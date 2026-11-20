import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/baseline_engine.dart';
import '../services/change_detector.dart';
import '../theme/physiopano_tokens.dart';

class BaselineLane extends StatelessWidget {
  const BaselineLane({super.key});

  @override
  Widget build(BuildContext context) {
    final detector = context.watch<ChangeDetector>();
    final assessment = detector.assessment;
    final colors = Theme.of(context).extension<PpColors>()!;
    final type = Theme.of(context).textTheme;
    final now = DateTime.now();
    final history = {
      for (final day in assessment?.days ?? const <DayAssessment>[])
        DateTime(day.date.year, day.date.month, day.date.day):
            day.z[PpSignal.restingHr],
    };
    final values = List.generate(
      14,
      (i) => history[DateTime(now.year, now.month, now.day - (13 - i))],
    );
    final latest = values.lastIndexWhere((value) => value != null);
    final usual = detector.engine.baselineFor(
      PpSignal.restingHr,
      bandOf(now),
      before: now,
    );
    final usualBpm = usual?.median.round();
    final value = latest < 0 ? null : values[latest];
    final String summary;
    if (value == null) {
      summary = assessment?.status == ChangeStatus.learning
          ? assessment!.summary
          : 'Your lane appears when there are enough still readings to compare.';
    } else if (value.abs() <= 1) {
      summary = 'Your latest daily reading was within your usual band.';
    } else {
      final direction = value > 0 ? 'above' : 'below';
      summary = 'Your latest daily reading was $direction your usual band.';
    }

    return Container(
      padding: const EdgeInsets.all(PpSpace.s4),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(PpRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resting heart rate', style: type.titleLarge),
          const SizedBox(height: PpSpace.s2),
          Text(summary, style: type.titleMedium),
          if (detector.isSynthetic)
            Text('Synthetic demo history', style: type.bodySmall),
          if (latest >= 0) ...[
            const SizedBox(height: PpSpace.s4),
            Semantics(
              image: true,
              label: 'Fourteen days of resting heart rate compared with your '
                  'own usual. Larger dots show readings farther from your '
                  'usual. Short ticks show days without a comparison.',
              child: _LanePlot(values: values, latest: latest, colors: colors),
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('13 days ago'), Text('Today')],
            ),
            const SizedBox(height: PpSpace.s2),
            Text(
              'Shaded band: your usual ±1σ. Teal marker: latest comparison.',
              style: type.bodySmall?.copyWith(color: colors.inkMuted),
            ),
          ],
          if (usualBpm != null) ...[
            const SizedBox(height: PpSpace.s2),
            Text(
                'Your usual at this time of day is about $usualBpm beats per minute.',
                style: type.bodySmall),
          ],
          const SizedBox(height: PpSpace.s2),
          Text('A change can be a cue to check in with yourself.',
              style: type.bodySmall?.copyWith(color: colors.inkMuted)),
        ],
      ),
    );
  }
}

class _LanePlot extends StatelessWidget {
  const _LanePlot({
    required this.values,
    required this.latest,
    required this.colors,
  });
  final List<double?> values;
  final int latest;
  final PpColors colors;

  @override
  Widget build(BuildContext context) {
    final extent = values.whereType<double>().fold<double>(
        2.5, (greatest, value) => math.max(greatest, value.abs()));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: 144,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final target = _LanePainter.position(
            Size(constraints.maxWidth, 144),
            latest,
            values[latest]!,
            extent,
          );
          const markerSize = 18.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _LanePainter(values, extent, colors)),
              AnimatedPositioned(
                duration: reduceMotion ? Duration.zero : PpMotion.base,
                curve: PpMotion.ease,
                left: target.dx - markerSize / 2,
                top: target.dy - markerSize / 2,
                width: markerSize,
                height: markerSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.brand,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LanePainter extends CustomPainter {
  _LanePainter(this.values, this.extent, this.colors);
  final List<double?> values;
  final double extent;
  final PpColors colors;

  static Offset position(Size size, int day, double z, double extent) {
    const pad = 12.0;
    final width = math.max(0.0, size.width - 2 * pad);
    return Offset(
      pad + width * day / 13,
      size.height / 2 - z / extent * (size.height / 2 - pad),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(int day, double z) => position(size, day, z, extent);
    canvas.drawRect(
      Rect.fromPoints(at(0, 1), at(13, -1)),
      Paint()..color = colors.brand.withValues(alpha: 0.14),
    );
    final center = at(0, 0).dy;
    final dash = Paint()
      ..color = colors.brand
      ..strokeWidth = 2;
    for (var x = at(0, 0).dx; x < at(13, 0).dx; x += 6) {
      canvas.drawLine(
        Offset(x, center),
        Offset(math.min(x + 2, at(13, 0).dx), center),
        dash,
      );
    }
    final series = Paint()
      ..color = colors.ink
      ..strokeWidth = 3;
    final missing = Paint()
      ..color = colors.inkMuted
      ..strokeWidth = 2;
    Offset? previous;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        final x = at(i, 0).dx;
        canvas.drawLine(
            Offset(x, size.height - 8), Offset(x, size.height - 3), missing);
        previous = null;
        continue;
      }
      final point = at(i, value);
      if (previous != null) canvas.drawLine(previous, point, series);
      final radius = switch (levelFor(value.abs())) {
        DeviationLevel.within => 4.0,
        DeviationLevel.notable => 7.0,
        DeviationLevel.marked => 10.0,
      };
      canvas.drawCircle(point, radius, series);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(_LanePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}
