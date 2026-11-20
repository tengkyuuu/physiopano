// PARTICLES + PHYSICS: celebrate with many pieces; let forces drive motion.
//
// ConfettiBurst fires shaped pieces (dots, squiggles, stars, squares) from an
// origin with randomised velocity; gravity, drag and spin integrate per frame.
// Use it only for genuine accomplishments: finishing a check-in, finishing a
// breathing session, completing calibration.
//
// FloatingMotes are slow ambient particles under gentle brownian drift that
// get pushed away from a touch point (repulsion force).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/physiopano_tokens.dart';

class ConfettiController extends ChangeNotifier {
  int _shots = 0;
  Offset? _origin;

  /// Fire a burst. [origin] is in fractional coordinates of the overlay (0..1).
  void fire({Offset origin = const Offset(0.5, 0.35)}) {
    _origin = origin;
    _shots++;
    notifyListeners();
  }
}

enum _Shape { dot, square, squiggle, star }

class _Piece {
  _Piece(this.pos, this.vel, this.color, this.shape, this.size, this.spin);
  Offset pos, vel;
  final Color color;
  final _Shape shape;
  final double size;
  double angle = 0;
  final double spin;
  double life = 1;
}

class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key, required this.controller, required this.child, this.count = 70});

  final ConfettiController controller;
  final Widget child;
  final int count;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay> with SingleTickerProviderStateMixin {
  final _pieces = <_Piece>[];
  final _rand = math.Random();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  int _seen = 0;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFire);
  }

  void _onFire() {
    if (widget.controller._shots == _seen) return;
    _seen = widget.controller._shots;
    if (PpMotion.reduced(context) || _size == Size.zero) return;
    final o = widget.controller._origin ?? const Offset(0.5, 0.35);
    final origin = Offset(o.dx * _size.width, o.dy * _size.height);
    for (var i = 0; i < widget.count; i++) {
      final a = -math.pi / 2 + (_rand.nextDouble() - 0.5) * math.pi * 1.1;
      final speed = 380 + _rand.nextDouble() * 520;
      _pieces.add(_Piece(
        origin,
        Offset(math.cos(a), math.sin(a)) * speed,
        PpAccent.all[_rand.nextInt(PpAccent.all.length)],
        _Shape.values[_rand.nextInt(_Shape.values.length)],
        6 + _rand.nextDouble() * 8,
        (_rand.nextDouble() - 0.5) * 12,
      ));
    }
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero ? 1 / 60 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    const gravity = Offset(0, 900);
    for (final p in _pieces) {
      p.vel = (p.vel + gravity * dt) * math.pow(0.12, dt).toDouble(); // gravity + air drag
      p.pos += p.vel * dt;
      p.angle += p.spin * dt;
      p.life -= dt * 0.45;
    }
    _pieces.removeWhere((p) => p.life <= 0 || p.pos.dy > _size.height + 40);
    if (_pieces.isEmpty) _ticker.stop();
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFire);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _size = box.biggest;
      return Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _ConfettiPainter(_pieces))),
          ),
        ],
      );
    });
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces);
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final paint = Paint()..color = p.color.withValues(alpha: p.life.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(p.pos.dx, p.pos.dy);
      canvas.rotate(p.angle);
      switch (p.shape) {
        case _Shape.dot:
          canvas.drawCircle(Offset.zero, p.size / 2, paint);
        case _Shape.square:
          canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size), const Radius.circular(2)),
              paint);
        case _Shape.squiggle:
          final s = p.size;
          final path = Path()
            ..moveTo(-s, 0)
            ..quadraticBezierTo(-s / 2, -s / 1.5, 0, 0)
            ..quadraticBezierTo(s / 2, s / 1.5, s, 0);
          canvas.drawPath(
              path,
              paint
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.6
                ..strokeCap = StrokeCap.round);
        case _Shape.star:
          canvas.drawPath(starPath(p.size * 0.75), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Five-point rounded-ish star centred on the origin.
Path starPath(double r) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final rad = i.isEven ? r : r * 0.48;
    final a = -math.pi / 2 + i * math.pi / 5;
    final pt = Offset(math.cos(a) * rad, math.sin(a) * rad);
    i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
  }
  return path..close();
}

/// Slow ambient motes that drift and part around a finger.
class FloatingMotes extends StatefulWidget {
  const FloatingMotes({super.key, this.count = 22, this.color});

  final int count;
  final Color? color;

  @override
  State<FloatingMotes> createState() => _FloatingMotesState();
}

class _Mote {
  _Mote(this.pos, this.vel, this.r, this.hue);
  Offset pos, vel;
  final double r;
  final Color hue;
}

class _FloatingMotesState extends State<FloatingMotes> with SingleTickerProviderStateMixin {
  final _rand = math.Random(7);
  final _motes = <_Mote>[];
  Offset? _touch;
  Size _size = Size.zero;
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  void _seed(Size s) {
    _motes.clear();
    for (var i = 0; i < widget.count; i++) {
      _motes.add(_Mote(
        Offset(_rand.nextDouble() * s.width, _rand.nextDouble() * s.height),
        Offset(_rand.nextDouble() - 0.5, _rand.nextDouble() - 0.5) * 14,
        1.2 + _rand.nextDouble() * 2.6,
        widget.color ?? PpAccent.all[i % PpAccent.all.length],
      ));
    }
  }

  void _tick(Duration e) {
    final dt = _last == Duration.zero ? 1 / 60 : ((e - _last).inMicroseconds / 1e6).clamp(0, 0.05).toDouble();
    _last = e;
    for (final m in _motes) {
      var f = Offset(_rand.nextDouble() - 0.5, _rand.nextDouble() - 0.5) * 30; // brownian
      if (_touch != null) {
        final d = m.pos - _touch!;
        final dist = d.distance.clamp(8.0, 400.0);
        if (dist < 140) f += d / dist * (22000 / (dist * dist)) * 60; // inverse-square repulsion
      }
      m.vel = (m.vel + f * dt) * math.pow(0.6, dt).toDouble();
      m.pos += m.vel * dt;
      // wrap
      m.pos = Offset((m.pos.dx + _size.width) % _size.width, (m.pos.dy + _size.height) % _size.height);
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PpMotion.reduced(context)) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final s = box.biggest;
      if (s != _size && s.isFinite) {
        _size = s;
        _seed(s);
      }
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _touch = e.localPosition,
        onPointerMove: (e) => _touch = e.localPosition,
        onPointerUp: (_) => _touch = null,
        onPointerCancel: (_) => _touch = null,
        child: CustomPaint(size: s, painter: _MotePainter(_motes)),
      );
    });
  }
}

class _MotePainter extends CustomPainter {
  _MotePainter(this.motes);
  final List<_Mote> motes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in motes) {
      canvas.drawCircle(m.pos, m.r * 3, Paint()..color = m.hue.withValues(alpha: 0.06));
      canvas.drawCircle(m.pos, m.r, Paint()..color = m.hue.withValues(alpha: 0.55));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
