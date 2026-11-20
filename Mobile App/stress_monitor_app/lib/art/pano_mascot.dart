import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/physiopano_tokens.dart';

enum PanoMood { calm, happy, celebrate, wave, breathe, alert, sleepy, thinking }

enum PanoProp { heart, leaf, band }

/// Paño shares the same eight illustrated reactions across the companion app.
class PanoMascot extends StatelessWidget {
  const PanoMascot({
    super.key,
    this.mood = PanoMood.calm,
    this.size = 120,
    this.breath,
    this.prop,
  });

  final PanoMood mood;
  final double size;
  final ValueListenable<double>? breath;
  final PanoProp? prop;

  @override
  Widget build(BuildContext context) {
    final reduced = PpMotion.reduced(context);
    final playsOnce = mood == PanoMood.wave || mood == PanoMood.celebrate;
    final extension = playsOnce && !reduced ? 'gif' : 'png';
    final asset = 'assets/mascot/${mood.name}.$extension';
    Widget art =
        Image.asset(asset, fit: BoxFit.contain, excludeFromSemantics: true);
    if (prop case final held?) {
      final (icon, color) = switch (held) {
        PanoProp.heart => (Icons.favorite_rounded, const Color(0xFFE56F91)),
        PanoProp.leaf => (Icons.eco_rounded, const Color(0xFF24806F)),
        PanoProp.band => (Icons.watch_rounded, const Color(0xFF214B72)),
      };
      art = Stack(fit: StackFit.expand, children: [
        art,
        Align(
          alignment: const Alignment(0.66, 0.50),
          child: Icon(icon, color: color, size: size * 0.19),
        ),
      ]);
    }
    if (!reduced && mood == PanoMood.breathe && breath != null) {
      art = ValueListenableBuilder<double>(
        valueListenable: breath!,
        child: art,
        builder: (context, phase, child) => Transform.scale(
          scale: 0.91 + 0.09 * phase.clamp(0.0, 1.0),
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      );
    }
    final expression = switch (mood) {
      PanoMood.wave => 'waving',
      PanoMood.celebrate => 'celebrating',
      PanoMood.breathe => 'breathing calmly',
      PanoMood.alert => 'paying attention',
      _ => mood.name,
    };
    return Semantics(
      image: true,
      label: 'Paño, $expression',
      child: SizedBox(width: size, height: size * 1.05, child: art),
    );
  }
}
