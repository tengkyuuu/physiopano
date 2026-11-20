import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stress_monitor_app/art/pano_mascot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every reaction has a still and the two GIFs play once', () async {
    for (final mood in PanoMood.values) {
      final bytes = await rootBundle.load('assets/mascot/${mood.name}.png');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      ));
      expect(codec.frameCount, 1);
      codec.dispose();
    }
    for (final mood in [PanoMood.wave, PanoMood.celebrate]) {
      final bytes = await rootBundle.load('assets/mascot/${mood.name}.gif');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      ));
      expect(codec.frameCount, greaterThan(1));
      expect(codec.repetitionCount, 0);
      codec.dispose();
    }
  });

  testWidgets('motion preference switches the greeting to its still',
      (tester) async {
    Future<void> show(bool reduced) => tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: PanoMascot(mood: PanoMood.wave),
            ),
          ),
        );
    String asset() =>
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName;

    await show(false);
    expect(asset(), 'assets/mascot/wave.gif');
    await show(true);
    expect(asset(), 'assets/mascot/wave.png');
    await show(false);
    expect(asset(), 'assets/mascot/wave.gif');
  });

  testWidgets(
      'the breathing pose follows the pacer and respects reduced motion',
      (tester) async {
    final breath = ValueNotifier(0.0);
    addTearDown(breath.dispose);
    Future<void> show(bool reduced) => tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: PanoMascot(mood: PanoMood.breathe, breath: breath),
            ),
          ),
        );

    final scale = find.descendant(
      of: find.byType(PanoMascot),
      matching: find.byType(Transform),
    );
    await show(false);
    expect(tester.widget<Transform>(scale).transform.entry(0, 0), 0.91);
    breath.value = 1;
    await tester.pump();
    expect(tester.widget<Transform>(scale).transform.entry(0, 0), 1.0);
    await show(true);
    expect(scale, findsNothing);
  });
}
