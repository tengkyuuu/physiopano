import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/physiopano_tokens.dart';

/// A dashboard tile showing a single sensor reading.
///
/// The icon is mapped onto a painted [SensorGlyph]; the tile leans toward the
/// finger (TiltCard) and the value rolls vertically when it changes.
class SensorCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? unit;
  final String? subtitle;
  final Color color;
  final bool alert;

  const SensorCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.subtitle,
    this.color = PpAccent.sky,
    this.alert = false,
  });

  SensorKind get _kind {
    if (icon == Icons.favorite) return SensorKind.heart;
    if (icon == Icons.timeline) return SensorKind.hrv;
    if (icon == Icons.water_drop) return SensorKind.skin;
    if (icon == Icons.thermostat) return SensorKind.temp;
    return SensorKind.motion;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final kind = _kind;
    final tint = alert ? c.crisis : SensorGlyph.tint(kind);
    final text = Theme.of(context).textTheme;

    return TiltCard(
      maxTilt: 0.08,
      child: AnimatedContainer(
        duration: PpMotion.slow,
        curve: PpMotion.ease,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PpRadius.panel),
          border: alert ? Border.all(color: c.crisis.withValues(alpha: 0.6), width: 1.5) : PpShadow.edge(c),
          boxShadow: PpShadow.raised(c, lift: 0.8),
        ),
        child: Stack(
          children: [
            // Soft tinted glow in the corner: each sensor gets its own hue.
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [tint.withValues(alpha: 0.10), tint.withValues(alpha: 0)]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SensorGlyph(kind: kind, size: 30, color: alert ? c.crisis : null),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: text.labelMedium?.copyWith(color: c.inkMuted, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: ClipRect(
                          child: AnimatedSwitcher(
                            duration: PpMotion.base,
                            switchInCurve: PpMotion.ease,
                            transitionBuilder: (child, a) => SlideTransition(
                              position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(a),
                              child: FadeTransition(opacity: a, child: child),
                            ),
                            child: Text(
                              value,
                              key: ValueKey<String>(value),
                              style: PpTheme.data(context, size: 26).copyWith(
                                color: alert ? c.crisis : c.ink,
                                height: 1.05,
                                letterSpacing: -0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      if (unit != null) ...[
                        const SizedBox(width: 4),
                        Text(unit!, style: text.labelMedium?.copyWith(color: tint)),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: text.labelSmall?.copyWith(
                        letterSpacing: 0.1,
                        fontWeight: FontWeight.w400,
                        color: alert ? c.crisis : c.inkMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
