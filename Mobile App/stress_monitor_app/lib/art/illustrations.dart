// PHYSIOPAÑO clipart: painted vector illustrations, theme-aware, no assets.
//
//   WristbandArt   the StressMonitor band, with a live LED and floating signal arcs
//   SensorGlyph    small badge art per sensor (heart, skin/GSR, temp, motion, HRV)
//   SparkleField   twinkling 4-point stars for hero corners
//   SceneCard      a mascot-on-a-blob composition for empty states and banners
//   CalmHills      layered parallax hills for headers and the breathing screen

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/keyframes.dart';
import '../theme/physiopano_tokens.dart';
import 'pano_mascot.dart';

/// The wristband, three-quarter view, with an animated status LED and
/// signal arcs radiating while [searching] or [live].
class WristbandArt extends StatefulWidget {
  const WristbandArt({super.key, this.size = 180, this.live = false, this.searching = false});

  final double size;
  final bool live;
  final bool searching;

  @override
  State<WristbandArt> createState() => _WristbandArtState();
}

class _WristbandArtState extends State<WristbandArt> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PpMotion.reduced(context)) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    return SizedBox(
      width: widget.size,
      height: widget.size * 0.8,
      child: CustomPaint(
        painter: _WristbandPainter(_c, c, live: widget.live, searching: widget.searching),
      ),
    );
  }
}

class _WristbandPainter extends CustomPainter {
  _WristbandPainter(this.t, this.c, {required this.live, required this.searching}) : super(repaint: t);
  final Animation<double> t;
  final PpColors c;
  final bool live, searching;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final center = Offset(w * 0.5, h * 0.58);

    // Strap: an ellipse ring seen at an angle.
    final strapOuter = Rect.fromCenter(center: center, width: w * 0.86, height: h * 0.5);
    final strapInner = Rect.fromCenter(center: center.translate(0, -h * 0.02), width: w * 0.66, height: h * 0.3);
    final strap = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(strapOuter)
      ..addOval(strapInner);
    canvas.drawPath(
      strap,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF2A3247), Color(0xFF1A2030)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(strapOuter),
    );
    // Strap holes.
    for (var i = 0; i < 4; i++) {
      final a = math.pi * (0.62 + i * 0.07);
      canvas.drawCircle(
        center + Offset(math.cos(a) * w * 0.38, math.sin(a) * h * 0.22),
        w * 0.008,
        Paint()..color = Colors.black.withValues(alpha: 0.5),
      );
    }

    // Module (the pod) on top.
    final pod = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center.translate(0, -h * 0.2), width: w * 0.42, height: h * 0.34),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(pod.shift(Offset(0, h * 0.04)), Paint()..color = const Color(0xFF242A32).withValues(alpha: 0.18));
    canvas.drawRRect(
      pod,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A4462), Color(0xFF20263A)],
        ).createShader(pod.outerRect),
    );
    // Screen.
    final screen = pod.deflate(w * 0.03);
    canvas.drawRRect(screen, Paint()..color = const Color(0xFF0A0D13));

    // Mini ECG on the screen.
    final sr = screen.outerRect;
    final ecg = Path()..moveTo(sr.left + sr.width * 0.1, sr.center.dy);
    ecg
      ..lineTo(sr.left + sr.width * 0.35, sr.center.dy)
      ..lineTo(sr.left + sr.width * 0.43, sr.top + sr.height * 0.22)
      ..lineTo(sr.left + sr.width * 0.52, sr.bottom - sr.height * 0.2)
      ..lineTo(sr.left + sr.width * 0.6, sr.center.dy)
      ..lineTo(sr.left + sr.width * 0.9, sr.center.dy);
    final metric = ecg.computeMetrics().first;
    final drawn = live ? metric.extractPath(0, metric.length * ((t.value * 1.4) % 1.0)) : ecg;
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.012
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = live ? PpAccent.mint : c.inkMuted.withValues(alpha: 0.5),
    );

    // LED.
    final ledOn = live || (searching && (t.value * 4).floor().isEven);
    final ledAt = Offset(pod.outerRect.right - w * 0.05, pod.outerRect.top + w * 0.035);
    if (ledOn) {
      canvas.drawCircle(ledAt, w * 0.03, Paint()..color = (live ? PpAccent.mint : c.brand).withValues(alpha: 0.3));
    }
    canvas.drawCircle(ledAt, w * 0.013, Paint()..color = ledOn ? (live ? PpAccent.mint : c.brand) : c.line);

    // Signal arcs (bluetooth feel).
    if (live || searching) {
      final origin = Offset(pod.outerRect.right + w * 0.02, pod.outerRect.top);
      for (var i = 0; i < 3; i++) {
        final p = (t.value + i / 3) % 1;
        final r = w * (0.06 + 0.16 * p);
        canvas.drawArc(
          Rect.fromCircle(center: origin, radius: r),
          -math.pi * 0.45,
          math.pi * 0.4,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.014
            ..strokeCap = StrokeCap.round
            ..color = (live ? PpAccent.mint : c.brand).withValues(alpha: (1 - p) * 0.8),
        );
      }
    }

    // Sparkle highlight on the pod.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pod.left + w * 0.04, pod.top + w * 0.015, pod.width * 0.4, w * 0.012),
        Radius.circular(w * 0.01),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant _WristbandPainter old) => old.live != live || old.searching != searching || old.c != c;
}

