/// Session model for recording physiological data over time.
///
/// A session captures a continuous recording period from the wearable device.
/// Sessions are stored locally using Hive for offline access.
library;

import 'dart:convert';
import 'sensor_data.dart';

class Session {
  final String id;
  final String userId; // owner — ensures sessions stay with the right account
  final DateTime startTime;
  DateTime? endTime;
  final List<SensorSnapshot> snapshots;
  String? notes;
  List<String> tags;
  // Pre-computed values when loaded from DB without snapshots
  double? _cachedAvgStress;
  int? _cachedSnapshotCount;
  double? _cachedAvgHr;

  Session({
    required this.id,
    required this.userId,
    required this.startTime,
    this.endTime,
    List<SensorSnapshot>? snapshots,
    this.notes,
    List<String>? tags,
    double? cachedAvgStress,
    int? cachedSnapshotCount,
    double? cachedAvgHr,
  })  : snapshots = snapshots ?? [],
        tags = tags ?? [],
        _cachedAvgStress = cachedAvgStress,
        _cachedSnapshotCount = cachedSnapshotCount,
        _cachedAvgHr = cachedAvgHr;

  /// Duration of the session
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  String get durationString {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  bool get isActive => endTime == null;

  int get snapshotCount =>
      snapshots.isNotEmpty ? snapshots.length : (_cachedSnapshotCount ?? 0);

  /// Average stress index across the session
  double get avgStressIndex {
    final valid = snapshots.where((s) => s.stress.index >= 0);
    if (valid.isEmpty) return _cachedAvgStress ?? -1;
    return valid.map((s) => s.stress.index).reduce((a, b) => a + b) / valid.length;
  }

  /// Average heart rate
  double get avgHeartRate {
    final valid = snapshots.where((s) => s.hr.valid);
    if (valid.isEmpty) return _cachedAvgHr ?? -1;
    return valid.map((s) => s.hr.bpm.toDouble()).reduce((a, b) => a + b) / valid.length;
  }

  /// Time spent in each stress category (percentage)
  Map<String, double> get stressDistribution {
    // Use the same filter as avgStressIndex (index >= 0) so both stats are
    // computed from the same set of valid, calibrated readings.
    final valid = snapshots.where((s) => s.stress.index >= 0).toList();
    if (valid.isEmpty) return {'Low': 0, 'Moderate': 0, 'High': 0};
    final total = valid.length.toDouble();
    return {
      'Low':      valid.where((s) => s.stress.category == 0).length / total * 100,
      'Moderate': valid.where((s) => s.stress.category == 1).length / total * 100,
      'High':     valid.where((s) => s.stress.category == 2).length / total * 100,
    };
  }

  /// Serialize for Hive storage (JSON string)
  String toJsonString() {
    return jsonEncode({
      'id': id,
      'userId': userId,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime?.millisecondsSinceEpoch,
      'notes': notes,
      'tags': tags,
      'cachedAvgStress': _cachedAvgStress,
      'snapshots': snapshots.map((s) => s.toMap()).toList(),
    });
  }

  /// Deserialize from Hive storage
  factory Session.fromJsonString(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final snapshotList = (m['snapshots'] as List?)?.map((s) {
      final snap = s as Map<String, dynamic>;
      return SensorSnapshot(
        hr: _hrFromMap(snap['hr'] as Map<String, dynamic>),
        hrv: _hrvFromMap(snap['hrv'] as Map<String, dynamic>),
        gsr: _gsrFromMap(snap['gsr'] as Map<String, dynamic>),
        temp: _tempFromMap(snap['temp'] as Map<String, dynamic>),
        motion: _motionFromMap(snap['motion'] as Map<String, dynamic>),
        stress: _stressFromMap(snap['stress'] as Map<String, dynamic>),
        timestamp: DateTime.fromMillisecondsSinceEpoch(snap['ts'] as int),
      );
    }).toList();

    final tagsList = (m['tags'] as List?)?.cast<String>() ?? [];

    return Session(
      id: m['id'] as String,
      userId: m['userId'] as String? ?? '',
      startTime: DateTime.fromMillisecondsSinceEpoch(m['startTime'] as int),
      endTime: m['endTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['endTime'] as int)
          : null,
      snapshots: snapshotList ?? [],
      notes: m['notes'] as String?,
      tags: tagsList,
      cachedAvgStress: (m['cachedAvgStress'] as num?)?.toDouble(),
    );
  }

  /// CSV export content
  String toCsv() {
    final buf = StringBuffer();
    buf.writeln(SensorSnapshot.csvHeader());
    for (final snap in snapshots) {
      buf.writeln(snap.csvRow());
    }
    return buf.toString();
  }

  /// JSON export content
  String toExportJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'session_id': id,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'duration_seconds': duration.inSeconds,
      'snapshot_count': snapshotCount,
      'notes': notes,
      'summary': {
        'avg_stress_index': avgStressIndex,
        'avg_heart_rate': avgHeartRate,
        'stress_distribution': stressDistribution,
      },
      'data': snapshots.map((s) => s.toMap()).toList(),
    });
  }
}

// Helper factories for deserialization
HRData _hrFromMap(Map<String, dynamic> m) => HRData(
  bpm: m['bpm'] as int? ?? 0,
  valid: m['valid'] as bool? ?? false,
  sqi: (m['sqi'] as num?)?.toDouble() ?? 0,
  timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int? ?? 0),
);

HRVData _hrvFromMap(Map<String, dynamic> m) => HRVData(
  rmssd: (m['rmssd'] as num?)?.toDouble() ?? -1,
  sdnn: (m['sdnn'] as num?)?.toDouble() ?? -1,
  pnn50: (m['pnn50'] as num?)?.toDouble() ?? -1,
  timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int? ?? 0),
);

GSRData _gsrFromMap(Map<String, dynamic> m) => GSRData(
  microSiemens: (m['us'] as num?)?.toDouble() ?? 0,
  raw: m['raw'] as int? ?? 0,
  timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int? ?? 0),
);

TempData _tempFromMap(Map<String, dynamic> m) => TempData(
  skin: (m['skin'] as num?)?.toDouble() ?? 0,
  ambient: (m['ambient'] as num?)?.toDouble() ?? 0,
  timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int? ?? 0),
);

MotionData _motionFromMap(Map<String, dynamic> m) => MotionData(
  ax: (m['ax'] as num?)?.toDouble() ?? 0,
  ay: (m['ay'] as num?)?.toDouble() ?? 0,
  az: (m['az'] as num?)?.toDouble() ?? 0,
  mag: (m['mag'] as num?)?.toDouble() ?? 0,
  timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int? ?? 0),
);

StressData _stressFromMap(Map<String, dynamic> m) => StressData(
  index: (m['index'] as num?)?.toDouble() ?? -1,
  category: m['cat'] as int? ?? -1,
  label: m['label'] as String? ?? 'Unknown',
  probability: (m['prob'] as num?)?.toDouble() ?? 0,
  chronic: m['chronic'] as bool? ?? false,
  motionArtifact: m['motion'] as bool? ?? false,
  calibrated: m['cal'] as bool? ?? false,
  battery: m['bat'] as int? ?? 0,
  timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int? ?? 0),
);
