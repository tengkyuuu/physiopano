/// Check-in history, kept on the phone per user. Nothing leaves the device
/// unless the person later chooses to share it with a support station.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/check_in.dart';

class CheckInStore {
  static const _prefix = 'pp_checkins_';
  static const _max = 100;

  static Future<List<CheckInResult>> load(String uid) async {
    if (uid.isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('$_prefix$uid') ?? const [];
    final out = <CheckInResult>[];
    for (final r in raw) {
      try {
        out.add(CheckInResult.fromJson(jsonDecode(r) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  static Future<void> add(String uid, CheckInResult result) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = [...(prefs.getStringList('$_prefix$uid') ?? const <String>[]), jsonEncode(result.toJson())];
    await prefs.setStringList('$_prefix$uid', raw.length > _max ? raw.sublist(raw.length - _max) : raw);
  }

  /// Most recent earlier result of the same instrument, for "compared with last time".
  static CheckInResult? previous(List<CheckInResult> history, Instrument i, DateTime before) {
    CheckInResult? best;
    for (final r in history) {
      if (r.instrument == i && r.takenAt.isBefore(before)) {
        if (best == null || r.takenAt.isAfter(best.takenAt)) best = r;
      }
    }
    return best;
  }
}
