/// Owns the personal-baseline engine for the signed-in person.
///
/// Replaces the old ChronicDetector, which raised "High Stress" alerts from a
/// population classifier and wrote chronic alerts to Firestore for an email
/// automation. This service:
///   - keeps the person's baseline on the phone (SharedPreferences, per user);
///   - compares each live reading with the person's own usual;
///   - re-assesses once a minute and, when a sustained change appears, OFFERS
///     a moment for themselves. Nobody else is contacted.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'baseline_engine.dart';
import 'database_service.dart';
import 'notification_service.dart';

class ChangeDetector extends ChangeNotifier {
  final NotificationService _notifications;
  final DatabaseService _db;

  ChangeDetector(this._notifications, this._db);

  static const _prefix = 'pp_baseline_engine_';
  static const _promptPrefix = 'pp_change_prompt_';

  /// Minimum gap between two prompts about the same change.
  static const promptCooldown = Duration(hours: 24);

  BaselineEngine _engine = BaselineEngine();
  String _uid = '';
  ChangeAssessment? _assessment;
  LiveDeviation? _live;
  DateTime? _lastPrompt;
  DateTime? _lastSave;

  ChangeAssessment? get assessment => _assessment;
  LiveDeviation? get live => _live;
  bool get isChanging => _assessment?.status == ChangeStatus.changing;
  bool get isLearning => (_assessment?.status ?? ChangeStatus.learning) == ChangeStatus.learning;
  bool get isSynthetic => _engine.synthetic;
  BaselineEngine get engine => _engine;

  Future<void> loadForUser(String uid) async {
    if (uid.isEmpty || uid == _uid) return;
    await _save(); // flush the previous person's state
    _uid = uid;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$uid');
    _engine = BaselineEngine();
    if (raw != null) {
      try {
        _engine = BaselineEngine.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('[ChangeDetector] Could not read saved baseline: $e');
      }
    }
    final p = prefs.getString('$_promptPrefix$uid');
    _lastPrompt = p == null ? null : DateTime.tryParse(p);
    _engine.catchUp(DateTime.now());
    _assessment = _engine.assess();
    notifyListeners();
  }

  /// Feed one live reading (~1 Hz). Returns the comparison with the usual.
  LiveDeviation? ingest({
    double? hr,
    double? rmssd,
    double? eda,
    double? temp,
    double? accelMag,
  }) {
    if (_uid.isEmpty) return null;
    final now = DateTime.now();
    final minuteDone = _engine.addSample(now,
        hr: hr, rmssd: rmssd, eda: eda, temp: temp, accelMag: accelMag);
    _live = _engine.live(now, hr: hr, rmssd: rmssd, eda: eda, temp: temp);
    if (minuteDone) unawaited(_onMinute(now));
    return _live;
  }

  Future<void> _onMinute(DateTime now) async {
    final before = _assessment?.status;
    _assessment = _engine.assess(now: now);
    if (_assessment!.status == ChangeStatus.changing && before != ChangeStatus.changing) {
      await _maybePrompt(now);
    }
    if (_lastSave == null || now.difference(_lastSave!) >= const Duration(minutes: 5)) {
      await _save();
    }
    notifyListeners();
  }

  Future<void> _maybePrompt(DateTime now) async {
    if (_lastPrompt != null && now.difference(_lastPrompt!) < promptCooldown) return;
    // Respect the person's notification choice (Settings > Changes from your usual).
    try {
      final settings = await _db.getSettings(_uid);
      if ((settings?['notify_high_stress'] as int?) == 0) return;
    } catch (_) {}
    _lastPrompt = now;
    final a = _assessment!;
    final since = a.changingSince;
    final sinceText = since == null ? 'the last few days' : _weekday(since);
    const title = 'A change from your usual';
    final body = 'Your body has been working harder than your usual since $sinceText. '
        'Want to do a 2-minute check-in?';
    await _notifications.showChangeNoticed(title: title, body: body);
    await _db.insertNotification(
      type: 'change_noticed',
      title: title,
      body: '$body ${a.summary}',
      userId: _uid,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_promptPrefix$_uid', now.toIso8601String());
  }

  static String _weekday(DateTime d) => const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
      ][d.weekday - 1];

  Future<void> _save() async {
    if (_uid.isEmpty) return;
    _lastSave = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$_uid', jsonEncode(_engine.toJson()));
  }

  /// Persist now (call on disconnect / app pause).
  Future<void> flush() => _save();

  /// Demo only: replace this person's history with labelled synthetic days.
  Future<void> seedDemoHistory() async {
    _engine.seedSyntheticHistory(now: DateTime.now());
    _lastPrompt = null;
    _assessment = _engine.assess();
    await _save();
    notifyListeners();
  }

  /// Forget the baseline (person's choice, or after a synthetic demo).
  Future<void> resetHistory() async {
    _engine.clear();
    _live = null;
    _lastPrompt = null;
    _assessment = _engine.assess();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$_uid');
    await prefs.remove('$_promptPrefix$_uid');
    notifyListeners();
  }
}
