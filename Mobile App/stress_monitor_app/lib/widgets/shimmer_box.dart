import 'package:flutter/material.dart';

/// Atomic shimmer placeholder block — the base of all skeleton UI in PHYSIOPAÑO.
///
/// The highlight sweeps left-to-right using the brand's dark-forest palette
/// with a subtle emerald-tinted peak. No external package required.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // t sweeps from -1.0 → +2.0 so the gradient fully traverses the widget
        final t = (_ctrl.value * 3.0) - 1.0;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(t - 0.8, 0),
              end: Alignment(t + 0.8, 0),
              colors: const [
                Color(0xFF12292A), // base dark
                Color(0xFF162F30), // ramp up
                Color(0xFF1B3637), // emerald-tinted peak
                Color(0xFF162F30), // ramp down
                Color(0xFF12292A), // base dark
              ],
              stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
            ),
          ),
        );
      },
    );
  }
}
