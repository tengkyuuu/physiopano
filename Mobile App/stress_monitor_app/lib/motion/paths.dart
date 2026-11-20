// SVG PATHS: draw, morph, follow a line.
//
// HeartbeatTrace draws a looping ECG line with a glowing head that follows the
// path (PathMetric.getTangentForOffset). MorphBlob morphs between organic
// shapes by interpolating radial control points: used for the breathing orb.
// DrawOn reveals any path stroke-by-stroke, like an SVG stroke-dashoffset.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/physiopano_tokens.dart';

class HeartbeatTrace extends StatefulWidget {
  const HeartbeatTrace({
    super.key,
    required this.color,
    this.height = 56,
    this.bpm = 72,
    this.strokeWidth = 2.5,
  });

  final Color color;
  final double height;
  final double bpm;
  final double strokeWidth;

  @override
  State<HeartbeatTrace> createState() => _HeartbeatTraceState();
}

class _HeartbeatTraceState extends State<HeartbeatTrace> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _period())..repeat();

  Duration _period() {
    final bpm = widget.bpm.clamp(40, 160);
    // Two beats travel across the strip per loop.
    return Duration(milliseconds: (2 * 60000 / bpm).round());
  }

  @override
  void didUpdateWidget(HeartbeatTrace old) {
    super.didUpdateWidget(old);
    if ((old.bpm - widget.bpm).abs() > 3) {
      _c.duration = _period();
      if (_c.isAnimating) _c.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PpMotion.reduced(context)) {
      _c.stop();
      _c.value = 0.999;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(painter: _TracePainter(_c, widget.color, widget.strokeWidth)),
      );
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.t, this.color, this.width) : super(repaint: t);
  final Animation<double> t;
  final Color color;
  final double width;

  Path _ecg(Size s) {
    final p = Path();
    final mid = s.height * 0.6;
    p.moveTo(0, mid);
    for (var beat = 0; beat < 2; beat++) {
      final x0 = s.width * beat / 2;
      final w = s.width / 2;
      p.lineTo(x0 + w * 0.18, mid);
      p.quadraticBezierTo(x0 + w * 0.23, mid - s.height * 0.12, x0 + w * 0.28, mid); // P wave
      p.lineTo(x0 + w * 0.36, mid);
      p.lineTo(x0 + w * 0.40, mid + s.height * 0.12); // Q
      p.lineTo(x0 + w * 0.45, s.height * 0.05); // R
      p.lineTo(x0 + w * 0.50, s.height * 0.92); // S
      p.lineTo(x0 + w * 0.55, mid);
      p.quadraticBezierTo(x0 + w * 0.66, mid - s.height * 0.22, x0 + w * 0.76, mid); // T wave
      p.lineTo(x0 + w, mid);
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _ecg(size);
    final metric = path.computeMetrics().first;
    final head = metric.length * t.value;
    const tail = 0.55; // fraction of length that stays visible

    final start = head - metric.length * tail;
    final segs = <Path>[];
    if (start < 0) {
      segs.add(metric.extractPath(metric.length + start, metric.length));
      segs.add(metric.extractPath(0, head));
    } else {
      segs.add(metric.extractPath(start, head));
    }

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 4
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final s in segs) {
      canvas.drawPath(s, glow);
    }
    // Tail fades out: draw the visible window in 12 slices of rising alpha.
    const slices = 12;
    final window = metric.length * tail;
    for (var i = 0; i < slices; i++) {
      final a = head - window + window * i / slices;
      final b = head - window + window * (i + 1) / slices + 0.5;
      final alpha = (i + 1) / slices;
      void draw(double from, double to) {
        if (to <= from) return;
        canvas.drawPath(metric.extractPath(from, to), line..color = color.withValues(alpha: alpha * 0.95));
      }
      if (a < 0 && b < 0) {
        draw(metric.length + a, metric.length + b);
      } else if (a < 0) {
        draw(metric.length + a, metric.length);
        draw(0, b);
      } else {
        draw(a, b);
      }
    }
    final tangent = metric.getTangentForOffset(head);
    if (tangent != null) {
      canvas.drawCircle(tangent.position, width * 3.2, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(tangent.position, width * 1.6, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _TracePainter old) => old.color != color;
}

/// An organic blob that morphs between seeds over time and can scale with an
/// external "breath" value (0..1).
class MorphBlob extends StatefulWidget {
  const MorphBlob({
    super.key,
    required this.colors,
    this.size = 240,
    this.breath,
    this.wobble = 0.08,
    this.child,
  });

  final List<Color> colors;
  final double size;
  final ValueListenable<double>? breath;
  final double wobble;
  final Widget? child;

  @override
  State<MorphBlob> createState() => _MorphBlobState();
}

class _MorphBlobState extends State<MorphBlob> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = PpMotion.reduced(context);
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _BlobPainter(
          time: _c,
          breath: widget.breath,
          colors: widget.colors,
          wobble: reduced ? 0 : widget.wobble,
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({required this.time, required this.breath, required this.colors, required this.wobble})
      : super(repaint: Listenable.merge([time, if (breath != null) breath]));

  final Animation<double> time;
  final ValueListenable<double>? breath;
  final List<Color> colors;
  final double wobble;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final b = breath?.value ?? 0.5;
    final base = size.shortestSide / 2 * (0.62 + 0.3 * b);
    const n = 8;
    final t = time.value * 2 * math.pi;
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final a = i / n * 2 * math.pi;
      final r = base * (1 + wobble * math.sin(t * 2 + i * 1.7) + wobble * 0.6 * math.cos(t + i * 2.3));
      pts.add(c + Offset(math.cos(a), math.sin(a)) * r);
    }
    // Catmull-Rom through the points -> smooth closed cubic path.
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    path.close();

    final rect = Rect.fromCircle(center: c, radius: base * 1.2);
    canvas.drawPath(
      path.shift(const Offset(0, 0)),
      Paint()
        ..color = colors.first.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, base * 0.25),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = SweepGradient(
          colors: [...colors, colors.first],
          transform: GradientRotation(t * 0.5),
        ).createShader(rect),
    );
    // Soft inner highlight.
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.8,
          colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) => old.colors != colors || old.wobble != wobble;
}

/// Reveals a stroke along its length once, like an SVG stroke-dashoffset.
class DrawOn extends StatefulWidget {
  const DrawOn({
    super.key,
    required this.pathBuilder,
    required this.color,
    this.size = const Size(64, 64),
    this.strokeWidth = 4,
    this.duration = const Duration(milliseconds: 700),
    this.delay = Duration.zero,
  });

  final Path Function(Size size) pathBuilder;
  final Color color;
  final Size size;
  final double strokeWidth;
  final Duration duration;
  final Duration delay;

  /// A tick mark, for success states.
  static Path check(Size s) => Path()
    ..moveTo(s.width * 0.22, s.height * 0.52)
    ..lineTo(s.width * 0.43, s.height * 0.72)
    ..lineTo(s.width * 0.80, s.height * 0.30);

  @override
  State<DrawOn> createState() => _DrawOnState();
}

class _DrawOnState extends State<DrawOn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
        size: widget.size,
        child: CustomPaint(
          painter: _DrawOnPainter(CurvedAnimation(parent: _c, curve: PpMotion.ease), widget),
        ),
      );
}

class _DrawOnPainter extends CustomPainter {
  _DrawOnPainter(this.t, this.w) : super(repaint: t);
  final Animation<double> t;
  final DrawOn w;

  @override
  void paint(Canvas canvas, Size size) {
    final path = w.pathBuilder(size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = w.color;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * t.value), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawOnPainter old) => false;
}
