// KEYFRAMES: choreograph a sequence.
//
// Reveal plays a three-key entrance (hidden -> overshoot -> rest) with a
// stagger index, so a screen's sections arrive in order instead of all at
// once. Pulse is a looping keyframe track for "alive" indicators.

import 'package:flutter/material.dart';

import '../theme/physiopano_tokens.dart';

class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 70),
    this.offset = const Offset(0, 28),
    this.duration = PpMotion.entrance,
  });

  final Widget child;
  final int index;
  final Duration stagger;
  final Offset offset;
  final Duration duration;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);

  // Keyframes: opacity 0 -> 1 over the first 55%; translate 100% -> -4% -> 0.
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _c, curve: const Interval(0, 0.55, curve: Curves.easeOut));
  late final Animation<double> _travel = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: -0.04).chain(CurveTween(curve: PpMotion.ease)), weight: 70),
    TweenSequenceItem(tween: Tween(begin: -0.04, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
  ]).animate(_c);
  late final Animation<double> _scale = Tween(begin: 0.97, end: 1.0).animate(CurvedAnimation(parent: _c, curve: PpMotion.ease));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.stagger * widget.index, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PpMotion.reduced(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(
          offset: widget.offset * _travel.value,
          child: Transform.scale(scale: _scale.value, child: child),
        ),
      ),
    );
  }
}

/// Looping "heartbeat" keyframe track: quick double-beat then rest.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child, this.period = const Duration(milliseconds: 1400), this.amount = 0.12});

  final Widget child;
  final Duration period;
  final double amount;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);
  late final Animation<double> _beat = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 10),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.3).chain(CurveTween(curve: Curves.easeIn)), weight: 10),
    TweenSequenceItem(tween: Tween(begin: 0.3, end: 0.8).chain(CurveTween(curve: Curves.easeOut)), weight: 8),
    TweenSequenceItem(tween: Tween(begin: 0.8, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 22),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
  ]).animate(_c);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PpMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _beat,
        child: widget.child,
        builder: (_, child) => Transform.scale(scale: 1 + widget.amount * _beat.value, child: child),
      );
}

/// Expanding rings that radiate from a centre: for "searching" and "live".
class Ripples extends StatefulWidget {
  const Ripples({super.key, required this.color, this.size = 160, this.rings = 3, this.child});

  final Color color;
  final double size;
  final int rings;
  final Widget? child;

  @override
  State<Ripples> createState() => _RipplesState();
}

class _RipplesState extends State<Ripples> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _RipplePainter(_c, widget.color, widget.rings),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.anim, this.color, this.rings) : super(repaint: anim);
  final Animation<double> anim;
  final Color color;
  final int rings;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    for (var i = 0; i < rings; i++) {
      final t = (anim.value + i / rings) % 1.0;
      final r = maxR * (0.3 + 0.7 * Curves.easeOut.transform(t));
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + 2 * (1 - t)
        ..color = color.withValues(alpha: 0.55 * (1 - t));
      canvas.drawCircle(c, r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.color != color;
}
