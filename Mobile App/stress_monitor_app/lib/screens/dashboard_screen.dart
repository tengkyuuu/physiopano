import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../models/sensor_data.dart';
import '../widgets/sensor_card.dart';
import '../widgets/baseline_lane.dart';
import '../widgets/trend_chart.dart';
import '../services/theme_provider.dart';
import '../services/database_service.dart';
import '../services/ai_insight_service.dart';
import '../services/baseline_service.dart';
import 'session_history_screen.dart';
import 'mood_journal_screen.dart';
import 'check_in_screen.dart';
import 'breathing_screen.dart';
import 'referral_follow_up.dart';
import '../models/check_in.dart';
import '../services/change_detector.dart';
import '../theme/physiopano_tokens.dart';
import '../motion/motion.dart';

// Re-export AppColors for convenience
export '../services/theme_provider.dart' show AppColors;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, ble, _) {
        final hr = ble.hr;
        final hrv = ble.hrv;
        final gsr = ble.gsr;
        final temp = ble.temp;
        final motion = ble.motion;
        final stress = ble.stress;

        final themeProvider = context.watch<ThemeProvider>();
        final isDark = themeProvider.isDarkMode;

        final authUser = context.watch<AuthService>().currentUser;
        final firstName = (authUser?.displayName ?? authUser?.email ?? '')
            .split(' ').first.split('@').first;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: _DashboardBackdrop(
            calm: stress.index < 0 ? 1.0 : (1 - stress.category / 2).clamp(0.0, 1.0).toDouble(),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _DashboardHeader(
                    ble: ble,
                    firstName: firstName,
                    isDark: isDark,
                    onToggleTheme: themeProvider.toggleTheme,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(PpSpace.gutter, 12, PpSpace.gutter, 150),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Reveal(child: _Greeting(firstName: firstName, ble: ble)),
                          const SizedBox(height: 24),
                          Reveal(
                            index: 1,
                            child: _StatusHero(ble: ble, stress: stress),
                          ),
                          const SizedBox(height: 20),
                          // ---- Recording banner ----
                          if (ble.isRecording && ble.activeSession != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.brandSoft,
                                borderRadius: BorderRadius.circular(PpRadius.pill),
                              ),
                              child: Row(
                                children: [
                                  const Pulse(child: Icon(Icons.fiber_manual_record, color: AppColors.emerald, size: 14)),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Recording  ·  ${ble.activeSession?.snapshotCount ?? 0} samples',
                                    style: PpTheme.font(size: 14, weight: FontWeight.w600, color: AppColors.emerald),
                                  ),
                                  const Spacer(),
                                  Text(
                                    ble.activeSession?.durationString ?? '',
                                    style: PpTheme.data(context, size: 14).copyWith(color: AppColors.emerald),
                                  ),
                                ],
                              ),
                            ),

                          const Reveal(index: 2, child: BaselineLane()),
                          const SizedBox(height: 16),
                          const ReferralFollowUps(),
                          // ---- Check-in entry (works without the wristband) ----
                          const Reveal(index: 3, child: _CheckInCard()),
                          const SizedBox(height: 16),

                          // ====================================================
                          // SENSOR STATE MACHINE
                          // Phase 0 — not connected → connect device panel
                          // Phase 1 — sensors not all ready → waiting panel
                          // Phase 2 — all ready, not calibrated, not calibrating
                          //           → "Start Calibrating Baseline" panel
                          // Phase 3 — calibrating → 3-min countdown panel
                          // ====================================================
                          if (ble.state != BleConnectionState.connected)
                            _ConnectDevicePanel(ble: ble)
                          else if (!ble.allSensorsReady)
                            _WaitingPanel(
                                pendingSensors: ble.pendingSensors)
                          else if (ble.isCalibrating)
                            _CalibratingPanel(
                              progress: ble.calibrationProgress,
                              timeRemaining: ble.calibrationTimeRemaining,
                            )
                          else if (!ble.isCalibrated)
                            _ReadyToCalibratePanel(
                              onStart: () => context
                                  .read<BleService>()
                                  .startBaselineCalibration(),
                            ),
                          const SizedBox(height: 4),

                          // Motion artifact warning
                          if (stress.motionArtifact)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: PpAccent.sun.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.directions_walk,
                                      color: PpAccent.sun, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'Motion detected — readings may be affected',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: PpAccent.sun,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 12),

                          // ---- Daily Stress Pie Chart ----
                          if (ble.stressHistory.isNotEmpty)
                            Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: AppColors.emerald
                                                .withValues(
                                                    alpha: isDark ? 0.2 : 0.1),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: const Icon(
                                              Icons.pie_chart_rounded,
                                              color: AppColors.emerald,
                                              size: 16),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Time near your usual',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 120,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: PieChart(
                                              PieChartData(
                                                sectionsSpace: 2,
                                                centerSpaceRadius: 24,
                                                sections: _buildPieSections(
                                                    ble.stressHistory),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          const Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              _PieLegend(
                                                  color: AppColors.levelLow,
                                                  label: 'Within your usual'),
                                              SizedBox(height: 6),
                                              _PieLegend(
                                                  color: AppColors.levelMid,
                                                  label: 'A little different'),
                                              SizedBox(height: 6),
                                              _PieLegend(
                                                  color: AppColors.levelHigh,
                                                  label: 'Different'),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // ---- Sensor cards grid ----
                          const _SectionHeading(
                            title: 'Right now',
                            caption: 'Live from your band',
                          ),
                          const SizedBox(height: 12),
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.18,
                            children: [
                              SensorCard(
                                icon: Icons.favorite,
                                label: 'Heart Rate',
                                value: hr.valid ? '${hr.bpm}' : '--',
                                unit: 'bpm',
                                subtitle: hr.valid
                                    ? 'SQI: ${hr.sqi.toStringAsFixed(2)}'
                                    : 'No pulse detected',
                                color: PpAccent.coral,
                              ),
                              SensorCard(
                                icon: Icons.timeline,
                                label: 'HRV (RMSSD)',
                                value: hrv.valid
                                    ? hrv.rmssd.toStringAsFixed(1)
                                    : '--',
                                unit: 'ms',
                                subtitle: hrv.valid
                                    ? 'SDNN:${hrv.sdnn.toStringAsFixed(1)} pNN50:${hrv.pnn50.toStringAsFixed(1)}%'
                                    : 'Waiting for IBI data',
                                color: PpAccent.sky,
                              ),
                              SensorCard(
                                icon: Icons.water_drop,
                                label: 'Skin Conductance',
                                value: gsr.microSiemens > 0
                                    ? gsr.microSiemens.toStringAsFixed(2)
                                    : '--',
                                unit: 'µS',
                                subtitle: 'ADC: ${gsr.raw}',
                                color: PpAccent.mint,
                              ),
                              SensorCard(
                                icon: Icons.thermostat,
                                label: 'Skin Temp',
                                value: temp.skin > 20
                                    ? temp.skin.toStringAsFixed(1)
                                    : '--',
                                unit: '°C',
                                subtitle: temp.ambient > 0
                                    ? 'Ambient: ${temp.ambient.toStringAsFixed(1)}°C'
                                    : null,
                                color: PpAccent.sun,
                              ),
                              SensorCard(
                                icon: Icons.vibration,
                                label: 'Accelerometer',
                                value: motion.mag.toStringAsFixed(2),
                                unit: 'g',
                                subtitle: 'X:${motion.ax.toStringAsFixed(2)} Y:${motion.ay.toStringAsFixed(2)} Z:${motion.az.toStringAsFixed(2)}',
                                color: PpAccent.lilac,
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // ---- Baseline vs Current delta panel ----
                          Consumer<BaselineService>(
                            builder: (ctx, baseline, _) {
                              if (!baseline.isCalibrated) return const SizedBox();
                              return _BaselineDeltaPanel(
                                baseline: baseline,
                                hr: hr,
                                hrv: hrv,
                                gsr: gsr,
                                temp: temp,
                              );
                            },
                          ),

                          const SizedBox(height: 20),

                          // ---- Trend charts (primary visualization) ----
                          const _SectionHeading(
                            title: 'How your body moved',
                            caption: 'Last 5 minutes',
                          ),
                          const SizedBox(height: 10),

                          TrendChart(
                            title: 'Heart Rate',
                            lineColor: PpAccent.coral,
                            spots: _buildSpots(
                              ble.hrHistory,
                              (s) => s.valid ? s.bpm.toDouble() : null,
                              (s) => s.timestamp,
                            ),
                            minY: 40,
                            maxY: 150,
                            yLabel: 'bpm',
                          ),
                          const SizedBox(height: 8),

                          TrendChart(
                            title: 'GSR (EDA)',
                            lineColor: PpAccent.mint,
                            spots: _buildSpots(
                              ble.gsrHistory,
                              (s) => (s.microSiemens > 0 && s.microSiemens < 50)
                                  ? s.microSiemens
                                  : null,
                              (s) => s.timestamp,
                            ),
                            minY: 0,
                            yLabel: 'µS',
                          ),
                          const SizedBox(height: 8),

                          TrendChart(
                            title: 'Skin Temperature',
                            lineColor: PpAccent.sun,
                            spots: _buildSpots(
                              ble.tempHistory,
                              (s) => s.skin > 20 ? s.skin : null,
                              (s) => s.timestamp,
                            ),
                            yLabel: '°C',
                          ),
                          const SizedBox(height: 8),

                          // ---- HRV Bar Chart (reference-style) ----
                          if (ble.hrvHistory.isNotEmpty)
                            Consumer<BaselineService>(
                              builder: (ctx, baseline, _) => _HRVBarChart(
                                hrvHistory: ble.hrvHistory,
                                baseline: baseline,
                              ),
                            ),

                          // ---- Recalibrate button (Phase 4 only) ----
                          if (ble.isCalibrated) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.refresh_rounded,
                                    size: 18),
                                label: const Text('Recalibrate Baseline'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.emerald,
                                  side: BorderSide(
                                      color: AppColors.emerald
                                          .withValues(alpha: 0.6)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(16)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                ),
                                onPressed: () async {
                                  await context
                                      .read<BleService>()
                                      .resetForRecalibration();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Baseline cleared — press "Start Calibrating Baseline" to recalibrate'),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ---- FAB: Record toggle ----
          floatingActionButton: Padding(
            // Clear the floating nav pill.
            padding: const EdgeInsets.only(bottom: 92),
            child: _RecordButton(
            recording: ble.isRecording,
            elapsed: ble.activeSession?.durationString,
            onPressed: () async {
              if (ble.isRecording) {
                final session = await ble.stopRecording();
                if (session != null && context.mounted) {
                  // Trigger AI insight in background — saves to Firestore when done
                  context.read<AiInsightService>().generateInsight(session);

                  // Show tag picker
                  final tags = await _showTagPicker(context);
                  if (tags != null && tags.isNotEmpty && context.mounted) {
                    session.tags = tags;
                    await context
                        .read<DatabaseService>()
                        .updateSessionTags(session.id, tags);
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Session saved: ${session.snapshotCount} samples, '
                          '${session.durationString}',
                        ),
                        action: SnackBarAction(
                          label: 'VIEW',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SessionHistoryScreen(),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                }
              } else {
                final userId = context.read<AuthService>().userId;
                ble.startRecording(userId: userId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Recording started')),
                );
              }
            },
          ),
          )
        );
      },
    );
  }

  /// Convert a list of typed data into FlSpots for the chart.
  /// X-axis = seconds since first data point. Null values are skipped.
  List<FlSpot> _buildSpots<T>(
    List<T> data,
    double? Function(T) getValue,
    DateTime Function(T) getTime,
  ) {
    if (data.isEmpty) return [];

    final origin = getTime(data.first);
    final spots = <FlSpot>[];

    for (final item in data) {
      final val = getValue(item);
      final x = getTime(item).difference(origin).inMilliseconds / 1000.0;
      if (val == null) {
        spots.add(FlSpot.nullSpot);
      } else {
        spots.add(FlSpot(x, val));
      }
    }

    return spots;
  }

  Future<List<String>?> _showTagPicker(BuildContext context) {
    return showModalBottomSheet<List<String>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (_) => const _TagPickerSheet(),
    );
  }

  List<PieChartSectionData> _buildPieSections(List<StressData> history) {
    if (history.isEmpty) return [];

    int low = 0, moderate = 0, high = 0;
    for (final s in history) {
      if (s.index < 0) continue;
      if (s.category == 0) {
        low++;
      } else if (s.category == 1) {
        moderate++;
      } else {
        high++;
      }
    }
    final total = low + moderate + high;
    if (total == 0) return [];

    return [
      PieChartSectionData(
        value: low.toDouble(),
        color: AppColors.levelLow, // one-hue blue ramp, paired with words
        title: '${(low / total * 100).toStringAsFixed(0)}%',
        titleStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        radius: 32,
      ),
      PieChartSectionData(
        value: moderate.toDouble(),
        color: AppColors.levelMid, // Colorblind-friendly Yellow
        title: '${(moderate / total * 100).toStringAsFixed(0)}%',
        titleStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        radius: 32,
      ),
      PieChartSectionData(
        value: high.toDouble(),
        color: AppColors.levelHigh, // Colorblind-friendly Red
        title: '${(high / total * 100).toStringAsFixed(0)}%',
        titleStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.deepBlack),
        radius: 32,
      ),
    ];
  }
}

