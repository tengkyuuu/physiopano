// SHADERS: transform the pixels.
//
// AuroraBackground (kept name for existing call sites) now renders a paper
// surface on the GPU: fine fibre grain and a slow, faint wash of light
// (shaders/aurora.frag). On paper the wash is nearly invisible (intensity
// ~0.05); inside the ink feature card it reads as soft light moving across
// glass (intensity ~0.35). If the shader cannot load, a flat fill is painted.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/physiopano_tokens.dart';

class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.calm = 1, this.child, this.base, this.intensity = 0.05});

  /// 0..1; lower values warm the wash slightly (elevated arousal).
  final double calm;
  final Widget? child;

  /// Surface colour; defaults to the theme ground (paper).
  final Color? base;

  /// Strength of the drifting light wash.
  final double intensity;

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;

  static Future<ui.FragmentProgram?> _load() => _loading ??= ui.FragmentProgram.fromAsset('shaders/aurora.frag')
      .then<ui.FragmentProgram?>((p) => _program = p)
      .catchError((Object _) => null);

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  // Cost control: the full-screen paper surface is drawn once and stays
  // static (the grain reads as material; a near-invisible moving wash is not
  // worth repainting every pixel at 60 fps, which also overwhelms software
  // GPUs such as the Android emulator's SwiftShader). Only stronger washes
  // (the small ink card) animate, throttled to ~15 fps.
  static const _frameGap = Duration(milliseconds: 66);
  Duration _lastFrame = Duration.zero;
  late final Ticker _ticker = createTicker((e) {
    if (e - _lastFrame < _frameGap) return;
    _lastFrame = e;
    _time.value = 8 + e.inMicroseconds / 1e6;
  });
  final _time = ValueNotifier<double>(8);
  ui.FragmentShader? _shader;

  bool get _animated => widget.intensity >= 0.15;

  @override
  void initState() {
    super.initState();
    if (AuroraBackground._program != null) {
      _shader = AuroraBackground._program!.fragmentShader();
    } else {
      AuroraBackground._load().then((p) {
        if (mounted && p != null) setState(() => _shader = p.fragmentShader());
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PpMotion.reduced(context) || !_animated) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final base = widget.base ?? c.ground;
    final painter = _shader != null
        ? _PaperPainter(_shader!, _time, widget.calm, widget.intensity, base, c)
        : _FlatPainter(base);
    return RepaintBoundary(
      child: CustomPaint(painter: painter, child: widget.child ?? const SizedBox.expand()),
    );
  }
}

class _PaperPainter extends CustomPainter {
  _PaperPainter(this.shader, this.time, this.calm, this.intensity, this.base, this.c) : super(repaint: time);
  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final double calm, intensity;
  final Color base;
  final PpColors c;

  void _color(int i, Color col) {
    shader
      ..setFloat(i, col.r)
      ..setFloat(i + 1, col.g)
      ..setFloat(i + 2, col.b)
      ..setFloat(i + 3, 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, intensity)
      ..setFloat(4, calm.clamp(0, 1));
    _color(5, base);
    _color(9, Color.lerp(c.brand, Colors.white, base.computeLuminance() > 0.5 ? 0.2 : 0.0)!);
    _color(13, PpAccent.sun);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _PaperPainter old) =>
      old.calm != calm || old.intensity != intensity || old.base != base || old.c != c;
}

class _FlatPainter extends CustomPainter {
  _FlatPainter(this.base);
  final Color base;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(Offset.zero & size, Paint()..color = base);

  @override
  bool shouldRepaint(covariant _FlatPainter old) => old.base != base;
}
