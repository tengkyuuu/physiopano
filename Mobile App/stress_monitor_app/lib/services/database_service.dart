/// SQLite database service for persistent local storage.
///
/// Tables: sessions, snapshots, notifications, baseline, user_settings
/// Replaces Hive for structured query support and relational data.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart' as p;
import '../models/sensor_data.dart';
import '../models/session.dart';

class DatabaseService {
  static Database? _db;
  static Completer<Database>? _initCompleter;
  static const int _version = 6;

  Future<Database> get database async {
    if (_db != null) return _db!;
    // Use Completer to prevent concurrent _initDb() calls (race condition)
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<Database>();
    try {
      _db = await _initDb();
      _initCompleter!.complete(_db!);
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
    return _db!;
  }

  Future<Database> _initDb() async {
    if (kIsWeb) {
      return await databaseFactoryFfiWeb.openDatabase(
        'stress_monitor.db',
        options: OpenDatabaseOptions(
          version: _version,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'stress_monitor.db');

    return await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Sessions table
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL DEFAULT '',
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        notes TEXT,
        tags TEXT,
        avg_stress_index REAL DEFAULT -1,
        snapshot_count INTEGER DEFAULT 0,
        avg_hr REAL DEFAULT -1,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Snapshots table (linked to sessions)
    await db.execute('''
      CREATE TABLE snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        data TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    // Notifications log
    await db.execute('''
      CREATE TABLE notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        read INTEGER DEFAULT 0
      )
    ''');

    // Baseline calibration data
    await db.execute('''
      CREATE TABLE baseline (
        user_id TEXT PRIMARY KEY,
        hr_mean REAL,
        hr_std REAL,
        hrv_mean REAL,
        hrv_std REAL,
        gsr_mean REAL,
        gsr_std REAL,
        temp_mean REAL,
        temp_std REAL,
        accmag_mean REAL DEFAULT 1.0,
        accmag_std REAL DEFAULT 0.1,
        sample_count INTEGER,
        calibrated_at INTEGER,
        is_complete INTEGER DEFAULT 0
      )
    ''');

    // Mood journal
    await db.execute('''
      CREATE TABLE mood_journal (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        date TEXT NOT NULL,
        mood INTEGER NOT NULL,
        emoji TEXT NOT NULL,
        label TEXT NOT NULL,
        note TEXT,
        timestamp INTEGER NOT NULL
      )
    ''');

    // User settings
    await db.execute('''
      CREATE TABLE user_settings (
        user_id TEXT PRIMARY KEY,
        display_name TEXT,
        student_id TEXT,
        emergency_name TEXT,
        emergency_email TEXT,
        emergency_phone TEXT,
        notify_high_stress INTEGER DEFAULT 1,
        notify_chronic INTEGER DEFAULT 1,
        notify_battery INTEGER DEFAULT 1,
        notify_reconnect INTEGER DEFAULT 1,
        onboarding_complete INTEGER DEFAULT 0,
        incognito_mode INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE baseline ADD COLUMN accmag_mean REAL DEFAULT 1.0');
      await db.execute(
          'ALTER TABLE baseline ADD COLUMN accmag_std REAL DEFAULT 0.1');
    }

    if (oldVersion < 3) {
      try {
        await db.execute(
            'ALTER TABLE user_settings ADD COLUMN incognito_mode INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE sessions ADD COLUMN tags TEXT');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE sessions ADD COLUMN avg_stress_index REAL DEFAULT -1');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE mood_journal (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            date TEXT NOT NULL,
            mood INTEGER NOT NULL,
            emoji TEXT NOT NULL,
            label TEXT NOT NULL,
            note TEXT,
            timestamp INTEGER NOT NULL
          )
        ''');
      } catch (_) {}
    }

    if (oldVersion < 4) {
      try {
        await db.execute(
            "ALTER TABLE sessions ADD COLUMN user_id TEXT NOT NULL DEFAULT ''");
      } catch (_) {}
    }

    if (oldVersion < 5) {
      try {
        await db.execute(
            'ALTER TABLE sessions ADD COLUMN snapshot_count INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE sessions ADD COLUMN avg_hr REAL DEFAULT -1');
      } catch (_) {}
      // Back-fill snapshot_count from existing snapshots table
      try {
        await db.execute('''
          UPDATE sessions SET snapshot_count = (
            SELECT COUNT(*) FROM snapshots WHERE snapshots.session_id = sessions.id
          )
        ''');
      } catch (_) {}
    }

    if (oldVersion < 6) {
      try {
        await db.execute(
            "ALTER TABLE notifications ADD COLUMN user_id TEXT NOT NULL DEFAULT ''");
      } catch (_) {}
    }
  }

  // =====================================================================
  //  SESSIONS
  // =====================================================================

  /// Save a session with all its snapshots.
  /// Deletes existing snapshots first to prevent duplicates from periodic saves.
  Future<void> saveSession(Session session) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'sessions',
        {
          'id': session.id,
          'user_id': session.userId,
          'start_time': session.startTime.millisecondsSinceEpoch,
          'end_time': session.endTime?.millisecondsSinceEpoch,
          'notes': session.notes,
          'tags': session.tags.isNotEmpty ? session.tags.join(',') : null,
          'avg_stress_index': session.avgStressIndex,
          'snapshot_count': session.snapshots.length,
          'avg_hr': session.avgHeartRate,
          'synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Delete existing snapshots first — prevents duplicates when a session
      // was partially written by the periodic progress saver during recording.
      await txn.delete('snapshots',
          where: 'session_id = ?', whereArgs: [session.id]);

      // Batch insert all snapshots
      for (final snap in session.snapshots) {
        await txn.insert('snapshots', {
          'session_id': session.id,
          'timestamp': snap.timestamp.millisecondsSinceEpoch,
          'data': jsonEncode(snap.toMap()),
        });
      }
    });
  }

  /// Upsert only the session row — no snapshot changes.
  /// Called by the periodic progress saver so data survives a crash/kill.
  Future<void> upsertSessionRow(Session session) async {
    final db = await database;
    await db.insert(
      'sessions',
      {
        'id': session.id,
        'user_id': session.userId,
        'start_time': session.startTime.millisecondsSinceEpoch,
        'end_time': session.endTime?.millisecondsSinceEpoch,
        'notes': session.notes,
        'tags': session.tags.isNotEmpty ? session.tags.join(',') : null,
        'avg_stress_index': session.avgStressIndex,
        'snapshot_count': session.snapshots.length,
        'avg_hr': session.avgHeartRate,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Append new snapshots to an existing session (incremental — no delete).
  /// Paired with [upsertSessionRow] for live progress saves during recording.
  Future<void> appendSnapshots(
      String sessionId, List<SensorSnapshot> snapshots) async {
    if (snapshots.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final snap in snapshots) {
        await txn.insert('snapshots', {
          'session_id': sessionId,
          'timestamp': snap.timestamp.millisecondsSinceEpoch,
          'data': jsonEncode(snap.toMap()),
        });
      }
    });
  }

  /// Load sessions for a specific user (without snapshots for performance).
  /// Also claims any orphaned sessions (user_id = '') from before the
  /// per-user isolation migration, so they aren't lost.
  Future<List<Session>> loadSessions(String userId) async {
    final db = await database;

    // Claim orphaned sessions ONLY if no other user has sessions yet.
    // This prevents a second user login from stealing a first user's sessions.
    // Safe to run every login — the WHERE clause only matches truly unclaimed rows
    // and the COUNT check ensures we only claim if this is the sole user account.
    final otherUserCount = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(DISTINCT user_id) FROM sessions WHERE user_id != '' AND user_id IS NOT NULL AND user_id != ?",
      [userId],
    )) ?? 0;

    if (otherUserCount == 0) {
      // Only one user (or no users yet) — safe to claim orphaned sessions
      await db.update(
        'sessions',
        {'user_id': userId},
        where: "user_id = '' OR user_id IS NULL",
      );
    }

    final rows = await db.query(
      'sessions',
      where: "user_id = ?",
      whereArgs: [userId],
      orderBy: 'start_time DESC',
    );

    return rows.map((row) {
      final tagsStr = row['tags'] as String?;
      return Session(
        id: row['id'] as String,
        userId: row['user_id'] as String? ?? '',
        startTime:
            DateTime.fromMillisecondsSinceEpoch(row['start_time'] as int),
        endTime: row['end_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['end_time'] as int)
            : null,
        notes: row['notes'] as String?,
        tags: tagsStr != null && tagsStr.isNotEmpty
            ? tagsStr.split(',')
            : [],
        cachedAvgStress: (row['avg_stress_index'] as num?)?.toDouble() ?? -1,
        cachedSnapshotCount: (row['snapshot_count'] as int?) ?? 0,
        cachedAvgHr: (row['avg_hr'] as num?)?.toDouble() ?? -1,
      );
    }).toList();
  }

  /// Load full session with snapshots.
  Future<Session?> loadSessionWithSnapshots(String sessionId) async {
    final db = await database;
    final sessionRows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    if (sessionRows.isEmpty) return null;

    final row = sessionRows.first;
    final snapRows = await db.query(
      'snapshots',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );

    final snapshots = <SensorSnapshot>[];
    for (final s in snapRows) {
      try {
        final data = jsonDecode(s['data'] as String) as Map<String, dynamic>;
        snapshots.add(_snapshotFromMap(data, s['timestamp'] as int));
      } catch (e) {
        debugPrint('[DB] Corrupted snapshot id=${s['id']}, skipping: $e');
      }
    }

    final tagsStr2 = row['tags'] as String?;
    return Session(
      id: row['id'] as String,
      userId: row['user_id'] as String? ?? '',
      startTime: DateTime.fromMillisecondsSinceEpoch(row['start_time'] as int),
      endTime: row['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['end_time'] as int)
          : null,
      notes: row['notes'] as String?,
      tags: tagsStr2 != null && tagsStr2.isNotEmpty ? tagsStr2.split(',') : [],
      snapshots: snapshots,
    );
  }

  Future<void> updateSessionTags(String sessionId, List<String> tags) async {
    final db = await database;
    await db.update(
      'sessions',
      {'tags': tags.isNotEmpty ? tags.join(',') : null},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> deleteSession(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('snapshots', where: 'session_id = ?', whereArgs: [id]);
      await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Get unsynced sessions for cloud upload.
  Future<List<String>> getUnsyncedSessionIds() async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      columns: ['id'],
      where: 'synced = 0',
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  /// Mark a session as synced.
  Future<void> markSynced(String sessionId) async {
    final db = await database;
    await db.update(
      'sessions',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  // =====================================================================
  //  MOOD JOURNAL
  // =====================================================================

  Future<void> saveMoodEntry({
    required String userId,
    required String date,
    required int mood,
    required String emoji,
    required String label,
    String? note,
  }) async {
    final db = await database;
    await db.insert(
      'mood_journal',
      {
        'user_id': userId,
        'date': date,
        'mood': mood,
        'emoji': emoji,
        'label': label,
        'note': note,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getMoodEntries(String userId) async {
    final db = await database;
    return db.query(
      'mood_journal',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
    );
  }

  Future<Map<String, dynamic>?> getMoodEntryForDate(
      String userId, String date) async {
    final db = await database;
    final rows = await db.query(
      'mood_journal',
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, date],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Returns a map of date string (yyyy-MM-dd) → avg stress index for the calendar.
  Future<Map<String, double>> getDailyStressStats(String userId) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      columns: ['start_time', 'avg_stress_index'],
      where: 'user_id = ? AND avg_stress_index >= 0',
      whereArgs: [userId],
    );

    final grouped = <String, List<double>>{};
    for (final row in rows) {
      final dt =
          DateTime.fromMillisecondsSinceEpoch(row['start_time'] as int);
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final stress = (row['avg_stress_index'] as num).toDouble();
      grouped.putIfAbsent(key, () => []).add(stress);
    }

    return grouped.map((date, values) => MapEntry(
          date,
          values.reduce((a, b) => a + b) / values.length,
        ));
  }

  // =====================================================================
  //  NOTIFICATIONS
  // =====================================================================

  Future<void> insertNotification({
    required String type,
    required String title,
    required String body,
    required String userId,
  }) async {
    final db = await database;
    await db.insert('notifications', {
      'user_id': userId,
      'type': type,
      'title': title,
      'body': body,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'read': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getNotifications(String userId, {int limit = 100}) async {
    final db = await database;
    return db.query(
      'notifications',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<int> getUnreadCount(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM notifications WHERE read = 0 AND user_id = ?',
      [userId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> markAllRead(String userId) async {
    final db = await database;
    await db.update(
      'notifications',
      {'read': 1},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> clearNotifications(String userId) async {
    final db = await database;
    await db.delete('notifications', where: 'user_id = ?', whereArgs: [userId]);
  }

  // =====================================================================
  //  BASELINE
  // =====================================================================

  Future<void> saveBaseline({
    required String userId,
    required double hrMean,
    required double hrStd,
    required double hrvMean,
    required double hrvStd,
    required double gsrMean,
    required double gsrStd,
    required double tempMean,
    required double tempStd,
    required int sampleCount,
    double accMagMean = 1.0,
    double accMagStd = 0.1,
  }) async {
    final db = await database;
    await db.insert(
      'baseline',
      {
        'user_id': userId,
        'hr_mean': hrMean,
        'hr_std': hrStd,
        'hrv_mean': hrvMean,
        'hrv_std': hrvStd,
        'gsr_mean': gsrMean,
        'gsr_std': gsrStd,
        'temp_mean': tempMean,
        'temp_std': tempStd,
        'accmag_mean': accMagMean,
        'accmag_std': accMagStd,
        'sample_count': sampleCount,
        'calibrated_at': DateTime.now().millisecondsSinceEpoch,
        'is_complete': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getBaseline(String userId) async {
    final db = await database;
    final rows = await db.query(
      'baseline',
      where: 'user_id = ? AND is_complete = 1',
      whereArgs: [userId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> clearBaseline(String userId) async {
    final db = await database;
    await db.delete('baseline', where: 'user_id = ?', whereArgs: [userId]);
  }

  // =====================================================================
  //  PRIVACY & DATA WIPING ("Right to be Forgotten")
  // =====================================================================

  Future<void> wipeAllUserData(String userId) async {
    final db = await database;
    await db.transaction((txn) async {
      // Delete snapshots linked to this user's sessions
      await txn.execute(
          "DELETE FROM snapshots WHERE session_id IN (SELECT id FROM sessions WHERE user_id = ?)",
          [userId]);
      // Delete this user's sessions
      await txn.delete('sessions', where: 'user_id = ?', whereArgs: [userId]);
      // Delete baseline
      await txn.delete('baseline', where: 'user_id = ?', whereArgs: [userId]);
      // Delete settings
      await txn
          .delete('user_settings', where: 'user_id = ?', whereArgs: [userId]);
      // Clear only this user's notifications
      await txn.delete('notifications', where: 'user_id = ?', whereArgs: [userId]);
      // Clear mood journal
      await txn
          .delete('mood_journal', where: 'user_id = ?', whereArgs: [userId]);
    });
  }

  // =====================================================================
  //  USER SETTINGS
  // =====================================================================

  /// Merge [settings] into the user's row. Only the given columns change;
  /// everything else is kept. (A plain INSERT OR REPLACE would delete the row
  /// and silently reset every column that was not passed — that is how the
  /// emergency contact, name and onboarding flag used to get wiped.)
  Future<void> saveSettings(
      String userId, Map<String, dynamic> settings) async {
    if (userId.isEmpty) return;
    final db = await database;
    final values = Map<String, dynamic>.from(settings)..remove('user_id');
    await db.transaction((txn) async {
      final updated = values.isEmpty
          ? 0
          : await txn.update('user_settings', values, where: 'user_id = ?', whereArgs: [userId]);
      final exists = updated > 0 ||
          (await txn.query('user_settings', columns: ['user_id'], where: 'user_id = ?', whereArgs: [userId])).isNotEmpty;
      if (!exists) {
        await txn.insert('user_settings', {...values, 'user_id': userId});
      }
    });
  }

  Future<Map<String, dynamic>?> getSettings(String userId) async {
    final db = await database;
    final rows = await db.query(
      'user_settings',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  // =====================================================================
  //  HELPERS
  // =====================================================================

  SensorSnapshot _snapshotFromMap(Map<String, dynamic> data, int ts) {
    return SensorSnapshot(
      hr: _hrFromMap(data['hr'] as Map<String, dynamic>),
      hrv: _hrvFromMap(data['hrv'] as Map<String, dynamic>),
      gsr: _gsrFromMap(data['gsr'] as Map<String, dynamic>),
      temp: _tempFromMap(data['temp'] as Map<String, dynamic>),
      motion: _motionFromMap(data['motion'] as Map<String, dynamic>),
      stress: _stressFromMap(data['stress'] as Map<String, dynamic>),
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
    );
  }

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
}