class _PieLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _PieLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 12,
                color: isDark ? AppColors.textSecondary : Colors.grey.shade700)),
      ],
    );
  }
}

// ---- Tag Picker Sheet ----

const _kTags = [
  'Sitting', 'Mental Activity', 'Physical Activity',
  'Class', 'Study', 'Exam', 'Social', 'Exercise',
  'Break', 'Work', 'Commute', 'Sleep', 'Other',
];

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet();

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tag this session',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'What were you doing? (optional)',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kTags.map((tag) {
              final selected = _selected.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: selected,
                onSelected: (val) => setState(() {
                  val ? _selected.add(tag) : _selected.remove(tag);
                }),
                selectedColor: AppColors.emerald.withValues(alpha: 0.15),
                checkmarkColor: AppColors.emerald,
                labelStyle: TextStyle(
                  color: selected
                      ? AppColors.emerald
                      : Colors.grey.shade700,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, <String>[]),
                child: const Text('Skip'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _selected.toList()),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.emerald),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  BASELINE DELTA PANEL — shows ▲▼ change vs resting baseline per sensor
// ============================================================================
class _BaselineDeltaPanel extends StatelessWidget {
  final BaselineService baseline;
  final HRData hr;
  final HRVData hrv;
  final GSRData gsr;
  final TempData temp;

