/// Local notification service.
///
/// Uses flutter_local_notifications for push-style alerts.
/// Logs all notifications to SQLite for the notification screen.
library;

import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Stream to broadcast tapped notification payloads
  final StreamController<String?> _selectNotificationStream =
      StreamController<String?>.broadcast();
  Stream<String?> get selectNotificationStream =>
      _selectNotificationStream.stream;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _selectNotificationStream.add(response.payload);
      },
    );
    _initialized = true;
  }

  // ---- A sustained change from the person's own usual ----
  // Calm by design: default importance, no alarm wording, no emoji. It offers
  // a moment for the person; it never contacts anyone else.
  Future<void> showChangeNoticed({required String title, required String body}) async {
    await _show(
      id: 1,
      title: title,
      body: body,
      channel: 'change_noticed',
      channelName: 'Changes from your usual',
      payload: 'change_noticed',
    );
  }

  // ---- Battery low ----
  Future<void> showBatteryLow(int percent) async {
    await _show(
      id: 4,
      title: 'Wristband battery low',
      body: 'PHYSIOPAÑO battery is at $percent%. Please charge soon.',
      channel: 'battery',
      channelName: 'Battery Alerts',
    );
  }

  // ---- Reconnection ----
  Future<void> showReconnected() async {
    await _show(
      id: 5,
      title: 'Wristband reconnected',
      body: 'PHYSIOPAÑO has been reconnected successfully.',
      channel: 'connection',
      channelName: 'Connection Events',
      importance: Importance.low,
      priority: Priority.low,
    );
  }

  // ---- Generic show ----
  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channel,
    required String channelName,
    Importance importance = Importance.defaultImportance,
    Priority priority = Priority.defaultPriority,
    String? payload,
  }) async {
    if (!_initialized) await init();

    final androidDetails = AndroidNotificationDetails(
      channel,
      channelName,
      importance: importance,
      priority: priority,
      showWhen: true,
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  void dispose() {
    _selectNotificationStream.close();
  }
}