enum SensorKind { heart, hrv, skin, temp, motion }

/// A squircle badge with a painted pictogram for each sensor.
class SensorGlyph extends StatelessWidget {
  const SensorGlyph({super.key, required this.kind, this.size = 40, this.color});

  final SensorKind kind;
  final double size;
  final Color? color;

  static Color tint(SensorKind k) => switch (k) {
        SensorKind.heart => PpAccent.coral,
        SensorKind.hrv => PpAccent.sky,
        SensorKind.skin => PpAccent.mint,
        SensorKind.temp => PpAccent.sun,
        SensorKind.motion => PpAccent.lilac,
      };

  @override
  Widget build(BuildContext context) {
    final col = color ?? tint(kind);
    final glyph = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(size * 0.36)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [col.withValues(alpha: 0.16), col.withValues(alpha: 0.08)],
          ),
        ),
        child: CustomPaint(painter: _GlyphPainter(kind, col)),
      ),
    );
    return kind == SensorKind.heart ? Pulse(amount: 0.06, child: glyph) : glyph;
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color);
  final SensorKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color;
    switch (kind) {
      case SensorKind.heart:
        final r = s * 0.2;
        final p = Path()
          ..moveTo(c.dx, c.dy + r * 1.1)
          ..cubicTo(c.dx - r * 1.8, c.dy - r * 0.1, c.dx - r * 0.8, c.dy - r * 1.6, c.dx, c.dy - r * 0.45)
          ..cubicTo(c.dx + r * 0.8, c.dy - r * 1.6, c.dx + r * 1.8, c.dy - r * 0.1, c.dx, c.dy + r * 1.1);
        canvas.drawPath(p, fill);
      case SensorKind.hrv:
        final p = Path()
          ..moveTo(s * 0.18, c.dy)
          ..lineTo(s * 0.36, c.dy)
          ..lineTo(s * 0.44, s * 0.28)
          ..lineTo(s * 0.54, s * 0.72)
          ..lineTo(s * 0.62, c.dy)
          ..lineTo(s * 0.82, c.dy);
        canvas.drawPath(p, stroke);
      case SensorKind.skin:
        // A droplet.
        final p = Path()
          ..moveTo(c.dx, s * 0.2)
          ..cubicTo(c.dx + s * 0.28, s * 0.48, c.dx + s * 0.22, s * 0.78, c.dx, s * 0.78)
          ..cubicTo(c.dx - s * 0.22, s * 0.78, c.dx - s * 0.28, s * 0.48, c.dx, s * 0.2);
        canvas.drawPath(p, fill);
        canvas.drawCircle(Offset(c.dx - s * 0.07, s * 0.58), s * 0.05, Paint()..color = Colors.white.withValues(alpha: 0.6));
      case SensorKind.temp:
        final bulb = Offset(c.dx, s * 0.66);
        canvas.drawLine(Offset(c.dx, s * 0.24), Offset(c.dx, s * 0.6), stroke..strokeWidth = s * 0.12);
        canvas.drawCircle(bulb, s * 0.12, fill);
      case SensorKind.motion:
        for (var i = 0; i < 3; i++) {
          final y = s * (0.32 + i * 0.18);
          canvas.drawLine(Offset(s * (0.2 + i * 0.06), y), Offset(s * (0.62 + i * 0.06), y), stroke..color = color.withValues(alpha: 1 - i * 0.25));
        }
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) => old.kind != kind || old.color != color;
}

