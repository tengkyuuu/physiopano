// LAYOUT TRANSITIONS: reorder, expand, connect.
//
// FadeThroughSwitcher swaps content with a shared-axis fade-through (old
// shrinks out, new grows in), keyed by value. ExpandReveal animates a section
// opening with size + fade so content below re-flows smoothly (FLIP-style).
// FlipbookPlayer plays a list of finished frames at a fixed fps (Flipbook).

import 'package:flutter/material.dart';

import '../theme/physiopano_tokens.dart';

class FadeThroughSwitcher extends StatelessWidget {
  const FadeThroughSwitcher({super.key, required this.child, this.duration = PpMotion.slow, this.axis = Axis.vertical});

  final Widget child;
  final Duration duration;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: PpMotion.reduced(context) ? Duration.zero : duration,
      switchInCurve: PpMotion.ease,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, anim) {
        final slide = Tween<Offset>(
          begin: axis == Axis.vertical ? const Offset(0, 0.04) : const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(anim), child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class ExpandReveal extends StatelessWidget {
  const ExpandReveal({super.key, required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: PpMotion.slow,
      curve: PpMotion.ease,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: PpMotion.base,
        child: expanded ? child : const SizedBox(width: double.infinity),
      ),
    );
  }
}

class FlipbookPlayer extends StatefulWidget {
  const FlipbookPlayer({super.key, required this.frames, this.fps = 8, this.loop = true});

  final List<Widget> frames;
  final double fps;
  final bool loop;

  @override
  State<FlipbookPlayer> createState() => _FlipbookPlayerState();
}

class _FlipbookPlayerState extends State<FlipbookPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (widget.frames.length / widget.fps * 1000).round()),
  );

  @override
  void initState() {
    super.initState();
    widget.loop ? _c.repeat() : _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final i = (_c.value * widget.frames.length).floor().clamp(0, widget.frames.length - 1);
          return widget.frames[i];
        },
      );
}
