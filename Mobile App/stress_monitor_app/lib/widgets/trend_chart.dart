import 'package:flutter/material.dart';
import '../services/theme_provider.dart';
import '../theme/physiopano_tokens.dart';
import 'package:fl_chart/fl_chart.dart';

/// Generic time-series line chart for sensor history data.
/// Used on both the live dashboard and session detail screen.
class TrendChart extends StatelessWidget {
  final String title;
  final List<FlSpot> spots;
  final Color lineColor;
  final double? minY;
  final double? maxY;
  final String yLabel;
  final String xLabel;
  final bool showDots;

  const TrendChart({
    super.key,
    required this.title,
    required this.spots,
    this.lineColor = PpAccent.sky,
    this.minY,
    this.maxY,
    this.yLabel = '',
    this.xLabel = 'Time (s)',
    this.showDots = false,
  });

  @override
  Widget build(BuildContext context) {
    if (spots.length < 2) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 30),
              Text(
                'Waiting for data...',
                style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.textSecondary
                        : AppColors.textSecondary),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _calcInterval(),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: _calcXInterval(),
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${value.toInt()}s',
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? AppColors.textSecondary
                                    : AppColors.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: _calcInterval(),
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(
                              value == value.roundToDouble() ? 0 : 1,
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.textSecondary
                                  : AppColors.textMuted,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: spots.first.x,
                  maxX: spots.last.x,
                  minY: minY ?? _autoMinY(),
                  maxY: maxY ?? _autoMaxY(),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      color: lineColor,
                      barWidth: 2.5,
                      dotData: FlDotData(show: showDots),
                      preventCurveOverShooting: true,
                      belowBarData: BarAreaData(
                        show: true,
                        color: lineColor.withValues(
                            alpha:
                                Theme.of(context).brightness == Brightness.dark
                                    ? 0.2
                                    : 0.08),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((s) {
                        return LineTooltipItem(
                          '${s.y.toStringAsFixed(1)} $yLabel',
                          TextStyle(
                            color: lineColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _autoMinY() {
    final validSpots = spots.where((s) => s != FlSpot.nullSpot && !s.y.isNaN);
    if (validSpots.isEmpty) return 0;
    final vals = validSpots.map((s) => s.y);
    final min = vals.reduce((a, b) => a < b ? a : b);
    return (min - (min.abs() * 0.1)).floorToDouble();
  }

  double _autoMaxY() {
    final validSpots = spots.where((s) => s != FlSpot.nullSpot && !s.y.isNaN);
    if (validSpots.isEmpty) return 100;
    final vals = validSpots.map((s) => s.y);
    final max = vals.reduce((a, b) => a > b ? a : b);
    return (max + (max.abs() * 0.1)).ceilToDouble();
  }

  double _calcInterval() {
    final range = (maxY ?? _autoMaxY()) - (minY ?? _autoMinY());
    if (range <= 0) return 1;
    if (range <= 5) return 1;
    if (range <= 20) return 5;
    if (range <= 50) return 10;
    return 25;
  }

  double _calcXInterval() {
    final validSpots = spots.where((s) => s != FlSpot.nullSpot).toList();
    if (validSpots.length < 2) return 1;
    final range = validSpots.last.x - validSpots.first.x;
    if (range <= 30) return 5;
    if (range <= 120) return 30;
    return 60;
  }
}
