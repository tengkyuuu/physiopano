import 'package:flutter/material.dart';
import '../theme/physiopano_tokens.dart';
import '../services/theme_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';
import '../widgets/trend_chart.dart';
import '../utils/export_util.dart';
import '../utils/pdf_generator.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/ai_insight_service.dart';
import 'package:provider/provider.dart';

class SessionDetailScreen extends StatefulWidget {
  final Session session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late Session _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _loadSnapshots();
  }

  Future<void> _loadSnapshots() async {
    // If snapshots are already loaded (e.g. just-recorded session), skip DB fetch
    if (_session.snapshots.isNotEmpty) {
      setState(() => _loading = false);
      return;
    }
    // Lazy-load full snapshots from SQLite
    final db = context.read<DatabaseService>();
    final full = await db.loadSessionWithSnapshots(_session.id);
    if (full != null && mounted) {
      setState(() {
        _session = full;
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy  h:mm a');
    final dist = _session.stressDistribution;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor ?? (isDark ? AppColors.deepBlack : Colors.white),
        elevation: 0,
        title: Text(
          'Session Detail',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF10201F),
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xFF10201F)),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.ios_share, color: isDark ? Colors.white : const Color(0xFF10201F)),
            onSelected: (val) async {
              if (val == 'csv') {
                ExportUtil.exportSession(_session, ExportFormat.csv);
              } else if (val == 'json') {
                ExportUtil.exportSession(_session, ExportFormat.json);
              } else if (val == 'pdf') {
                final auth = context.read<AuthService>();
                final db = context.read<DatabaseService>();
                final settings = await db.getSettings(auth.userId);
                final patientName =
                    settings?['display_name'] as String? ?? 'Unknown';
                final patientId =
                    settings?['student_id'] as String? ?? auth.userId;

                await PdfReportGenerator.generateAndPrintSessionReport(
                  session: _session,
                  patientName: patientName,
                  patientId: patientId,
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, size: 18, color: PpAccent.sky),
                    SizedBox(width: 8),
                    Text('Clinical PDF Report'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, size: 18),
                    SizedBox(width: 8),
                    Text('Export CSV (Raw)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'json',
                child: Row(
                  children: [
                    Icon(Icons.code, size: 18),
                    SizedBox(width: 8),
                    Text('Export JSON (Raw)'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _session.snapshots.isEmpty
          ? Center(child: Text('No data in this session',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Summary card ----
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateFmt.format(_session.startTime),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SummaryRow(
                            label: 'Duration',
                            value: _session.durationString,
                          ),
                          _SummaryRow(
                            label: 'Samples',
                            value: '${_session.snapshotCount}',
                          ),
                          _SummaryRow(
                            label: 'Avg Heart Rate',
                            value: _session.avgHeartRate > 0
                                ? '${_session.avgHeartRate.toStringAsFixed(0)} bpm'
                                : 'N/A',
                          ),
                          _SummaryRow(
                            label: 'Avg distance from usual',
                            value: _session.avgStressIndex >= 0
                                ? '${_session.avgStressIndex.toStringAsFixed(1)} / 100'
                                : 'N/A',
                          ),
                          const SizedBox(height: 12),

                          // Stress distribution
                          const Text(
                            'Time near your usual',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              height: 12,
                              child: Row(
                                children: [
                                  if ((dist['Low'] ?? 0) > 0)
                                    Expanded(
                                      flex:
                                          (dist['Low']!).round().clamp(1, 100),
                                      child: Container(color: PpAccent.mint),
                                    ),
                                  if ((dist['Moderate'] ?? 0) > 0)
                                    Expanded(
                                      flex: (dist['Moderate']!)
                                          .round()
                                          .clamp(1, 100),
                                      child: Container(color: PpAccent.sun),
                                    ),
                                  if ((dist['High'] ?? 0) > 0)
                                    Expanded(
                                      flex:
                                          (dist['High']!).round().clamp(1, 100),
                                      child: Container(color: Colors.red),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _Legend(
                                  color: PpAccent.mint,
                                  label:
                                      'Within ${dist['Low']?.toStringAsFixed(0) ?? 0}%'),
                              _Legend(
                                  color: PpAccent.sun,
                                  label:
                                      'A little different ${dist['Moderate']?.toStringAsFixed(0) ?? 0}%'),
                              _Legend(
                                  color: Colors.red,
                                  label:
                                      'Different ${dist['High']?.toStringAsFixed(0) ?? 0}%'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---- AI Insight ----
                  _AiInsightCard(session: _session),

                  const SizedBox(height: 16),

                  // ---- Charts ----
                  Text(
                    'Session Trends',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? Colors.white : const Color(0xFF10201F),
                    ),
                  ),
                  const SizedBox(height: 8),

                  TrendChart(
                    title: 'Distance from your usual',
                    lineColor: AppColors.emerald,
                    spots: _spots(
                        (s) => s.stress.index >= 0 ? s.stress.index : null),
                    minY: 0,
                    maxY: 100,
                  ),
                  const SizedBox(height: 8),

                  TrendChart(
                    title: 'Heart Rate',
                    lineColor: Colors.red,
                    spots:
                        _spots((s) => s.hr.valid ? s.hr.bpm.toDouble() : null),
                    minY: 40,
                    maxY: 150,
                    yLabel: 'bpm',
                  ),
                  const SizedBox(height: 8),

                  TrendChart(
                    title: 'HRV (RMSSD)',
                    lineColor: PpAccent.lilac,
                    spots: _spots((s) => s.hrv.valid ? s.hrv.rmssd : null),
                    yLabel: 'ms',
                  ),
                  const SizedBox(height: 8),

                  TrendChart(
                    title: 'Skin Conductance (EDA)',
                    lineColor: PpAccent.mint,
                    spots: _spots((s) =>
                        s.gsr.microSiemens > 0 ? s.gsr.microSiemens : null),
                    yLabel: 'µS',
                  ),
                  const SizedBox(height: 8),

                  TrendChart(
                    title: 'Skin Temperature',
                    lineColor: PpAccent.sun,
                    spots: _spots((s) => s.temp.skin > 20 ? s.temp.skin : null),
                    yLabel: '°C',
                  ),
                  const SizedBox(height: 8),

                  TrendChart(
                    title: 'Motion (Accel Magnitude)',
                    lineColor: PpAccent.sky,
                    spots: _spots((s) => s.motion.mag),
                    yLabel: 'g',
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  /// Build chart spots from session snapshots.
  /// X = seconds since session start.
  List<FlSpot> _spots(double? Function(dynamic s) getValue) {
    if (_session.snapshots.isEmpty) return [];
    final origin = _session.startTime;
    final spots = <FlSpot>[];
    for (final snap in _session.snapshots) {
      final val = getValue(snap);
      final x = snap.timestamp.difference(origin).inMilliseconds / 1000.0;
      if (val == null) {
        spots.add(FlSpot.nullSpot);
      } else {
        spots.add(FlSpot(x, val));
      }
    }
    return spots;
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: isDark ? AppColors.textSecondary : AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _AiInsightCard extends StatefulWidget {
  final Session session;
  const _AiInsightCard({required this.session});

  @override
  State<_AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends State<_AiInsightCard> {
  late final Future<String?> _insightFuture;

  @override
  void initState() {
    super.initState();
    _insightFuture = context.read<AiInsightService>().loadInsight(widget.session.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.cardDark : const Color(0xFFE3E7E2);
    final borderColor = isDark ? AppColors.border : const Color(0xFFC9D0CC);
    final accentColor = isDark ? AppColors.emerald : const Color(0xFF0F7A68);
    final labelColor = isDark ? AppColors.emerald : const Color(0xFF0F7A68);

    return FutureBuilder<String?>(
      future: _insightFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                ),
                const SizedBox(width: 12),
                Text('Generating AI insight…',
                    style: TextStyle(fontSize: 13, color: labelColor)),
              ],
            ),
          );
        }
        if (!snap.hasData || snap.data == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_rounded, color: accentColor, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Insight',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: labelColor,
                          letterSpacing: 0.5,
                        )),
                    const SizedBox(height: 4),
                    Text(snap.data!,
                        style: TextStyle(fontSize: 13, height: 1.5,
                          color: isDark ? Colors.white : Colors.black87)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 11,
              color: isDark ? AppColors.textSecondary : AppColors.textSecondary)),
      ],
    );
  }
}
