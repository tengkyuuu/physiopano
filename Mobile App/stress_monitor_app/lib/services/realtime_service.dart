/// Firebase Realtime Database service for live sensor streaming.
///
/// Writes current readings to live/{uid}/current at ~1Hz while connected.
/// Admin page and research dashboard can subscribe to get real-time updates.
library;

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class RealtimeService {
  final _db = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  /// Push a live sensor reading (called every 1–5 seconds from BleService).
  Future<void> pushLive({
    required int hrBpm,
    required double hrvRmssd,
    required double gsrUs,
    required double tempSkin,
    required double motionMag,
    required double stressIndex,
    required String stressLabel,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.ref('live/$uid/current').set({
        'hr_bpm': hrBpm,
        'hrv_rmssd': hrvRmssd,
        'gsr_us': gsrUs,
        'temp_skin': tempSkin,
        'motion_mag': motionMag,
        'stress_index': stressIndex,
        'stress_label': stressLabel,
        'ts': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[RTDB] pushLive failed: $e');
    }
  }

  /// Clear live data when device disconnects.
  Future<void> clearLive() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.ref('live/$uid/current').remove();
    } catch (e) {
      debugPrint('[RTDB] clearLive failed: $e');
    }
  }

  /// Stream of all active users' live data (for admin/research use).
  Stream<DatabaseEvent> get allLiveStream => _db.ref('live').onValue;
}
