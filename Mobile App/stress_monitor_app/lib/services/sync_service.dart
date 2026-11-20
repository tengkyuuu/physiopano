/// Cloud sync service — uploads data from local SQLite to Firestore.
///
/// Data flow: ESP32 → BLE → App (BleService) → SQLite → Firestore (this service)
///
/// Syncs: user profile, baseline calibration, sessions (with summaries).
/// Triggers: connectivity change, periodic timer, manual call.
library;

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'auth_service.dart';
import '../models/session.dart';

class SyncService extends ChangeNotifier {
  final DatabaseService _db;
  final AuthService _auth;
  final _firestore = FirebaseFirestore.instance;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  StreamSubscription? _connectivitySub;
  Timer? _periodicTimer;

  SyncService(this._db, this._auth);

  /// Start listening for connectivity changes and periodic sync.
  void startListening() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        syncAll();
      }
    });

    // Periodic sync every 5 minutes
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => syncAll(),
    );

    // Initial sync on start
    syncAll();
  }

  /// Stop listening.
  void stopListening() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Sync everything: profile, baseline, sessions.
  Future<void> syncAll() async {
    if (_isSyncing || !_auth.isSignedIn) return;

    // Check incognito mode
    final settings = await _db.getSettings(_auth.userId);
    final incognito = (settings?['incognito_mode'] as int? ?? 0) == 1;
    if (incognito) return;

    _isSyncing = true;
    notifyListeners();

    try {
      await _syncProfile();
      await _syncBaseline();
      await _syncSessions();
      _lastSyncTime = DateTime.now();
    } catch (e) {
      debugPrint('[Sync] Error during sync: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // =========================================================================
  //  HELPERS
  // =========================================================================

  /// Format a DateTime as "YYYY-MM-DD_HHmmss" — used as Firestore document IDs
  /// so they are human-readable in the console (e.g. "2024-03-23_143022").
  String _docId(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}_'
      '${dt.hour.toString().padLeft(2, '0')}'
      '${dt.minute.toString().padLeft(2, '0')}'
      '${dt.second.toString().padLeft(2, '0')}';

  /// Format an epoch-minutes key as "YYYY-MM-DD_HHmm" — used as reading doc IDs
  /// (e.g. "2024-03-23_1430" instead of a raw number like "29062102").
  String _minuteDocId(int epochMinutes) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMinutes * 60000);
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}_'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  // =========================================================================
  //  SYNC METHODS
  // =========================================================================

  /// Upload user profile to Firestore.
  Future<void> _syncProfile() async {
    if (!_auth.isSignedIn) return;

    final settings = await _db.getSettings(_auth.userId);
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Only include optional fields when they have a local value — this
      // prevents a race condition on first login where the local SQLite is
      // still empty from overwriting the values already written by register().
      final data = <String, dynamic>{
        'email': user.email ?? '',
        'display_name': settings?['display_name'] ?? user.displayName ?? '',
        'onboarding_complete':
            (settings?['onboarding_complete'] as int? ?? 0) == 1,
        'last_sync': FieldValue.serverTimestamp(),
        'created_at': user.metadata.creationTime != null
            ? Timestamp.fromDate(user.metadata.creationTime!)
            : null,
      };
      final studentId = settings?['student_id'] as String?;
      if (studentId != null && studentId.isNotEmpty) data['student_id'] = studentId;
      final eName = settings?['emergency_name'] as String?;
      if (eName != null && eName.isNotEmpty) data['emergency_name'] = eName;
      final eEmail = settings?['emergency_email'] as String?;
      if (eEmail != null && eEmail.isNotEmpty) data['emergency_email'] = eEmail;
      final ePhone = settings?['emergency_phone'] as String?;
      if (ePhone != null && ePhone.isNotEmpty) data['emergency_phone'] = ePhone;

      await _firestore.collection('users').doc(_auth.userId).set(
        data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Sync] Profile sync failed: $e');
    }
  }

  /// Upload baseline calibration data.
  Future<void> _syncBaseline() async {
    if (!_auth.isSignedIn) return;

    final baseline = await _db.getBaseline(_auth.userId);
    if (baseline == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(_auth.userId)
          .collection('baseline')
          .doc('current')
          .set({
        'hr_mean': baseline['hr_mean'],
        'hr_std': baseline['hr_std'],
        'hrv_mean': baseline['hrv_mean'],
        'hrv_std': baseline['hrv_std'],
        'gsr_mean': baseline['gsr_mean'],
        'gsr_std': baseline['gsr_std'],
        'temp_mean': baseline['temp_mean'],
        'temp_std': baseline['temp_std'],
        'accmag_mean': baseline['accmag_mean'],
        'accmag_std': baseline['accmag_std'],
        'sample_count': baseline['sample_count'],
        'calibrated_at': baseline['calibrated_at'] != null
            ? Timestamp.fromMillisecondsSinceEpoch(
                baseline['calibrated_at'] as int)
            : null,
        'uploaded_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Sync] Baseline sync failed: $e');
    }
  }

  /// Upload unsynced sessions to Firestore.
  Future<void> _syncSessions() async {
    final unsyncedIds = await _db.getUnsyncedSessionIds();
    _pendingCount = unsyncedIds.length;
    notifyListeners();

    for (final id in unsyncedIds) {
      final session = await _db.loadSessionWithSnapshots(id);
      if (session == null) continue;

      try {
        // Use human-readable "YYYY-MM-DD_HHmmss" as the document ID so the
        // Firestore console shows meaningful names instead of raw timestamps.
        final docRef = _firestore
            .collection('users')
            .doc(_auth.userId)
            .collection('sessions')
            .doc(_docId(session.startTime));

        // Build snapshot summaries (aggregate per-minute instead of raw)
        final snapshotSummaries = <Map<String, dynamic>>[];
        if (session.snapshots.isNotEmpty) {
          // Group snapshots by minute for compact cloud storage
          final byMinute = <int, List<dynamic>>{};
          for (final snap in session.snapshots) {
            final minuteKey = snap.timestamp.millisecondsSinceEpoch ~/ 60000;
            byMinute.putIfAbsent(minuteKey, () => []).add(snap);
          }

          for (final entry in byMinute.entries) {
            final snaps = entry.value;
            final validHr =
                snaps.where((s) => s.hr.valid).map((s) => s.hr.bpm);
            final validStress = snaps
                .where((s) => s.stress.index >= 0)
                .map((s) => s.stress.index);
            final gsrValues = snaps.map((s) => s.gsr.microSiemens);
            final tempValues =
                snaps.where((s) => s.temp.skin > 0).map((s) => s.temp.skin);
            // Accelerometer magnitude — important parameter for motion analysis
            final accelValues = snaps.map((s) => s.motion.mag);
            final hrvRmssd = snaps
                .where((s) => s.hrv.valid)
                .map((s) => s.hrv.rmssd);

            snapshotSummaries.add({
              'minute': entry.key,
              'timestamp': Timestamp.fromMillisecondsSinceEpoch(
                  entry.key * 60000),
              'avg_hr': validHr.isNotEmpty
                  ? (validHr.reduce((a, b) => a + b) / validHr.length)
                      .round()
                  : 0,
              'avg_stress': validStress.isNotEmpty
                  ? double.parse(
                      (validStress.reduce((a, b) => a + b) /
                              validStress.length)
                          .toStringAsFixed(1))
                  : -1,
              'avg_gsr': gsrValues.isNotEmpty
                  ? double.parse(
                      (gsrValues.reduce((a, b) => a + b) / gsrValues.length)
                          .toStringAsFixed(2))
                  : 0,
              'avg_temp': tempValues.isNotEmpty
                  ? double.parse(
                      (tempValues.reduce((a, b) => a + b) / tempValues.length)
                          .toStringAsFixed(2))
                  : 0,
              // Accelerometer magnitude — avg and max for motion artifact analysis
              'avg_accel_mag': accelValues.isNotEmpty
                  ? double.parse(
                      (accelValues.reduce((a, b) => a + b) / accelValues.length)
                          .toStringAsFixed(3))
                  : 0,
              'max_accel_mag': accelValues.isNotEmpty
                  ? double.parse(
                      accelValues.reduce((a, b) => a > b ? a : b)
                          .toStringAsFixed(3))
                  : 0,
              // HRV RMSSD — key autonomic nervous system indicator
              'avg_hrv_rmssd': hrvRmssd.isNotEmpty
                  ? double.parse(
                      (hrvRmssd.reduce((a, b) => a + b) / hrvRmssd.length)
                          .toStringAsFixed(1))
                  : -1,
              'motion_artifact_count': snaps
                  .where((s) => s.stress.motionArtifact)
                  .length,
              'sample_count': snaps.length,
            });
          }
        }

        // Compute session-level aggregates for all sensor channels
        final validHrv = session.snapshots
            .where((s) => s.hrv.valid && s.hrv.rmssd > 0);
        final avgHrv = validHrv.isNotEmpty
            ? validHrv.map((s) => s.hrv.rmssd).reduce((a, b) => a + b) /
                validHrv.length
            : -1.0;

        final validGsr = session.snapshots
            .where((s) => s.gsr.microSiemens > 0);
        final avgGsr = validGsr.isNotEmpty
            ? validGsr
                    .map((s) => s.gsr.microSiemens)
                    .reduce((a, b) => a + b) /
                validGsr.length
            : -1.0;

        final validTemp =
            session.snapshots.where((s) => s.temp.skin > 20);
        final avgTemp = validTemp.isNotEmpty
            ? validTemp.map((s) => s.temp.skin).reduce((a, b) => a + b) /
                validTemp.length
            : -1.0;

        final validMotion =
            session.snapshots.where((s) => s.motion.mag > 0);
        final avgMotion = validMotion.isNotEmpty
            ? validMotion.map((s) => s.motion.mag).reduce((a, b) => a + b) /
                validMotion.length
            : -1.0;

        final startDt = session.startTime;
        await docRef.set({
          'date': '${startDt.year.toString().padLeft(4, '0')}-'
              '${startDt.month.toString().padLeft(2, '0')}-'
              '${startDt.day.toString().padLeft(2, '0')}',
          'start_time': Timestamp.fromDate(startDt),
          'end_time': session.endTime != null
              ? Timestamp.fromDate(session.endTime!)
              : null,
          'notes': session.notes,
          'tags': session.tags,
          'snapshot_count': session.snapshotCount,
          'avg_stress': session.avgStressIndex,
          'avg_hr': session.avgHeartRate,
          'avg_hrv': double.parse(avgHrv.toStringAsFixed(2)),
          'avg_gsr': double.parse(avgGsr.toStringAsFixed(3)),
          'avg_temp': double.parse(avgTemp.toStringAsFixed(2)),
          'avg_accel_mag': double.parse(avgMotion.toStringAsFixed(3)),
          'stress_distribution': session.stressDistribution,
          'duration_seconds': session.duration.inSeconds,
          'uploaded_at': FieldValue.serverTimestamp(),
        });

        // ── Per-minute summaries → readings/ ─────────────────────────────
        // Each document = one minute of averaged sensor data.
        // Firestore batches are limited to 500 operations — chunk if needed.
        if (snapshotSummaries.isNotEmpty) {
          const batchLimit = 499;
          for (var i = 0; i < snapshotSummaries.length; i += batchLimit) {
            final chunk = snapshotSummaries.sublist(
              i, (i + batchLimit).clamp(0, snapshotSummaries.length));
            final batch = _firestore.batch();
            for (final summary in chunk) {
              final readingRef = docRef
                  .collection('readings')
                  .doc(_minuteDocId(summary['minute'] as int));
              batch.set(readingRef, summary);
            }
            await batch.commit();
          }
        }

        // ── Per-second raw snapshots → raw_readings/ ──────────────────────
        // Every second of all 6 sensor channels stored individually.
        // Doc ID format: "YYYY-MM-DD_HHmmss" for readability.
        // Includes full accelerometer (ax, ay, az, mag) which was missing
        // from previous cloud syncs.
        if (session.snapshots.isNotEmpty) {
          const batchLimit = 499;
          for (var i = 0; i < session.snapshots.length; i += batchLimit) {
            final chunk = session.snapshots.sublist(
              i, (i + batchLimit).clamp(0, session.snapshots.length));
            final batch = _firestore.batch();
            for (final snap in chunk) {
              final rawRef = docRef
                  .collection('raw_readings')
                  .doc(_docId(snap.timestamp));
              batch.set(rawRef, {
                'timestamp': Timestamp.fromDate(snap.timestamp),
                // Heart Rate
                'bpm':        snap.hr.bpm,
                'hr_valid':   snap.hr.valid,
                'hr_sqi':     double.parse(snap.hr.sqi.toStringAsFixed(3)),
                // HRV
                'hrv_rmssd':  double.parse(snap.hrv.rmssd.toStringAsFixed(2)),
                'hrv_sdnn':   double.parse(snap.hrv.sdnn.toStringAsFixed(2)),
                'hrv_pnn50':  double.parse(snap.hrv.pnn50.toStringAsFixed(2)),
                // GSR / EDA
                'gsr_us':     double.parse(
                    snap.gsr.microSiemens.toStringAsFixed(3)),
                'gsr_raw':    snap.gsr.raw,
                // Temperature
                'temp_skin':     double.parse(
                    snap.temp.skin.toStringAsFixed(2)),
                'temp_ambient':  double.parse(
                    snap.temp.ambient.toStringAsFixed(2)),
                // Accelerometer (ax, ay, az, mag)
                'accel_x':    double.parse(snap.motion.ax.toStringAsFixed(4)),
                'accel_y':    double.parse(snap.motion.ay.toStringAsFixed(4)),
                'accel_z':    double.parse(snap.motion.az.toStringAsFixed(4)),
                'accel_mag':  double.parse(snap.motion.mag.toStringAsFixed(4)),
                // Stress classification
                'stress_index': double.parse(
                    snap.stress.index.toStringAsFixed(2)),
                'stress_cat':   snap.stress.category,
                'stress_label': snap.stress.label,
                'stress_prob':  double.parse(
                    snap.stress.probability.toStringAsFixed(3)),
                'motion_artifact': snap.stress.motionArtifact,
                'calibrated':      snap.stress.calibrated,
                'battery':         snap.stress.battery,
              });
            }
            await batch.commit();
          }
        }

        await _db.markSynced(id);
        _pendingCount--;
        notifyListeners();
      } catch (e) {
        debugPrint('[Sync] Failed to sync session $id: $e');
      }
    }
  }

  /// Push current live sensor reading so admin can see real-time data.
  /// Writes to users/{uid}/live — throttled by caller to avoid excess writes.
  Future<void> reportLive({
    required int hrBpm,
    required double hrvRmssd,
    required double gsrUs,
    required double tempSkin,
    required double motionMag,
    required double stressIndex,
    required String stressLabel,
  }) async {
    if (!_auth.isSignedIn) return;
    try {
      await _firestore.collection('users').doc(_auth.userId).collection('live').doc('current').set({
        'hr_bpm': hrBpm,
        'hrv_rmssd': hrvRmssd,
        'gsr_us': gsrUs,
        'temp_skin': tempSkin,
        'motion_mag': motionMag,
        'stress_index': stressIndex,
        'stress_label': stressLabel,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Sync] Live update failed: $e');
    }
  }

  /// Force sync profile immediately (called after onboarding).
  Future<void> syncProfileNow() async {
    if (!_auth.isSignedIn) return;
    try {
      await _syncProfile();
    } catch (e) {
      debugPrint('[Sync] Manual profile sync failed: $e');
    }
  }

  /// Pull profile from Firestore into local SQLite.
  /// Called on login so display name, student ID, and emergency contacts
  /// are restored even after reinstall or login on a new device.
  Future<void> pullProfileFromCloud() async {
    if (!_auth.isSignedIn) return;
    try {
      final doc = await _firestore.collection('users').doc(_auth.userId).get();
      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;
      // Merge: only fields the cloud actually has a value for are taken, so a
      // partial cloud profile never blanks what is already on this phone
      // (e.g. the contact entered at sign-up). Local-only preferences are
      // untouched because saveSettings merges.
      final update = <String, dynamic>{};
      for (final key in ['display_name', 'student_id', 'emergency_name', 'emergency_email', 'emergency_phone']) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) update[key] = v;
      }
      // Completion only ever moves forward from the cloud (finished on another device).
      if (data['onboarding_complete'] == true) update['onboarding_complete'] = 1;
      await _db.saveSettings(_auth.userId, update);
      debugPrint('[Sync] Profile restored from cloud.');
    } catch (e) {
      debugPrint('[Sync] Pull profile from cloud failed: $e');
    }
  }

  /// Fetch all historical sessions from Firestore and save them locally.
  /// Called during onboarding/login so returning users get their data.
  Future<void> fetchSessionsFromCloud() async {
    if (!_auth.isSignedIn) return;
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_auth.userId)
          .collection('sessions')
          .orderBy('start_time', descending: true)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        final startTime = (data['start_time'] as Timestamp).toDate();
        final endTime = data['end_time'] != null ? (data['end_time'] as Timestamp).toDate() : null;
        
        final tagsDynamic = data['tags'] as List<dynamic>? ?? [];
        final tags = tagsDynamic.map((e) => e.toString()).toList();
        
        final dt = startTime;
        final sessionId = '${dt.year.toString().padLeft(4, '0')}-'
            '${dt.month.toString().padLeft(2, '0')}-'
            '${dt.day.toString().padLeft(2, '0')}_'
            '${dt.hour.toString().padLeft(2, '0')}'
            '${dt.minute.toString().padLeft(2, '0')}'
            '${dt.second.toString().padLeft(2, '0')}';

        final session = Session(
          id: sessionId,
          userId: _auth.userId,
          startTime: startTime,
          endTime: endTime,
          notes: data['notes'] as String?,
          tags: tags,
          cachedAvgStress: (data['avg_stress'] as num?)?.toDouble(),
          cachedSnapshotCount: (data['snapshot_count'] as num?)?.toInt(),
          cachedAvgHr: (data['avg_hr'] as num?)?.toDouble(),
        );

        await _db.upsertSessionRow(session);
        await _db.markSynced(session.id);
      }
      debugPrint('[Sync] Historical sessions fetched and saved locally.');
    } catch (e) {
      debugPrint('[Sync] Failed to fetch sessions: $e');
    }
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
