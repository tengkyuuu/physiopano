import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/physiopano_tokens.dart';
import '../services/theme_provider.dart';

/// Circular stress gauge — mirrors the firmware RGB LED scheme.
///   Green (0–25) → Amber (26–75) → Red (76–100)
///   Purple ring = chronic stress detected
class StressGauge extends StatelessWidget {
  final double stressIndex; // 0–100, or -1 for no data
  final String label;
  final bool chronic;
  final bool calibrating;
  final double probability;

  const StressGauge({
    super.key,
    required this.stressIndex,
    required this.label,
    this.chronic = false,
    this.calibrating = false,
    this.probability = 0.0,
  });

  Color get _stressColor {
    if (calibrating) return Colors.cyan;
    if (stressIndex < 0) return Colors.grey;
    if (chronic) return PpAccent.lilac;
    if (stressIndex <= 25) return AppColors.levelLow;
    if (stressIndex <= 75) return AppColors.levelMid;
    return AppColors.levelHigh;
  }

  String get _interpretation {
    if (calibrating) return 'Collecting baseline data…';
    if (stressIndex < 0) return 'Waiting for data';
    if (stressIndex <= 25) return 'Low physiological strain — you appear calm';
    if (stressIndex <= 50) return 'Mild strain — slightly elevated response';
    if (stressIndex <= 75) return 'Moderate strain — notable stress response';
    return 'High strain — significant stress response';
  }

  @override
  Widget build(BuildContext context) {
    final progress = stressIndex >= 0 ? stressIndex / 100.0 : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Circular gauge ──────────────────────────────────────────────
        SizedBox(
          width: 180,
          height: 180,
          child: CustomPaint(
            painter: _GaugePainter(
              progress: progress,
              color: _stressColor,
              chronic: chronic,
              isDark: isDark,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (calibrating)
                    const Text(
                      'Calibrating',
                      style: TextStyle(fontSize: 13, color: Colors.cyan),
                    )
                  else ...[
                    Text(
                      stressIndex >= 0
                          ? stressIndex.toStringAsFixed(0)
                          : '--',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        color: _stressColor,
                        height: 1.0,
                      ),
                    ),
                    const Text(
                      '/100',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: _stressColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _stressColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    if (chronic) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'CHRONIC',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: PpAccent.lilac,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),

        // ── Confidence + interpretation ─────────────────────────────────
        if (!calibrating) ...[
          const SizedBox(height: 8),
          if (probability > 0)
            Text(
              '${(probability * 100).toStringAsFixed(0)}% confidence',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            _interpretation,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.textSecondary : AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          // ── Stress zone bar ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // Tick marker
                LayoutBuilder(builder: (context, constraints) {
                  final frac = stressIndex >= 0
                      ? (stressIndex / 100.0).clamp(0.0, 1.0)
                      : 0.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Gradient bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 8,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.levelLow,
                                AppColors.levelMid,
                                AppColors.levelHigh,
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Position indicator
                      if (stressIndex >= 0)
                        Positioned(
                          left: constraints.maxWidth * frac - 6,
                          top: -4,
                          child: Container(
                            width: 12,
                            height: 16,
                            decoration: BoxDecoration(
                              color: _stressColor,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                  color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  );
                }),
                const SizedBox(height: 4),
                // Zone labels
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Low',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.levelLow)),
                    Text('Moderate',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.levelMid)),
                    Text('High',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.levelHigh)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool chronic;
  final bool isDark;

  _GaugePainter({
    required this.progress,
    required this.color,
    required this.chronic,
    this.isDark = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;

    final bgPaint = Paint()
      ..color = isDark ? AppColors.cardDarkAlt : Colors.grey.shade200
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi * 0.75,
      pi * 1.5,
      false,
      bgPaint,
    );

    if (progress > 0) {
      final fgPaint = Paint()
        ..color = color
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        pi * 0.75,
        pi * 1.5 * progress,
        false,
        fgPaint,
      );
    }

    if (chronic) {
      final chronicPaint = Paint()
        ..color = PpAccent.lilac.withValues(alpha: 0.3)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(center, radius + 8, chronicPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.chronic != chronic;
}
