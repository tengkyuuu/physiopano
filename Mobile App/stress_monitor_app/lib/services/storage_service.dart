/// Persistent storage service using Hive for session data.
///
/// Sessions are stored as JSON strings in a Hive box.
/// This keeps the data layer simple without needing Hive adapters.
library;

import 'package:hive_flutter/hive_flutter.dart';
import '../models/session.dart';

class StorageService {
  static const String _boxName = 'sessions';
  late Box<String> _box;

  /// Initialize Hive and open the sessions box.
  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
  }

  /// Load all saved sessions, most recent first.
  List<Session> loadSessions() {
    final sessions = <Session>[];
    for (final key in _box.keys) {
      try {
        final json = _box.get(key);
        if (json != null) {
          sessions.add(Session.fromJsonString(json));
        }
      } catch (e) {
        // Skip corrupted entries
      }
    }
    // Sort newest first
    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
    return sessions;
  }

  /// Save a session to persistent storage.
  Future<void> saveSession(Session session) async {
    await _box.put(session.id, session.toJsonString());
  }

  /// Delete a session from persistent storage.
  Future<void> deleteSession(String id) async {
    await _box.delete(id);
  }

  /// Clear all sessions.
  Future<void> clearAll() async {
    await _box.clear();
  }
}
