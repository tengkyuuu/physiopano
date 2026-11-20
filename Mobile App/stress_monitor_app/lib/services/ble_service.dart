/// BLE GATT client service for the StressMonitor ESP32 device.
///
/// Handles scanning, connecting, subscribing to all 6 characteristics,
/// and parsing JSON payloads into typed data models.
///
/// Architecture: ChangeNotifier so the UI rebuilds on every BLE update.
/// The ESP32 notifies at 1 Hz (BLE_NOTIFY_INTERVAL = 1000ms in firmware).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/sensor_data.dart';
import '../models/session.dart';
import 'storage_service.dart';
import 'database_service.dart';
import 'baseline_engine.dart';
import 'change_detector.dart';
import 'baseline_service.dart';
import 'notification_service.dart';
import 'realtime_service.dart';
import 'sync_service.dart';

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class BleService extends ChangeNotifier {
  // ---- Storage ----
  final StorageService _storage = StorageService();
  DatabaseService? _dbService;
  bool _initialized = false;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ---- AI Services (injected after init) ----
  /// Personal-baseline change detection (replaces the WESAD classifier).
  ChangeDetector? _changeDetector;
  BaselineService? _baselineService;
  NotificationService? _notificationService;
  RealtimeService? _realtimeService;
  SyncService? _syncService;
  DateTime? _lastLivePush;

  // Current authenticated user ID — used for auto-calibration completion
  // and per-user session isolation.
  String _currentUserId = '';

  // Timer that auto-completes baseline calibration after sufficient data.
  Timer? _autoCalibTimer;

  // Calibration countdown tracking (exposed to UI via getters).
  DateTime? _calibrationStartTime;
  Duration _calibrationDuration = const Duration(minutes: 2);

  /// Inject AI and notification services (called from main.dart after init).
  void setServices({
    ChangeDetector? changeDetector,
    BaselineService? baselineService,
    NotificationService? notificationService,
    DatabaseService? dbService,
    RealtimeService? realtimeService,
    SyncService? syncService,
  }) {
    _changeDetector = changeDetector;
    _baselineService = baselineService;
    _notificationService = notificationService;
    _dbService = dbService;
    _realtimeService = realtimeService;
    _syncService = syncService;
  }

  /// Set the current authenticated user ID.
  /// Called from _OnboardingGate after login to enable auto-calibration
  /// completion and per-user session isolation.
  void setUserId(String userId) {
    _currentUserId = userId;
    unawaited(_changeDetector?.loadForUser(userId));
  }

  /// Send a notification only if the person has that alert switched on in
  /// Settings ([prefKey] is a user_settings column; default on).
  Future<void> _notifyIfAllowed(String prefKey, Future<void>? Function() send) async {
    if (_currentUserId.isNotEmpty && _dbService != null) {
      final settings = await _dbService!.getSettings(_currentUserId);
      if ((settings?[prefKey] as int?) == 0) return;
    }
    await send();
  }

  /// Forget the signed-in person (sign-out / account switch): stops any
  /// recording and clears their sessions from memory. Local storage is kept.
  Future<void> clearUser() async {
    if (isRecording) {
      try {
        await stopRecording();
      } catch (_) {}
    }
    _currentUserId = '';
    _sessions.clear();
    notifyListeners();
  }

  /// Load sessions for the given user from SQLite (clears any stale sessions).
  /// Call this after authentication to enforce per-user session isolation.
  Future<void> loadSessionsForUser(String userId) async {
    _currentUserId = userId;
    await _changeDetector?.loadForUser(userId);
    if (_dbService != null) {
      final saved = await _dbService!.loadSessions(userId);
      _sessions.clear();
      _sessions.addAll(saved);
      notifyListeners();
    }
  }

  /// Start the 3-minute baseline calibration (user-triggered via the
  /// "Start Calibrating Baseline" button). Requires all sensors to be ready.
  Future<void> startBaselineCalibration() async {
    if (_baselineService == null || _currentUserId.isEmpty) return;
    if (_baselineService!.isCalibrating) return;
    _autoCalibTimer?.cancel();
    _calibrationDuration = _calibrationLength;
    _calibrationStartTime = DateTime.now();
    _baselineService!.startCalibration();
    _autoCalibTimer = Timer(_calibrationLength, () async {
      if (_state != BleConnectionState.connected) return;
      if (_baselineService != null &&
          _baselineService!.isCalibrating &&
          _currentUserId.isNotEmpty) {
        await _baselineService!.completeCalibration(_currentUserId);
        _calibrationStartTime = null;
        notifyListeners();
        // Push calibrated baseline to Firestore immediately
        if (_syncService != null) await _syncService!.syncAll();
      }
    });
    notifyListeners();
  }

  /// Clear the current baseline so the user can recalibrate.
  /// Returns the app to the "Start Calibrating Baseline" state.
  Future<void> resetForRecalibration() async {
    if (_baselineService == null || _currentUserId.isEmpty) return;
    _autoCalibTimer?.cancel();
    _calibrationStartTime = null;
    await _baselineService!.clearBaseline(_currentUserId);
    notifyListeners();
  }

  /// Initialize storage. Sessions are loaded per-user via [loadSessionsForUser]
  /// after authentication — never from Hive (which has no user-ID filtering).
  Future<void> init() async {
    if (_initialized) return;
    await _storage.init();
    _initialized = true;
  }

  // ---- Connection state ----
  BleConnectionState _state = BleConnectionState.disconnected;
  BleConnectionState get state => _state;
  String _statusMessage = 'Tap scan to find PHYSIOPAÑO device';
  String get statusMessage => _statusMessage;

  BluetoothDevice? _device;
  BluetoothDevice? get device => _device;
  final List<BluetoothDevice> _scanResults = [];
  List<BluetoothDevice> get scanResults => List.unmodifiable(_scanResults);

  StreamSubscription? _connectionSub;
  StreamSubscription? _scanSub;
  final List<StreamSubscription> _charSubs = [];
  final List<Timer> _pollTimers = [];

  // ---- Auto-reconnect ----
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  Timer? _reconnectTimer;
  DateTime? _lastBatteryAlert;

  // ---- Live sensor data (latest values) ----
  HRData _hr = HRData.empty();
  HRVData _hrv = HRVData.empty();
  GSRData _gsr = GSRData.empty();
  TempData _temp = TempData.empty();
  MotionData _motion = MotionData.empty();
  StressData _stress = StressData.empty();

  HRData get hr => _hr;
  HRVData get hrv => _hrv;
  GSRData get gsr => _gsr;
  TempData get temp => _temp;
  MotionData get motion => _motion;
  StressData get stress => _stress;

  // ---- Sensor readiness flags (all must be true before data is processed) ----
  bool _hrReady = false;
  bool _hrvReady = false;
  bool _gsrReady = false;
  bool _tempReady = false;
  bool _motionReady = false;

  /// Whether all 5 physiological sensors have reported valid data.
  /// HR requires an actual valid BPM reading (not just the characteristic arriving)
  /// because the MAX30102 PPG sensor takes time to lock on to a pulse.
  /// The "Waiting" phase ends — and "Start Calibrating" appears — only when
  /// this is true, i.e. when the firmware has detected a real heart rate.
  bool get allSensorsReady =>
      _hrReady && _hr.valid && _hrvReady && _gsrReady && _tempReady && _motionReady;

  /// Human-readable list of sensors that are still waiting for data.
  List<String> get pendingSensors {
    final pending = <String>[];
    if (!_hrReady || !_hr.valid) pending.add('HR (detecting pulse...)');
    if (!_hrvReady) pending.add('HRV');
    if (!_gsrReady) pending.add('GSR');
    if (!_tempReady) pending.add('Temp');
    if (!_motionReady) pending.add('Motion');
    return pending;
  }

  /// Whether baseline calibration is currently running.
  bool get isCalibrating => _baselineService?.isCalibrating ?? false;

  /// Whether baseline calibration is complete and stress identification can begin.
  bool get isCalibrated => _baselineService?.isCalibrated ?? false;

  /// Progress of the current calibration phase [0.0 → 1.0].
  /// Driven by charHR notifications (1 Hz), so the UI updates every second.
  double get calibrationProgress {
    if (_calibrationStartTime == null) return 0.0;
    final elapsed = DateTime.now().difference(_calibrationStartTime!);
    return (elapsed.inMilliseconds / _calibrationDuration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  /// Remaining time in the active calibration phase.
  Duration get calibrationTimeRemaining {
    if (_calibrationStartTime == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_calibrationStartTime!);
    final remaining = _calibrationDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ---- Rolling history for live trend charts (last 5 minutes) ----
  static const int _historyMax = 300; // 5 min at 1 Hz
  final List<HRData> hrHistory = [];
  final List<HRVData> hrvHistory = [];
  final List<GSRData> gsrHistory = [];
  final List<TempData> tempHistory = [];
  final List<StressData> stressHistory = [];

  // ---- Session recording ----
  Session? _activeSession;
  Session? get activeSession => _activeSession;
  bool get isRecording => _activeSession != null;

  // Periodic save support — snapshot index at last DB write
  int _lastSavedSnapshotCount = 0;
  Timer? _periodicSaveTimer;

  // ---- Stored sessions ----
  final List<Session> _sessions = [];
  List<Session> get sessions => List.unmodifiable(_sessions);

  // =====================================================================
  //  SCAN
  // =====================================================================
  
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (demoFeed) {
      await _startDemoFeed();
      return;
    }
    _scanResults.clear();
    _state = BleConnectionState.scanning;
    _statusMessage = 'Requesting permissions...';
    notifyListeners();

    // Request permissions. On Android 12+ (API 31+) with neverForLocation,
    // location is NOT required for BLE scanning. Notification is needed on
    // Android 13+ for local notifications (battery alerts, etc.).
    if (!kIsWeb && Platform.isAndroid) {
      final perms = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.notification,
      ].request();

      // Bluetooth permissions are hard requirements — fail if denied.
      // Notification permission is optional — silently continue if denied.
      final blePerms = [Permission.bluetoothScan, Permission.bluetoothConnect];
      for (final p in blePerms) {
        final status = perms[p];
        if (status == PermissionStatus.permanentlyDenied) {
          _statusMessage =
              'Bluetooth permission denied. Opening App Settings — '
              'enable "Nearby devices" then return and scan again.';
          _state = BleConnectionState.error;
          notifyListeners();
          await openAppSettings();
          return;
        }
        if (status != PermissionStatus.granted &&
            status != PermissionStatus.limited) {
          _statusMessage =
              'Bluetooth permission denied. Please allow "Nearby devices" '
              'when prompted, then try scanning again.';
          _state = BleConnectionState.error;
          notifyListeners();
          return;
        }
      }
    }

    // ---- Check Bluetooth Adapter State ----
    // Use adapterStateNow (synchronous) instead of adapterState.first (async
    // platform call) to avoid a 1-2 s UI freeze on every scan button press.
    try {
      if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
        if (Platform.isAndroid) {
          _statusMessage = 'Turning on Bluetooth...';
          notifyListeners();
          await FlutterBluePlus.turnOn();
          await Future.delayed(const Duration(seconds: 2));
        } else {
          _statusMessage = 'Please enable Bluetooth to scan for devices.';
          _state = BleConnectionState.error;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('[BLE] Adapter check error: $e');
    }

    _statusMessage = 'Scanning for PHYSIOPAÑO device...';
    notifyListeners();

    if (kIsWeb) {
      _statusMessage = 'Web preview active. BLE is disabled on web.';
      _state = BleConnectionState.error;
      notifyListeners();
      return;
    }

    try {
      // Subscribe BEFORE starting scan so early results are not lost
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (!_scanResults.any((d) => d.remoteId == r.device.remoteId)) {
            _scanResults.add(r.device);
            notifyListeners();
          }
        }
      });

      // Stop any previous scan to avoid "already scanning" errors
      try { await FlutterBluePlus.stopScan(); } catch (_) {}

      await FlutterBluePlus.startScan(
        withServices: [Guid(BleUuids.service)],
        timeout: timeout,
      );

      await Future.delayed(timeout);
      await FlutterBluePlus.stopScan();

      if (_scanResults.isEmpty) {
        _statusMessage = 'No PHYSIOPAÑO device found. Check device is powered on.';
        _state = BleConnectionState.disconnected;
      } else {
        _statusMessage =
            'Found ${_scanResults.length} device(s). Tap to connect.';
        _state = BleConnectionState.disconnected;
      }
    } catch (e) {
      if (e is FlutterBluePlusException) {
        if (e.code == 2) {
          // SCAN_FAILED_APPLICATION_REGISTRATION_FAILED — previous scan not fully
          // deregistered. Toggle Bluetooth off/on or restart the app to clear it.
          _statusMessage = 'BLE scan failed. Toggle Bluetooth off and on, then try again.';
        } else if (e.code == 3) {
          _statusMessage = 'Please enable Location Services to scan for BLE devices.';
        } else {
          _statusMessage = 'Bluetooth error: ${e.description} (Code ${e.code})';
        }
      } else {
        _statusMessage = 'Scan error: $e. Make sure Bluetooth is enabled.';
      }
      _state = BleConnectionState.error;
    }
    notifyListeners();
  }

  void stopScan() {
    if (kIsWeb) return;
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    _state = BleConnectionState.disconnected;
    notifyListeners();
  }

  // =====================================================================
  //  CONNECT
  // =====================================================================
  Future<void> connectToDevice(BluetoothDevice device) async {
    _state = BleConnectionState.connecting;
    _statusMessage = 'Connecting to ${device.platformName}...';
    notifyListeners();

    try {
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      // Request higher MTU to avoid truncated JSON (firmware requests 256)
      await device.requestMtu(256);

      _device = device;
      _state = BleConnectionState.connected;
      _statusMessage = 'Connected to ${device.platformName}';
      // A successful connection ends the retry cycle; without this reset,
      // auto-reconnect would give up for good after a few drops.
      final wasReconnect = _reconnectAttempts > 0;
      _reconnectAttempts = 0;
      notifyListeners();
      if (wasReconnect) {
        unawaited(_notifyIfAllowed('notify_reconnect', () => _notificationService?.showReconnected()));
      }

      // Listen for disconnection
      _connectionSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      // Discover services and subscribe
      await _discoverAndSubscribe();
    } catch (e) {
      _statusMessage = 'Connection failed: $e';
      _state = BleConnectionState.error;
      notifyListeners();
    }
  }

  Future<void> _discoverAndSubscribe() async {
    if (_device == null) return;

    final services = await _device!.discoverServices();
    BluetoothService? stressService;

    for (final s in services) {
      if (s.uuid.toString().toLowerCase() == BleUuids.service) {
        stressService = s;
        break;
      }
    }

    if (stressService == null) {
      _statusMessage = 'PHYSIOPAÑO service not found on device';
      _state = BleConnectionState.error;
      notifyListeners();
      return;
    }

    // Subscribe to each characteristic; fall back to 1 Hz polling if CCCD missing
    for (final c in stressService.characteristics) {
      if (c.properties.notify || c.properties.read) {
        final uuid = c.uuid.toString().toLowerCase();

        // Check if CCCD (0x2902) descriptor exists — if not, notifications won't work
        final hasCccd = c.descriptors.any(
          (d) => d.uuid.toString().toLowerCase().contains('2902'),
        );

        if (hasCccd && c.properties.notify) {
          await c.setNotifyValue(true);
          final sub = c.lastValueStream.listen((value) {
            _onCharacteristicUpdate(uuid, value);
          });
          _charSubs.add(sub);
        } else if (c.properties.read) {
          // No CCCD — poll at 1 Hz so we still get data.
          // Guard against ghost callbacks after disconnect: bail out if
          // state is no longer connected before processing the read result.
          final t = Timer.periodic(const Duration(seconds: 1), (_) async {
            if (_state != BleConnectionState.connected || _device == null) return;
            try {
              final val = await c.read();
              if (val.isNotEmpty && _state == BleConnectionState.connected) {
                _onCharacteristicUpdate(uuid, val);
              }
            } catch (_) {}
          });
          _pollTimers.add(t);
        }
      }
    }

    _statusMessage = 'Subscribed to all characteristics';
    notifyListeners();
  }

  // =====================================================================
  //  DEMO FEED (compile-time, for recordings without a band on hand)
  // =====================================================================
  /// `--dart-define=DEMO_FEED=true` makes "Find my band" connect to a
  /// simulated band that sends firmware-format JSON packets at 1 Hz through
  /// the same parser as a real band, so readiness, calibration, baseline
  /// comparison, recording and charts all run their real logic. Off by default.
  static const bool demoFeed = bool.fromEnvironment('DEMO_FEED');

  /// Optional shorter calibration for recordings (seconds). Real: 180.
  static const int _demoCalibrationSeconds = int.fromEnvironment('DEMO_CALIBRATION_SECONDS', defaultValue: 0);

  Duration get _calibrationLength => _demoCalibrationSeconds > 0
      ? Duration(seconds: _demoCalibrationSeconds)
      : const Duration(minutes: 3);

  Timer? _demoTimer;
  int _demoTick = 0;
  final math.Random _demoRand = math.Random(20261119);
  double _demoGsr = 2.4;
  double _demoBattery = 86;

  Future<void> _startDemoFeed() async {
    _stopDemoFeed();
    _scanResults.clear();
    _state = BleConnectionState.scanning;
    _statusMessage = 'Scanning for PHYSIOPAÑO band...';
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 1800));
    _state = BleConnectionState.connecting;
    _statusMessage = 'Connecting to PHYSIOPANO-01...';
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 1400));
    _state = BleConnectionState.connected;
    _statusMessage = 'Connected to PHYSIOPANO-01';
    _reconnectAttempts = 0;
    _demoTick = 0;
    notifyListeners();
    _demoTimer = Timer.periodic(const Duration(seconds: 1), (_) => _demoStep());
  }

  void _stopDemoFeed() {
    _demoTimer?.cancel();
    _demoTimer = null;
  }

  double _jitter(double amp) => (_demoRand.nextDouble() * 2 - 1) * amp;

  void _demoSend(String uuid, Map<String, dynamic> m) =>
      _onCharacteristicUpdate(uuid, utf8.encode(jsonEncode(m)));

  /// One second of a calm, seated wearer. Sensors come online one by one
  /// over the first ~12 s, the way a real band settles on the wrist.
  void _demoStep() {
    final t = _demoTick++;
    // Breathing (~0.25 Hz) modulates heart rate; a slow wander on top.
    final breath = math.sin(t * 2 * math.pi / 4.2);
    final wander = math.sin(t * 2 * math.pi / 95);
    final bpm = (71 + 2.6 * breath + 1.8 * wander + _jitter(0.8)).round();
    _demoSend(BleUuids.charHR, {
      'bpm': t < 3 ? 0 : bpm,
      'valid': t >= 3,
      'sqi': t < 3 ? 0.35 : double.parse((0.86 + _jitter(0.06)).toStringAsFixed(2)),
    });
    if (t >= 5) {
      final rmssd = 42 + 4 * math.sin(t * 2 * math.pi / 60) + _jitter(1.5);
      _demoSend(BleUuids.charHRV, {
        'rmssd': double.parse(rmssd.toStringAsFixed(1)),
        'sdnn': double.parse((rmssd * 1.32 + _jitter(1.2)).toStringAsFixed(1)),
        'pnn50': double.parse((22 + _jitter(2.5)).toStringAsFixed(1)),
      });
    }
    if (t >= 7) {
      // Tonic skin conductance drifts slowly, with occasional small phasic rises.
      _demoGsr += _jitter(0.015) + (t % 37 == 0 ? 0.18 : 0) - (_demoGsr - 2.4) * 0.02;
      _demoSend(BleUuids.charGSR, {
        'us': double.parse(_demoGsr.toStringAsFixed(2)),
        'raw': (1780 + (_demoGsr - 2.4) * 160 + _jitter(6)).round(),
      });
    }
    if (t >= 9) {
      _demoSend(BleUuids.charTemp, {
        'skin': double.parse((33.4 + 0.15 * math.sin(t * 2 * math.pi / 240) + _jitter(0.03)).toStringAsFixed(2)),
        'ambient': double.parse((27.6 + _jitter(0.05)).toStringAsFixed(2)),
      });
    }
    if (t >= 11) {
      _demoSend(BleUuids.charMotion, {
        'ax': double.parse((0.03 + _jitter(0.01)).toStringAsFixed(3)),
        'ay': double.parse((-0.06 + _jitter(0.01)).toStringAsFixed(3)),
        'az': double.parse((0.99 + _jitter(0.008)).toStringAsFixed(3)),
      });
    }
    if (t % 5 == 0) {
      _demoBattery = math.max(20, _demoBattery - 0.02);
      _demoSend(BleUuids.charStress, {'cal': isCalibrated, 'bat': _demoBattery.round()});
    }
  }

  // =====================================================================
  //  PARSE BLE NOTIFICATIONS (with JSON validation)
  // =====================================================================
  void _onCharacteristicUpdate(String uuid, List<int> value) {
    if (value.isEmpty) return;

    final jsonStr = utf8.decode(value, allowMalformed: true);

    // JSON validation — reject non-JSON payloads
    if (!jsonStr.trimLeft().startsWith('{')) {
      debugPrint('[BLE] Invalid JSON on $uuid: $jsonStr');
      return;
    }

    try {
      // ---- Step 1: Parse the incoming characteristic ----
      switch (uuid) {
        case BleUuids.charHR:
          _hr = HRData.fromJson(jsonStr);
          _hrReady = true; // characteristic received — record even while BPM is still locking
          _pushHistory(hrHistory, _hr);
          break;
        case BleUuids.charHRV:
          _hrv = HRVData.fromJson(jsonStr);
          _hrvReady = true;
          _pushHistory(hrvHistory, _hrv);
          break;
        case BleUuids.charGSR:
          _gsr = GSRData.fromJson(jsonStr);
          _gsrReady = _gsr.microSiemens > 0;
          _pushHistory(gsrHistory, _gsr);
          break;
        case BleUuids.charTemp:
          _temp = TempData.fromJson(jsonStr);
          _tempReady = _temp.skin > 20; // plausible skin temp range
          _pushHistory(tempHistory, _temp);
          break;
        case BleUuids.charMotion:
          _motion = MotionData.fromJson(jsonStr);
          _motionReady = true; // accelerometer always valid if parsed
          break;
        case BleUuids.charStress:
          // Only process stress/AI when ALL other sensors have valid data.
          // This ensures the classifier never operates on incomplete
          // multimodal input, which would compromise thesis data integrity.
          if (!allSensorsReady) {
            debugPrint('[BLE] Stress characteristic received but sensors '
                'not ready. Waiting for: ${pendingSensors.join(", ")}');
            notifyListeners(); // still update UI to show pending state
            return;
          }
          // Do NOT classify during baseline calibration — the model needs
          // a stable personalized baseline before producing valid stress indices.
          // Showing a stress index during calibration would be misleading because
          // it uses WESAD population statistics, not the user's personal baseline.
          if (_baselineService != null && _baselineService!.isCalibrating) {
            notifyListeners();
            return;
          }
          _handleFeatureVector(jsonStr);
          break;
      }

      // ---- Step 2: Feed calibration service during baseline collection ----
      if (_baselineService != null && _baselineService!.isCalibrating) {
        // Only feed calibration when all sensors report valid data
        if (allSensorsReady) {
          _baselineService!.addSample(_hr, _hrv, _gsr, _temp, _motion);
        }
      }

      // ---- Step 4: Record snapshot on every HR update when all sensors valid ----
      // charStress (26ad) may be unavailable on older firmware (handle limit).
      // charHR fires every BLE_NOTIFY_INTERVAL (1 Hz) and is always received.
      if (isRecording && uuid == BleUuids.charHR && allSensorsReady) {
        _activeSession!.snapshots.add(SensorSnapshot(
          hr: _hr,
          hrv: _hrv,
          gsr: _gsr,
          temp: _temp,
          motion: _motion,
          stress: _stress,
          timestamp: DateTime.now(),
        ));
      }

      // ---- Step 5: Compare with the person's own baseline (1 Hz) ----
      if (uuid == BleUuids.charHR && allSensorsReady) {
        _updateFromBaseline();
      }

      // Push live reading to Realtime Database every 5 s for admin monitor.
      if (uuid == BleUuids.charHR) {
        final now = DateTime.now();
        if (_lastLivePush == null ||
            now.difference(_lastLivePush!).inSeconds >= 5) {
          _lastLivePush = now;
          _realtimeService?.pushLive(
            hrBpm: _hr.valid ? _hr.bpm : 0,
            hrvRmssd: _hrv.valid ? _hrv.rmssd : 0,
            gsrUs: _gsr.microSiemens,
            tempSkin: _temp.skin,
            motionMag: _motion.mag,
            stressIndex: _stress.index >= 0 ? _stress.index : -1,
            stressLabel: _stress.label,
          );
        }
      }

      // Battery low notification
      if (_stress.battery > 0 && _stress.battery <= 15) {
        final now = DateTime.now();
        if (_lastBatteryAlert == null ||
            now.difference(_lastBatteryAlert!).inMinutes >= 10) {
          _lastBatteryAlert = now;
          final level = _stress.battery;
          unawaited(_notifyIfAllowed('notify_battery', () => _notificationService?.showBatteryLow(level)));
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[BLE] Parse error on $uuid: $e  raw: $jsonStr');
    }
  }

  void _pushHistory<T>(List<T> list, T item) {
    list.add(item);
    if (list.length > _historyMax) list.removeAt(0);
  }

  // =====================================================================
  //  DISCONNECT
  // =====================================================================
  void _onDisconnected() {
    _reconnectTimer?.cancel(); // prevent stacking reconnect timers
    _realtimeService?.clearLive();
    _lastLivePush = null;

    // Save active recording session before cleanup (prevent data loss)
    if (_activeSession != null) {
      _periodicSaveTimer?.cancel();
      _periodicSaveTimer = null;
      _activeSession!.endTime = DateTime.now();
      final interrupted = _activeSession!;
      _activeSession = null;
      _lastSavedSnapshotCount = 0;
      _sessions.insert(0, interrupted);
      _storage.saveSession(interrupted);
      _dbService?.saveSession(interrupted); // full save — handles dedup
      if (_syncService != null) unawaited(_syncService!.syncAll());
      debugPrint('[BLE] Active session saved on disconnect (${interrupted.snapshots.length} snapshots)');
    }

    _cleanup();
    // Try auto-reconnect if we had a device
    if (_device != null && _reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      _state = BleConnectionState.connecting;
      final attempt = _reconnectAttempts;
      _statusMessage =
          'Reconnecting (attempt $attempt/$_maxReconnectAttempts)...';
      notifyListeners();
      final device = _device!;
      _reconnectTimer = Timer(
        Duration(seconds: 2 * _reconnectAttempts),
        () => connectToDevice(device),
      );
      return;
    }
    _state = BleConnectionState.disconnected;
    _statusMessage = 'Disconnected — tap scan to reconnect';
    _device = null;
    _reconnectAttempts = 0;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _stopDemoFeed();
    _reconnectAttempts = _maxReconnectAttempts; // Prevent auto-reconnect
    _reconnectTimer?.cancel();
    // Cancel connection listener BEFORE disconnecting to prevent
    // _onDisconnected() from firing and double-cleaning up.
    _connectionSub?.cancel();
    _connectionSub = null;
    _cleanup();
    final dev = _device;
    _device = null;
    _state = BleConnectionState.disconnected;
    _statusMessage = 'Disconnected — tap scan to reconnect';
    _reconnectAttempts = 0;
    notifyListeners();
    if (dev != null) {
      try { await dev.disconnect(); } catch (_) {}
    }
  }

  // =====================================================================
  //  FIRMWARE STATUS PACKET (charStress)
  // =====================================================================
  /// The firmware still sends its feature packet; the app now uses it only
  /// for battery and calibration status. Change detection runs on the phone
  /// against the person's own baseline (see [_updateFromBaseline]).
  void _handleFeatureVector(String jsonStr) {
    try {
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      _stress = StressData(
        index: _stress.index,
        category: _stress.category,
        label: _stress.label,
        probability: _stress.probability,
        chronic: _stress.chronic,
        motionArtifact: _stress.motionArtifact,
        calibrated: data['cal'] as bool? ?? _stress.calibrated,
        battery: (data['bat'] as num?)?.toInt() ?? _stress.battery,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      // Ignore malformed packets.
    }
  }

  // =====================================================================
  //  PERSONAL BASELINE (1 Hz)
  // =====================================================================
  /// Compares the live reading with the person's own usual for this time of
  /// day. Replaces the WESAD Random Forest, which collapsed to "Medium" on our
  /// sensors. [StressData.index] now carries DISTANCE FROM YOUR USUAL
  /// (0–100 = 0–3σ) and the label says so in plain words; it is not a
  /// population stress level.
  void _updateFromBaseline() {
    final cd = _changeDetector;
    if (cd == null) return;
    final live = cd.ingest(
      hr: _hr.valid ? _hr.bpm.toDouble() : null,
      rmssd: _hrv.valid ? _hrv.rmssd : null,
      eda: _gsr.microSiemens > 0 ? _gsr.microSiemens : null,
      temp: (_temp.skin > 20 && _temp.skin < 45) ? _temp.skin : null,
      accelMag: _motion.mag,
    );
    final moving = (_motion.mag - 1.0).abs() > cd.engine.config.stillnessG;
    if (live == null || !live.hasBaseline) {
      _stress = StressData(
        index: -1,
        category: -1,
        label: 'Learning your usual',
        probability: 0,
        chronic: false,
        motionArtifact: moving,
        calibrated: _stress.calibrated,
        battery: _stress.battery,
        timestamp: DateTime.now(),
      );
      return;
    }
    final level = live.level;
    _stress = StressData(
      index: (live.maxAbsZ / 3).clamp(0.0, 1.0) * 100,
      category: level.index,
      label: switch (level) {
        DeviationLevel.within => 'Within your usual',
        DeviationLevel.notable => 'A little different from your usual',
        DeviationLevel.marked => 'Different from your usual',
      },
      probability: 0,
      chronic: cd.isChanging,
      motionArtifact: moving,
      calibrated: _stress.calibrated,
      battery: _stress.battery,
      timestamp: DateTime.now(),
    );
    _pushHistory(stressHistory, _stress);
  }

  /// Reset all sensor readiness flags (called on disconnect/cleanup).
  void _resetSensorReadiness() {
    _hrReady = false;
    _hrvReady = false;
    _gsrReady = false;
    _tempReady = false;
    _motionReady = false;
  }

  void _cleanup() {
    _autoCalibTimer?.cancel();
    _autoCalibTimer = null;
    _periodicSaveTimer?.cancel();
    _periodicSaveTimer = null;
    _calibrationStartTime = null;
    _scanSub?.cancel();
    _scanSub = null;
    for (final sub in _charSubs) {
      sub.cancel();
    }
    _charSubs.clear();
    for (final t in _pollTimers) {
      t.cancel();
    }
    _pollTimers.clear();
    _connectionSub?.cancel();
    _connectionSub = null;
    _resetSensorReadiness();
    unawaited(_changeDetector?.flush());
  }

  // =====================================================================
  //  SESSION RECORDING
  // =====================================================================
  void startRecording({required String userId, String? notes}) {
    // Keep userId up-to-date in case auto-calibration completes during recording.
    _currentUserId = userId;
    // Reset feature extractor so stale data from a previous session does
    // not contaminate the next session's classification windows.
    _lastSavedSnapshotCount = 0;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _activeSession = Session(
      id: id,
      userId: userId,
      startTime: DateTime.now(),
      notes: notes,
    );
    // Save to DB every 30 s so data survives a crash or force-kill (bug 1/3 fix)
    _periodicSaveTimer?.cancel();
    _periodicSaveTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _saveSessionProgress(),
    );
    notifyListeners();
  }

  /// Incrementally persist the active session to SQLite during recording.
  /// Writes only new snapshots since the last call — prevents data loss on crash.
  Future<void> _saveSessionProgress() async {
    if (_activeSession == null || _dbService == null) return;
    final session = _activeSession!;
    await _dbService!.upsertSessionRow(session);
    if (session.snapshots.length > _lastSavedSnapshotCount) {
      final newSnaps =
          session.snapshots.sublist(_lastSavedSnapshotCount);
      await _dbService!.appendSnapshots(session.id, newSnaps);
      _lastSavedSnapshotCount = session.snapshots.length;
    }
  }

  Future<Session?> stopRecording() async {
    if (_activeSession == null) return null;
    _periodicSaveTimer?.cancel();
    _periodicSaveTimer = null;
    _activeSession!.endTime = DateTime.now();
    final completed = _activeSession!;
    _sessions.insert(0, completed);
    _activeSession = null;
    _lastSavedSnapshotCount = 0;
    // Full save — deletes any periodic-save snapshots then re-inserts all
    await _storage.saveSession(completed);
    if (_dbService != null) {
      await _dbService!.saveSession(completed);
    }
    notifyListeners();
    // Push to Firestore immediately so raw data appears in admin without waiting
    // for the 5-minute periodic sync
    if (_syncService != null) unawaited(_syncService!.syncAll());
    return completed;
  }

  Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    await _storage.deleteSession(id);
    if (_dbService != null) {
      await _dbService!.deleteSession(id);
    }
    notifyListeners();
  }

  // =====================================================================
  //  CLEANUP
  // =====================================================================
  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _cleanup();
    super.dispose();
  }
}
