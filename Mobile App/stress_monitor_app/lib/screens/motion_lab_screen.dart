import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/physiopano_tokens.dart';

/// A living catalogue of the PHYSIOPAÑO motion kit and clipart. Every tile is
/// the real widget the app uses, so this doubles as a visual regression page.
///
/// Reach it from About, or launch straight into it with
///   flutter run --dart-define=MOTION_LAB=true
class MotionLabScreen extends StatefulWidget {
  const MotionLabScreen({super.key});

  @override
  State<MotionLabScreen> createState() => _MotionLabScreenState();
}

class _MotionLabScreenState extends State<MotionLabScreen> {
  final _confetti = ConfettiController();
  int _mood = 0;
  int _flicks = 0;
  bool _expanded = false;

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final t = Theme.of(context).textTheme;
    final mood = PanoMood.values[_mood % PanoMood.values.length];

    Widget tile(String title, String caption, Widget child, {double height = 200}) => Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PpRadius.panel),
            border: Border.all(color: c.line.withValues(alpha: 0.7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: height, child: Center(child: child)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium),
                    const SizedBox(height: 2),
                    Text(caption, style: t.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        );

    final tiles = <Widget>[
      tile(
        'Paño, ${mood.name}',
        'Tap Paño to see the next reaction.',
        GestureDetector(
          onTap: () => setState(() => _mood++),
          child: PanoMascot(mood: mood, size: 140, prop: mood == PanoMood.calm ? PanoProp.heart : null),
        ),
        height: 220,
      ),
      tile(
        'Particles',
        'Physics confetti. Reserved for real accomplishments.',
        FilledButton(
          onPressed: () => _confetti.fire(origin: const Offset(0.5, 0.5)),
          child: const Text('Celebrate'),
        ),
      ),
      tile('Shader', 'GPU aurora with film grain (aurora.frag).',
          const ClipRRect(borderRadius: BorderRadius.all(Radius.circular(18)), child: SizedBox(width: 260, height: 150, child: AuroraBackground()))),
      tile('SVG path', 'Heartbeat trace with a head that follows the line.',
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: HeartbeatTrace(color: PpAccent.coral, height: 70, bpm: 78))),
      tile('Morph', 'Organic blob morphing through Catmull-Rom points.',
          MorphBlob(size: 160, colors: [c.brand, PpAccent.lilac, PpAccent.mint])),
      tile('Gesture', 'Drag across the card: it tilts toward your finger.',
          TiltCard(
            child: Container(
              width: 220,
              height: 130,
              decoration: BoxDecoration(
                gradient: AppGradients.brand(c),
                borderRadius: BorderRadius.circular(PpRadius.panel),
              ),
              alignment: Alignment.center,
              child: Text('Tilt me', style: t.titleLarge?.copyWith(color: c.onBrand)),
            ),
          )),
      tile(
        'Flick',
        'Throw the card sideways to dismiss it ($_flicks so far).',
        FlickToDismiss(
          key: ValueKey(_flicks),
          onDismissed: () => setState(() => _flicks++),
          child: Container(
            width: 200,
            height: 110,
            decoration: BoxDecoration(color: PpAccent.sun, borderRadius: BorderRadius.circular(PpRadius.panel)),
            alignment: Alignment.center,
            child: Text('Flick me', style: t.titleLarge?.copyWith(color: const Color(0xFF0D1017))),
          ),
        ),
      ),
      tile('Clipart', 'Wristband with live LED, ECG and signal arcs.', const WristbandArt(size: 200, live: true)),
      tile(
        'Glyphs',
        'Painted sensor pictograms. The heart keyframes a double beat.',
        const Wrap(spacing: 12, children: [
          SensorGlyph(kind: SensorKind.heart, size: 52),
          SensorGlyph(kind: SensorKind.hrv, size: 52),
          SensorGlyph(kind: SensorKind.skin, size: 52),
          SensorGlyph(kind: SensorKind.temp, size: 52),
          SensorGlyph(kind: SensorKind.motion, size: 52),
        ]),
      ),
      tile('Keyframes', 'Ripples radiating from a live centre.', Ripples(color: c.brand, size: 170, child: Icon(Icons.sensors_rounded, color: c.brand))),
      tile(
        'Layout',
        'Expand and collapse with size + fade. Tap the button.',
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(onPressed: () => setState(() => _expanded = !_expanded), child: Text(_expanded ? 'Collapse' : 'Expand')),
            ExpandReveal(
              expanded: _expanded,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Content reflows smoothly.', style: t.bodyMedium),
              ),
            ),
          ],
        ),
      ),
      tile('Flipbook', 'Stepped frames played at 6 fps.',
          FlipbookPlayer(fps: 6, frames: [
            for (final m in [PanoMood.calm, PanoMood.happy, PanoMood.celebrate, PanoMood.happy])
              PanoMascot(key: ValueKey(m), mood: m, size: 110),
          ])),
      tile('Hills', 'Layered parallax hills for headers.', const Align(alignment: Alignment.bottomCenter, child: CalmHills(height: 150))),
      tile('Scene', 'Empty-state composition.',
          const FittedBox(child: SceneCard(title: 'All quiet', message: 'Nothing new right now.', mood: PanoMood.sleepy)),
          height: 300),
    ];

    return Scaffold(
      body: ConfettiOverlay(
        controller: _confetti,
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(title: const Text('Motion lab'), backgroundColor: c.ground),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              sliver: SliverList.separated(
                itemCount: tiles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) => Reveal(index: i.clamp(0, 6), child: tiles[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppGradients {
  static LinearGradient brand(PpColors c) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c.brand, PpAccent.lilac],
      );
}