/// Twinkling four-point sparkles scattered over an area.
class SparkleField extends StatefulWidget {
  const SparkleField({super.key, this.count = 6, this.seed = 3, this.colors});

  final int count;
  final int seed;
  final List<Color>? colors;

  @override
  State<SparkleField> createState() => _SparkleFieldState();
}

class _SparkleFieldState extends State<SparkleField> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PpMotion.reduced(context)) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _SparklePainter(_c, widget.count, widget.seed, widget.colors ?? [Theme.of(context).extension<PpColors>()!.brand])));
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.t, this.count, this.seed, this.colors) : super(repaint: t);
  final Animation<double> t;
  final int count, seed;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    for (var i = 0; i < count; i++) {
      final at = Offset(r.nextDouble() * size.width, r.nextDouble() * size.height);
      final phase = r.nextDouble();
      final k = (math.sin((t.value + phase) * 2 * math.pi) + 1) / 2;
      final s = (4 + r.nextDouble() * 6) * (0.4 + 0.6 * k);
      final col = colors[i % colors.length].withValues(alpha: 0.25 + 0.6 * k);
      final p = Path()
        ..moveTo(at.dx, at.dy - s)
        ..quadraticBezierTo(at.dx, at.dy, at.dx + s, at.dy)
        ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + s)
        ..quadraticBezierTo(at.dx, at.dy, at.dx - s, at.dy)
        ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - s);
      canvas.drawPath(p, Paint()..color = col);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Empty state: Pano resting in a soft grey circle, a short bold line, a calm
/// sentence and an optional action. Mirrors the Paper empty-state pattern.
class SceneCard extends StatelessWidget {
  const SceneCard({
    super.key,
    required this.title,
    required this.message,
    this.mood = PanoMood.sleepy,
    this.blobColor,
    this.action,
  });

  final String title;
  final String message;
  final PanoMood mood;

  /// Kept for call-site compatibility; Paper uses the neutral inset circle.
  final Color? blobColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              color: c.surfaceSunk,
              shape: BoxShape.circle,
              border: Border.all(color: c.highlight, width: 1.5),
            ),
            alignment: const Alignment(0, 0.35),
            child: PanoMascot(mood: mood, size: 112),
          ),
          const SizedBox(height: 26),
          Text(title, style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(message, style: text.bodyLarge, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    );
  }
}

/// Layered hills with slow parallax drift. Sits at the bottom of a header.
class CalmHills extends StatefulWidget {
  const CalmHills({super.key, this.height = 120, this.colors});

  final double height;
  final List<Color>? colors;

  @override
  State<CalmHills> createState() => _CalmHillsState();
}

class _CalmHillsState extends State<CalmHills> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PpMotion.reduced(context)) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final cols = widget.colors ??
        [
          c.brand.withValues(alpha: 0.18),
          PpAccent.lilac.withValues(alpha: 0.16),
          c.surface,
        ];
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: CustomPaint(painter: _HillsPainter(_c, cols)),
    );
  }
}

class _HillsPainter extends CustomPainter {
  _HillsPainter(this.t, this.colors) : super(repaint: t);
  final Animation<double> t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (var layer = 0; layer < colors.length; layer++) {
      final speed = (layer + 1) * 0.5;
      final phase = t.value * 2 * math.pi * speed;
      final baseY = size.height * (0.35 + layer * 0.2);
      final amp = size.height * (0.16 - layer * 0.03);
      final p = Path()..moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 6) {
        final y = baseY + math.sin(x / size.width * math.pi * (1.4 + layer * 0.5) + phase + layer) * amp;
        p.lineTo(x, y);
      }
      p
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(p, Paint()..color = colors[layer]);
    }
  }

  @override
  bool shouldRepaint(covariant _HillsPainter old) => old.colors != colors;
}
