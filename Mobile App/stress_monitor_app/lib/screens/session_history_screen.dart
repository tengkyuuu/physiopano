import 'dart:ui';
import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/physiopano_tokens.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/ble_service.dart';
import '../services/theme_provider.dart';
import '../models/session.dart';
import '../services/export_service.dart';
import 'session_detail_screen.dart';

class SessionHistoryScreen extends StatelessWidget {
  const SessionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {

    return Consumer<BleService>(
      builder: (context, ble, _) {
        final sessions = ble.sessions;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
            elevation: 0,
            title: Text(
              'Session History',
              style: TextStyle(
                color: Theme.of(context).textTheme.titleLarge?.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            iconTheme: Theme.of(context).appBarTheme.iconTheme,
          ),
          body: sessions.isEmpty
              ? const Center(
                  child: Reveal(
                    child: SceneCard(
                      mood: PanoMood.sleepy,
                      blobColor: PpAccent.sky,
                      title: 'Your story starts here',
                      message: 'Tap Record session on Today to capture your first moment.',
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    return _SessionTile(
                      session: session,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SessionDetailScreen(session: session),
                        ),
                      ),
                      onDelete: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Session?'),
                            content: Text(
                              'This will permanently delete ${session.snapshotCount} data points.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  ble.deleteSession(session.id);
                                  Navigator.pop(ctx);
                                },
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy  h:mm a');
    final avgStress = session.avgStressIndex;
    final dist = session.stressDistribution;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? AppColors.emerald.withValues(alpha: 0.1)
                  : Colors.grey.shade200,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        dateFmt.format(session.startTime),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.download_rounded,
                            size: 20, color: isDark ? AppColors.emerald : AppColors.primaryGreen),
                        onPressed: () => ExportService.exportSessionToCsv(session),
                        tooltip: 'Export CSV',
                        padding: const EdgeInsets.only(right: 8),
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: AppColors.textSecondary),
                        onPressed: onDelete,
                        tooltip: 'Delete',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _InfoChip(icon: Icons.timer, label: session.durationString),
                      const SizedBox(width: 12),
                      _InfoChip(
                          icon: Icons.data_usage,
                          label: '${session.snapshotCount} samples'),
                      const SizedBox(width: 12),
                      _InfoChip(
                        icon: Icons.favorite,
                        label: session.avgHeartRate > 0
                            ? '${session.avgHeartRate.toStringAsFixed(0)} bpm'
                            : '-- bpm',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Stress distribution bar
                  if (avgStress >= 0) ...[
                    Row(
                      children: [
                        Text(
                          'Avg Stress: ${avgStress.toStringAsFixed(0)}/100',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.textSecondary
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 6,
                        child: Row(
                          children: [
                            if ((dist['Low'] ?? 0) > 0)
                              Expanded(
                                flex: (dist['Low']!).round().clamp(1, 100),
                                child: Container(color: PpAccent.mint),
                              ),
                            if ((dist['Moderate'] ?? 0) > 0)
                              Expanded(
                                flex: (dist['Moderate']!).round().clamp(1, 100),
                                child: Container(color: PpAccent.sun),
                              ),
                            if ((dist['High'] ?? 0) > 0)
                              Expanded(
                                flex: (dist['High']!).round().clamp(1, 100),
                                child: Container(color: Colors.red),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14,
            color: isDark ? AppColors.textMuted : AppColors.textMuted),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12,
              color: isDark ? AppColors.textSecondary : AppColors.textSecondary),
        ),
      ],
    );
  }
}
