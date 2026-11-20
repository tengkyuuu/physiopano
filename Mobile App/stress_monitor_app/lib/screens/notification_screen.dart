import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/physiopano_tokens.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/theme_provider.dart';
import 'app_shell.dart';

/// Notification log screen — timestamped, icon-tagged, color-coded events.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    currentAppTab.addListener(_onTabChanged);
  }

  /// Index of this screen in AppShell's tabs.
  static const _tabIndex = 2;

  void _onTabChanged() {
    if (currentAppTab.value == _tabIndex) _load(markRead: true);
  }

  @override
  void dispose() {
    currentAppTab.removeListener(_onTabChanged);
    super.dispose();
  }

  /// Loads alerts. Items are only marked read when this tab is actually
  /// open — the shell builds every tab at launch.
  Future<void> _load({bool markRead = false}) async {
    final db = context.read<DatabaseService>();
    final auth = context.read<AuthService>();
    try {
      final notes = await db.getNotifications(auth.userId);
      if (!mounted) return;
      setState(() {
        _notifications = notes;
        _loading = false;
      });
      if (markRead) await db.markAllRead(auth.userId);
    } catch (e) {
      debugPrint('[Alerts] load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Notifications',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep,
                  color: isDark ? AppColors.textMuted : AppColors.textMuted),
              onPressed: () async {
                final db = context.read<DatabaseService>();
                final auth = context.read<AuthService>();
                await db.clearNotifications(auth.userId);
                if (mounted) setState(() => _notifications = []);
              },
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(
                  child: Reveal(
                    child: SceneCard(
                      mood: PanoMood.calm,
                      blobColor: PpAccent.mint,
                      title: 'All quiet',
                      message: 'Paño will let you know when something shifts from your usual.',
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notifications.length,
                  itemBuilder: (context, i) {
                    final n = _notifications[i];
                    return _NotificationTile(
                      type: (n['type'] as String?) ?? 'info',
                      title: (n['title'] as String?) ?? '',
                      body: (n['body'] as String?) ?? '',
                      timestamp: DateTime.fromMillisecondsSinceEpoch(
                          (n['timestamp'] as int?) ?? 0),
                      isRead: ((n['read'] as int?) ?? 0) == 1,
                    );
                  },
                ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final String type;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;

  const _NotificationTile({
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.isRead,
  });

  IconData get _icon {
    switch (type) {
      case 'change_noticed':
        return Icons.timeline_rounded;
      // Legacy entries from the retired stress classifier.
      case 'high_stress':
      case 'chronic_stress':
      case 'weekly_chronic':
        return Icons.history_rounded;
      case 'battery':
        return Icons.battery_alert_rounded;
      case 'connection':
        return Icons.bluetooth_connected_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  // Wayfinding: no alarm colours. Changes use the brand lane colour;
  // red is reserved for crisis UI and never used here.
  Color get _color {
    switch (type) {
      case 'change_noticed':
        return AppColors.emerald;
      case 'battery':
        return AppColors.route3;
      case 'connection':
        return AppColors.route2;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, h:mm a');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? AppColors.emerald.withValues(alpha: 0.1)
              : Colors.grey.shade200,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _color.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_icon, color: _color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    isRead ? FontWeight.w500 : FontWeight.bold,
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                          Text(
                            dateFmt.format(timestamp),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.textMuted
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textSecondary
                              : AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