  const _BaselineDeltaPanel({
    required this.baseline,
    required this.hr,
    required this.hrv,
    required this.gsr,
    required this.temp,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardDark;

    return Card(
      margin: EdgeInsets.zero,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.compare_arrows_rounded,
                      color: AppColors.emerald, size: 16),
                ),
                const SizedBox(width: 8),
                const Text(
                  'vs. Resting Baseline',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.6),
                4: FlexColumnWidth(1.4),
              },
              children: [
                // Header row
                TableRow(
                  children: [
                    _th('Sensor'),
                    _th('Baseline'),
                    _th('Current'),
                    _th('Δ Change'),
                    _th('Z-Score'),
                  ],
                ),
                // HR row
                if (hr.valid)
                  _deltaRow(
                    label: 'HR',
                    unit: 'bpm',
                    baseline: baseline.hrMean,
                    std: baseline.hrStd,
                    current: hr.bpm.toDouble(),
                    stressDirection: 1, // ↑ HR = stress
                  ),
                // HRV (RMSSD) row
                if (hrv.valid && hrv.rmssd > 0)
                  _deltaRow(
                    label: 'HRV',
                    unit: 'ms',
                    baseline: baseline.hrvMean,
                    std: baseline.hrvStd,
                    current: hrv.rmssd,
                    stressDirection: -1, // ↓ HRV = stress
                  ),
                // GSR row
                if (gsr.microSiemens > 0)
                  _deltaRow(
                    label: 'GSR',
                    unit: 'µS',
                    baseline: baseline.gsrMean,
                    std: baseline.gsrStd,
                    current: gsr.microSiemens,
                    stressDirection: 1, // ↑ EDA = stress
                  ),
                // Temp row
                if (temp.skin > 20)
                  _deltaRow(
                    label: 'Temp',
                    unit: '°C',
                    baseline: baseline.tempMean,
                    std: baseline.tempStd,
                    current: temp.skin,
                    stressDirection: -1, // ↓ Temp = stress
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '* Δ Change = current − baseline  |  Z = (current − μ) / σ',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _th(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      );

  TableRow _deltaRow({
    required String label,
    required String unit,
    required double baseline,
    required double std,
    required double current,
    required int stressDirection, // +1 means ↑ is stress, -1 means ↓ is stress
  }) {
    final delta = current - baseline;
    final zScore = std > 0 ? delta / std : 0.0;
    final isStress = stressDirection == 1 ? delta > 0 : delta < 0;
    final color = zScore.abs() < 1.0
        ? AppColors.textSecondary
        : isStress
            ? AppColors.danger
            : AppColors.emerald;
    final arrow = delta > 0 ? '▲' : (delta < 0 ? '▼' : '─');

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${baseline.toStringAsFixed(1)} $unit',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${current.toStringAsFixed(1)} $unit',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '$arrow ${delta.abs().toStringAsFixed(1)} $unit',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${zScore >= 0 ? '+' : ''}${zScore.toStringAsFixed(2)}σ',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
//  HRV BAR CHART — inspired by the reference medical UI
// ============================================================================
class _HRVBarChart extends StatelessWidget {
  final List<HRVData> hrvHistory;
  final BaselineService baseline;

  const _HRVBarChart({required this.hrvHistory, required this.baseline});

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardDark;

    // Take last 24 readings (24 seconds of data for the bar chart)
    final recent = hrvHistory.length > 24
        ? hrvHistory.sublist(hrvHistory.length - 24)
        : hrvHistory;

    final valid = recent.where((h) => h.rmssd > 0).toList();
    if (valid.isEmpty) return const SizedBox();

    final avgRmssd = valid.map((h) => h.rmssd).reduce((a, b) => a + b) / valid.length;
    final maxRmssd = valid.map((h) => h.rmssd).reduce((a, b) => a > b ? a : b);
    final minRmssd = valid.map((h) => h.rmssd).reduce((a, b) => a < b ? a : b);
    final baselineVal = baseline.isCalibrated ? baseline.hrvMean : 0.0;
    final latestRmssd = valid.last.rmssd;

    // Compare to population norm: RMSSD > 20ms is healthy for students
    final comparisonText = avgRmssd > 30
        ? 'Your HRV is above resting baseline'
        : avgRmssd < 15
            ? 'Low HRV — elevated stress detected'
            : 'HRV within normal range';

    return Card(
      margin: EdgeInsets.zero,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: PpAccent.lilac.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.timeline_rounded,
                      color: PpAccent.lilac, size: 16),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Heart Rate Variability',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: PpAccent.lilac.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.monitor_heart_outlined,
                      color: PpAccent.lilac, size: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Big number + stats row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  latestRmssd.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'ms  RMSSD',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Max ${maxRmssd.toStringAsFixed(0)} ms',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                    Text(
                      'Min ${minRmssd.toStringAsFixed(0)} ms',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),

            if (baseline.isCalibrated) ...[
              const SizedBox(height: 2),
              Text(
                'Baseline: ${baselineVal.toStringAsFixed(1)} ms  |  '
                'Avg: ${avgRmssd.toStringAsFixed(1)} ms  |  '
                'SDNN: ${valid.last.sdnn.toStringAsFixed(1)} ms  |  '
                'pNN50: ${valid.last.pnn50.toStringAsFixed(1)}%',
                style: const TextStyle(
                    fontSize: 10.5, color: AppColors.textMuted),
              ),
            ],

            const SizedBox(height: 16),

            // Bar chart
            SizedBox(
              height: 80,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceEvenly,
                  maxY: (maxRmssd * 1.2).clamp(40, 200),
                  minY: 0,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (val, meta) {
                          if (val == 0) return const SizedBox();
                          return Text(
                            val.toInt().toString(),
                            style: const TextStyle(
                                fontSize: 9, color: AppColors.textMuted),
                          );
                        },
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: baselineVal > 0 ? baselineVal : 20,
                    getDrawingHorizontalLine: (val) => FlLine(
                      color: AppColors.border.withValues(alpha: 0.5),
                      strokeWidth: 0.5,
                      dashArray: [4, 4],
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  // Baseline reference line
                  extraLinesData: baseline.isCalibrated
                      ? ExtraLinesData(horizontalLines: [
                          HorizontalLine(
                            y: baselineVal,
                            color: AppColors.emerald.withValues(alpha: 0.7),
                            strokeWidth: 1.5,
                            dashArray: [6, 4],
                            label: HorizontalLineLabel(
                              show: true,
                              alignment: Alignment.topRight,
                              labelResolver: (_) => ' Baseline',
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.emerald,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ])
                      : null,
                  barGroups: recent.asMap().entries.map((entry) {
                    final i = entry.key;
                    final h = entry.value;
                    final val = h.rmssd > 0 ? h.rmssd : 0.0;
                    // Color: green if above baseline, orange if near, red if very low
                    final barColor = baseline.isCalibrated
                        ? (val >= baselineVal
                            ? PpAccent.lilac
                            : val >= baselineVal * 0.6
                                ? AppColors.gold
                                : AppColors.danger)
                        : PpAccent.lilac;

                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: val,
                          color: barColor,
                          width: 6,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Insight banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: avgRmssd > 20
                    ? PpAccent.lilac.withValues(alpha: 0.08)
                    : AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: avgRmssd > 20
                        ? PpAccent.lilac
                        : AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      comparisonText,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: avgRmssd > 20
                            ? PpAccent.lilac
                            : AppColors.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  PHASE 0 — Device not connected
// ============================================================================
class _ConnectDevicePanel extends StatelessWidget {
  final BleService ble;
  const _ConnectDevicePanel({required this.ble});

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    final t = Theme.of(context).textTheme;
    final isScanning = ble.state == BleConnectionState.scanning;
    final isConnecting = ble.state == BleConnectionState.connecting;
    final busy = isScanning || isConnecting;

    return _StagePanel(
      eyebrow: 'Your band',
      art: WristbandArt(size: 200, searching: busy),
      title: isConnecting
          ? 'Connecting to your band.'
          : isScanning
              ? 'Looking for your band.'
              : 'Your band is resting.',
      body: busy ? ble.statusMessage : 'Power it on and keep it close to this phone.',
      children: [
        if (!isConnecting)
          PillButton(
            label: isScanning ? 'Scanning' : 'Find my band',
            icon: Icons.bluetooth_searching_rounded,
            busy: isScanning,
            onPressed: isScanning ? null : () => ble.startScan(),
          ),
        if (isConnecting) const LinearProgressIndicator(),
        if (ble.scanResults.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('NEARBY', style: PpTheme.eyebrow(context, color: c.inkQuiet)),
          const SizedBox(height: 12),
          for (final (i, device) in ble.scanResults.indexed)
            Reveal(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SpringPress(
                  onTap: () => ble.connectToDevice(device),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: c.surfaceSunk,
                      borderRadius: BorderRadius.circular(PpRadius.control),
                      border: PpShadow.edge(c),
                    ),
                    child: Row(
                      children: [
                        const SensorGlyph(kind: SensorKind.hrv, size: 38),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(device.platformName.isNotEmpty ? device.platformName : 'Unknown device', style: t.titleMedium),
                              const SizedBox(height: 2),
                              Text(device.remoteId.toString(), style: t.bodySmall),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: c.brand),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Shared shell for the sensor-setup stages: a raised paper card with an
/// illustration on a soft inset stage, eyebrow, headline, body, actions.
class _StagePanel extends StatelessWidget {
  const _StagePanel({
    required this.eyebrow,
    required this.art,
    required this.title,
    required this.body,
    this.children = const [],
  });

  final String eyebrow;
  final Widget art;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    final t = Theme.of(context).textTheme;
    return PaperCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 176,
            decoration: BoxDecoration(
              color: c.surfaceSunk,
              borderRadius: BorderRadius.circular(PpRadius.panel - 8),
            ),
            alignment: Alignment.center,
            child: art,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(eyebrow.toUpperCase(), style: PpTheme.eyebrow(context)),
                const SizedBox(height: 8),
                Text(title, style: t.headlineMedium),
                const SizedBox(height: 8),
                Text(body, style: t.bodyLarge),
                if (children.isNotEmpty) const SizedBox(height: 22),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  PHASE 1 — Waiting for sensor readings
// ============================================================================
class _WaitingPanel extends StatelessWidget {
  final List<String> pendingSensors;
  const _WaitingPanel({required this.pendingSensors});

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    return _StagePanel(
      eyebrow: 'Almost there',
      art: const PanoMascot(mood: PanoMood.thinking, size: 120, prop: PanoProp.band),
      title: 'Listening for your signals.',
      body: 'Wear the band snugly so every sensor touches your skin.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in pendingSensors)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: c.surfaceSunk,
                  borderRadius: BorderRadius.circular(PpRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Pulse(child: Icon(Icons.circle, size: 7, color: c.brand)),
                    const SizedBox(width: 8),
                    Text(s, style: PpTheme.font(size: 13, weight: FontWeight.w600, color: c.inkMuted)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
//  PHASE 2 — All sensors ready, waiting for user to start calibration
// ============================================================================
class _ReadyToCalibratePanel extends StatelessWidget {
  final VoidCallback onStart;
  const _ReadyToCalibratePanel({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return _StagePanel(
      eyebrow: 'Everything is listening',
      art: const PanoMascot(mood: PanoMood.happy, size: 120, prop: PanoProp.leaf),
      title: 'Let us learn your calm.',
      body: 'Sit back and stay still for three minutes. Every reading after this is compared with you, not with anyone else.',
      children: [
        PillButton(label: 'Learn my baseline', icon: Icons.play_arrow_rounded, onPressed: onStart),
      ],
    );
  }
}

// ============================================================================
//  PHASE 3 — Baseline calibration in progress
// ============================================================================
class _CalibratingPanel extends StatelessWidget {
  final double progress; // 0.0 -> 1.0
  final Duration timeRemaining;
  const _CalibratingPanel({required this.progress, required this.timeRemaining});

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    final t = Theme.of(context).textTheme;
    final mins = timeRemaining.inMinutes;
    final secs = timeRemaining.inSeconds % 60;
    final timeStr = '$mins:${secs.toString().padLeft(2, '0')}';

    return _StagePanel(
      eyebrow: 'Calibrating',
      art: const PanoMascot(mood: PanoMood.breathe, size: 120),
      title: 'Learning your calm.',
      body: 'Stay seated and breathe as you normally would.',
      children: [
        HeartbeatTrace(color: c.brand, height: 44),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SpringValue(
                value: progress,
                builder: (_, v) => LinearProgressIndicator(value: v.clamp(0.0, 1.0), minHeight: 8),
              ),
            ),
            const SizedBox(width: 14),
            Text(timeStr, style: PpTheme.data(context, size: 18)),
          ],
        ),
        const SizedBox(height: 8),
        Text('${(progress * 100).round()}% learned', style: t.bodySmall),
      ],
    );
  }
}

/// Entry to the validated check-in. When a sustained change from the person's
/// usual has been noticed, it says so in plain words first.
class _CheckInCard extends StatelessWidget {
  const _CheckInCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cd = context.watch<ChangeDetector>();
    final changing = cd.isChanging;
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PaperHeading(
                  eyebrow: changing ? 'Something shifted' : 'Two minutes for you',
                  title: changing ? 'A change from your usual.' : 'How are you, really?',
                  titleStyle: t.headlineMedium,
                ),
              ),
              PanoMascot(
                mood: changing ? PanoMood.alert : PanoMood.wave,
                size: 84,
                prop: changing ? null : PanoProp.heart,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            changing ? cd.assessment!.summary : 'Four questions. Your answers stay on this phone.',
            style: t.bodyLarge,
          ),
          if (cd.isSynthetic) ...[
            const SizedBox(height: PpSpace.s2),
            Text('Demo history: synthetic data', style: t.labelSmall),
          ],
          const SizedBox(height: 20),
          PillButton(
            label: 'Start my check-in',
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CheckInScreen(promptedByChange: changing)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckInScreen(instrument: Instrument.pss4)),
            ),
            child: const Text('Or a stress check for the last month'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  Paper chrome: backdrop, top bar, greeting, status hero, headings, record
// ============================================================================

/// Paper surface (fine grain, faint drifting light) behind the whole screen.
class _DashboardBackdrop extends StatelessWidget {
  const _DashboardBackdrop({required this.calm, required this.child});
  final double calm;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: AuroraBackground(calm: calm)),
        child,
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.ble,
    required this.firstName,
    required this.isDark,
    required this.onToggleTheme,
  });

  final BleService ble;
  final String firstName;
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final connected = ble.state == BleConnectionState.connected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(PpSpace.gutter, 14, 16, 4),
      child: Row(
        children: [
          const BrandTile(size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('PHYSIOPAÑO', maxLines: 1, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                ),
                Text(connected ? 'Band connected' : 'Wearable wellbeing', style: t.bodySmall),
              ],
            ),
          ),
          RoundPaperButton(
            icon: Icons.mood_rounded,
            tooltip: 'Mood journal',
            size: 44,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodJournalScreen())),
          ),
          const SizedBox(width: 8),
          RoundPaperButton(
            icon: connected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_rounded,
            tooltip: connected ? 'Disconnect' : 'Scan for device',
            size: 44,
            active: connected,
            onTap: () => connected ? ble.disconnect() : ble.startScan(),
          ),
        ],
      ),
    );
  }
}

/// Eyebrow + big tight greeting, like the opening of a magazine page.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.firstName, required this.ble});
  final String firstName;
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    final h = DateTime.now().hour;
    final part = h < 12 ? 'morning' : (h < 18 ? 'afternoon' : 'evening');
    final name = firstName.isEmpty ? '' : ', $firstName';
    final battery = ble.stress.battery;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaperHeading(
          eyebrow: 'Your body, today',
          title: 'Good $part$name.',
          lede: 'A calm look at how you are doing, compared only with you.',
        ),
        if (battery > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(PpRadius.pill),
              border: PpShadow.edge(c),
              boxShadow: PpShadow.raised(c, lift: 0.4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  battery > 60 ? Icons.battery_full_rounded : (battery > 20 ? Icons.battery_3_bar_rounded : Icons.battery_alert_rounded),
                  size: 16,
                  color: battery <= 15 ? c.crisis : c.brand,
                ),
                const SizedBox(width: 6),
                Text('Band battery $battery%', style: PpTheme.font(size: 13, weight: FontWeight.w600, color: c.inkMuted)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The one ink feature card on Today. Pano and a live heartbeat line reflect
/// the state; a single blue action offers the next helpful step.
class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.ble, required this.stress});
  final BleService ble;
  final StressData stress;

  (PanoMood, String, String, String) _state() {
    if (ble.state != BleConnectionState.connected) {
      return (PanoMood.sleepy, 'Waiting for your band', 'Pick up where you left off.', 'Connect your band and Paño will start listening again.');
    }
    if (ble.isCalibrating) {
      return (PanoMood.breathe, 'Calibrating', 'Breathing with you.', 'Learning what your calm looks like.');
    }
    if (!ble.isCalibrated) {
      return (PanoMood.thinking, 'First step', 'Let us get to know you.', 'A short baseline makes every reading personal.');
    }
    if (ble.isRecording) {
      return (PanoMood.wave, 'Recording', 'Capturing this moment.', 'Tap stop when you are done.');
    }
    if (stress.index < 0) {
      return (PanoMood.calm, 'Settling in', 'Reading your signals.', 'Your first numbers appear in a few seconds.');
    }
    return switch (stress.category) {
      0 => (PanoMood.happy, 'Right now', 'Close to your usual.', 'Your body looks settled. Nice.'),
      1 => (PanoMood.thinking, 'Right now', 'A little above your usual.', 'A slow breath or a short walk can help.'),
      _ => (PanoMood.alert, 'Right now', 'Well above your usual.', 'Want to try a one-minute breathing reset?'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    final t = Theme.of(context).textTheme;
    final (mood, eyebrow, title, body) = _state();
    final connected = ble.state == BleConnectionState.connected;
    final bpm = ble.hr.valid ? ble.hr.bpm.toDouble() : 72.0;
    return TiltCard(
      maxTilt: 0.05,
      child: InkCard(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(child: AuroraBackground(base: c.panel, intensity: 0.32, calm: stress.index < 0 ? 1 : 1 - stress.category / 2)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: FadeThroughSwitcher(
                          child: Column(
                            key: ValueKey(title),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(connected ? Icons.sensors_rounded : Icons.sensors_off_rounded, size: 16, color: c.onPanel.withValues(alpha: 0.8)),
                                  const SizedBox(width: 8),
                                  Text(eyebrow.toUpperCase(),
                                      style: PpTheme.eyebrow(context, color: c.onPanel.withValues(alpha: 0.85))),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(title, style: t.headlineLarge?.copyWith(color: c.onPanel)),
                              const SizedBox(height: 10),
                              Text(body, style: t.bodyLarge?.copyWith(color: c.onPanel.withValues(alpha: 0.78))),
                            ],
                          ),
                        ),
                      ),
                      PanoMascot(mood: mood, size: 80),
                    ],
                  ),
                  const SizedBox(height: 16),
                  HeartbeatTrace(color: const Color(0xFF8FB2FA), height: 46, bpm: bpm, strokeWidth: 2.2),
                  const SizedBox(height: 18),
                  if (!connected)
                    PillButton(
                      label: 'Find my band',
                      trailingIcon: Icons.arrow_forward_rounded,
                      expand: false,
                      onPressed: () => ble.startScan(),
                    )
                  else
                    PillButton(
                      label: 'Breathing reset',
                      icon: Icons.air_rounded,
                      expand: false,
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BreathingScreen())),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.caption});
  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) => PaperSectionTitle(title: title, caption: caption);
}

/// Record toggle: blue pill with glow; while recording an ink pill with a
/// live dot and the elapsed time (the width change animates).
class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.recording, required this.onPressed, this.elapsed});
  final bool recording;
  final String? elapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    final fg = recording ? c.onPanel : c.onBrand;
    return Semantics(
      button: true,
      label: recording ? 'Stop recording' : 'Record session',
      child: SpringPress(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: PpMotion.slow,
          curve: PpMotion.settle,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: recording ? c.panel : null,
            gradient: recording
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.lerp(c.brand, Colors.white, 0.14)!, c.brand],
                  ),
            borderRadius: BorderRadius.circular(PpRadius.pill),
            boxShadow: recording
                ? [BoxShadow(color: c.panel.withValues(alpha: 0.3), blurRadius: 24, spreadRadius: -8, offset: const Offset(0, 12))]
                : PpShadow.brand(c),
          ),
          child: AnimatedSize(
            duration: PpMotion.slow,
            curve: PpMotion.ease,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                recording
                    ? Pulse(child: Icon(Icons.stop_rounded, color: fg))
                    : Icon(Icons.fiber_manual_record_rounded, color: fg, size: 18),
                const SizedBox(width: 10),
                Text(
                  recording ? 'Stop  ${elapsed ?? ''}' : 'Record session',
                  style: PpTheme.font(size: 15, weight: FontWeight.w700, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
