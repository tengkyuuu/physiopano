// SPRINGS: make UI feel responsive.
//
// SpringPress wraps any tappable surface. Pointer-down compresses it, release
// lets a real spring simulation carry it back past 1.0 and settle, so the
// surface feels like it has mass instead of an easing curve.

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/physiopano_tokens.dart';

class SpringPress extends StatefulWidget {
  const SpringPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.94,
    this.spring = PpMotion.snappy,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final SpringDescription spring;
  final bool haptic;

  @override
  State<SpringPress> createState() => _SpringPressState();
}

class _SpringPressState extends State<SpringPress> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: 1);

  void _to(double target, {double velocity = 0}) {
    if (PpMotion.reduced(context)) {
      _c.value = 1;
      return;
    }
    _c.animateWith(SpringSimulation(widget.spring, _c.value, target, velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _to(widget.pressedScale) : null,
      onTapCancel: enabled ? () => _to(1, velocity: 2) : null,
      onTapUp: enabled ? (_) => _to(1, velocity: 3) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.scale(scale: _c.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// A value that chases its target with a spring. Use for numbers that update
/// from live sensors so they glide instead of jumping (HR, scores, gauges).
class SpringValue extends StatefulWidget {
  const SpringValue({super.key, required this.value, required this.builder, this.spring = PpMotion.soft});

  final double value;
  final SpringDescription spring;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<SpringValue> createState() => _SpringValueState();
}

class _SpringValueState extends State<SpringValue> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: widget.value);

  @override
  void didUpdateWidget(SpringValue old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      if (PpMotion.reduced(context)) {
        _c.value = widget.value;
      } else {
        _c.animateWith(SpringSimulation(widget.spring, _c.value, widget.value, _c.velocity));
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _c, builder: (context, _) => widget.builder(context, _c.value));
}
