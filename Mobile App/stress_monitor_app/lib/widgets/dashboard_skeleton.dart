import 'dart:math';
import 'package:flutter/material.dart';
import 'shimmer_box.dart';
import '../services/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Public skeleton components — drop-in replacements used by DashboardScreen
//  while BLE sensors are initialising (Phase 1).
// ─────────────────────────────────────────────────────────────────────────────

/// 2-column grid of skeleton sensor cards.
class SensorCardSkeletonGrid extends StatelessWidget {
  const SensorCardSkeletonGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.15,
      children: const [
        _SensorCardSkeleton(),
        _SensorCardSkeleton(),
        _SensorCardSkeleton(),
        _SensorCardSkeleton(),
        _SensorCardSkeleton(),
        _SensorCardSkeleton(),
      ],
    );
  }
}

/// Two stacked skeleton chart cards.
class ChartSkeletonSection extends StatelessWidget {
  const ChartSkeletonSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShimmerBox(width: 160, height: 16, borderRadius: 6),
        SizedBox(height: 12),
        _ChartSkeleton(),
        SizedBox(height: 10),
        _ChartSkeleton(),
      ],
    );
  }
}

/// Circular gauge skeleton — mirrors the 200×200 StressGauge widget.
class GaugeSkeleton extends StatefulWidget {
  const GaugeSkeleton({super.key});

  @override
  State<GaugeSkeleton> createState() => _GaugeSkeletonState();
}

class _GaugeSkeletonState extends State<GaugeSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _GaugeSkeletonPainter(_ctrl.value),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShimmerBox(width: 56, height: 44, borderRadius: 8),
                SizedBox(height: 6),
                ShimmerBox(width: 52, height: 11, borderRadius: 4),
                SizedBox(height: 4),
                ShimmerBox(width: 70, height: 9, borderRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Private helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SensorCardSkeleton extends StatelessWidget {
  const _SensorCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          top: BorderSide(
            color: AppColors.emerald.withValues(alpha: 0.10),
            width: 2,
          ),
          left: const BorderSide(color: Color(0xFF162F30), width: 1),
          right: const BorderSide(color: Color(0xFF162F30), width: 1),
          bottom: const BorderSide(color: Color(0xFF162F30), width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              ShimmerBox(width: 34, height: 34, borderRadius: 10),
              SizedBox(width: 8),
              Expanded(child: ShimmerBox(height: 11, borderRadius: 5)),
            ],
          ),
          ShimmerBox(height: 30, borderRadius: 6),
          ShimmerBox(height: 10, borderRadius: 5),
        ],
      ),
    );
  }
}

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          top: BorderSide(
            color: AppColors.emerald.withValues(alpha: 0.10),
            width: 2,
          ),
          left: const BorderSide(color: Color(0xFF162F30), width: 1),
          right: const BorderSide(color: Color(0xFF162F30), width: 1),
          bottom: const BorderSide(color: Color(0xFF162F30), width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerBox(width: 8, height: 8, borderRadius: 4),
              SizedBox(width: 8),
              ShimmerBox(width: 100, height: 13, borderRadius: 5),
            ],
          ),
          SizedBox(height: 12),
          ShimmerBox(height: 120, borderRadius: 8),
        ],
      ),
    );
  }
}

class _GaugeSkeletonPainter extends CustomPainter {
  final double t;

  const _GaugeSkeletonPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;
    const startAngle = pi * 0.75;
    const sweepTotal = pi * 1.5;

    // Background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      Paint()
        ..color = const Color(0xFF12292A)
        ..strokeWidth = 12
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Shimmer segment that sweeps around the arc
    final segStart = startAngle + (t * sweepTotal);
    const segLen = 0.9;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      segStart,
      segLen,
      false,
      Paint()
        ..strokeWidth = 12
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: segStart - 0.15,
          endAngle: segStart + segLen + 0.15,
          colors: const [
            Color(0xFF12292A),
            Color(0xFF1B3637),
            Color(0xFF203E3F),
            Color(0xFF1B3637),
            Color(0xFF12292A),
          ],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
          tileMode: TileMode.clamp,
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(covariant _GaugeSkeletonPainter old) => old.t != t;
}
