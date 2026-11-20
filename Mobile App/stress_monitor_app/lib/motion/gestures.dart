// GESTURES: follow a finger.
//
// TiltCard leans toward the finger in 3D while it is held and springs flat
// when released. DragToDismiss lets a card be flicked away with velocity.

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/physiopano_tokens.dart';

class TiltCard extends StatefulWidget {
  const TiltCard({super.key, required this.child, this.maxTilt = 0.12, this.glare = true});

  final Widget child;
  final double maxTilt; // radians
  final bool glare;

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> with TickerProviderStateMixin {
  late final AnimationController _x = AnimationController.unbounded(vsync: this);
  late final AnimationController _y = AnimationController.unbounded(vsync: this);
  Offset _glare = const Offset(0.5, 0.5);

  void _track(Offset local, Size size) {
    if (PpMotion.reduced(context)) return;
    final nx = (local.dx / size.width).clamp(0.0, 1.0);
    final ny = (local.dy / size.height).clamp(0.0, 1.0);
    _x.value = (nx - 0.5) * 2 * widget.maxTilt;
    _y.value = (ny - 0.5) * 2 * widget.maxTilt;
    setState(() => _glare = Offset(nx, ny));
  }

  void _release() {
    _x.animateWith(SpringSimulation(PpMotion.soft, _x.value, 0, 0));
    _y.animateWith(SpringSimulation(PpMotion.soft, _y.value, 0, 0));
  }

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight.isFinite ? box.maxHeight : 200);
      return Listener(
        onPointerDown: (e) => _track(e.localPosition, context.size ?? size),
        onPointerMove: (e) => _track(e.localPosition, context.size ?? size),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedBuilder(
          animation: Listenable.merge([_x, _y]),
          child: widget.child,
          builder: (context, child) {
            final active = _x.value.abs() + _y.value.abs();
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(_x.value)
                ..rotateX(-_y.value),
              child: Stack(
                children: [
                  child!,
                  if (widget.glare && active > 0.001)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(PpRadius.panel),
                            gradient: RadialGradient(
                              center: Alignment(_glare.dx * 2 - 1, _glare.dy * 2 - 1),
                              radius: 0.9,
                              colors: [
                                Colors.white.withValues(alpha: (active / widget.maxTilt) * 0.08),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    });
  }
}

/// Horizontal drag with rubber-banding; flick past the threshold to dismiss.
class FlickToDismiss extends StatefulWidget {
  const FlickToDismiss({super.key, required this.child, required this.onDismissed});

  final Widget child;
  final VoidCallback onDismissed;

  @override
  State<FlickToDismiss> createState() => _FlickToDismissState();
}

class _FlickToDismissState extends State<FlickToDismiss> with SingleTickerProviderStateMixin {
  late final AnimationController _dx = AnimationController.unbounded(vsync: this);

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      onHorizontalDragUpdate: (d) => _dx.value += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_dx.value.abs() > width * 0.35 || v.abs() > 900) {
          final target = (_dx.value + v * 0.2).sign * width * 1.3;
          _dx.animateWith(SpringSimulation(PpMotion.snappy, _dx.value, target, v)).whenComplete(widget.onDismissed);
        } else {
          _dx.animateWith(SpringSimulation(PpMotion.soft, _dx.value, 0, v));
        }
      },
      child: AnimatedBuilder(
        animation: _dx,
        child: widget.child,
        builder: (_, child) => Transform.translate(
          offset: Offset(_dx.value, 0),
          child: Transform.rotate(
            angle: _dx.value / width * 0.18,
            child: Opacity(opacity: (1 - (_dx.value.abs() / width)).clamp(0.0, 1.0), child: child),
          ),
        ),
      ),
    );
  }
}
