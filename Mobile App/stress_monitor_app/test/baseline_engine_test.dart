import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:stress_monitor_app/services/baseline_engine.dart';

/// Adds [n] still minutes in the morning band of [date].
void addDay(BaselineEngine e, DateTime date,
    {double hr = 66, double rmssd = 42, double eda = 2.2, double temp = 33.6, int n = 10, int seed = 0}) {
  final rnd = math.Random(seed);
  double j(double sd) => (rnd.nextDouble() * 2 - 1) * sd;
  for (var m = 0; m < n; m++) {
    e.addMinute(DateTime(date.year, date.month, date.day, 8, m), {
      PpSignal.restingHr: hr + j(1.5),
      PpSignal.rmssd: rmssd + j(3),
      PpSignal.edaTonic: eda + j(0.1),
      PpSignal.skinTemp: temp + j(0.15),
    });
  }
}

void main() {
  final start = DateTime(2026, 11, 1);
  DateTime day(int i) => start.add(Duration(days: i));

  test('bands follow the clock', () {
    expect(bandOf(DateTime(2026, 1, 1, 6)), DayBand.morning);
    expect(bandOf(DateTime(2026, 1, 1, 12)), DayBand.day);
    expect(bandOf(DateTime(2026, 1, 1, 20)), DayBand.evening);
    expect(bandOf(DateTime(2026, 1, 1, 2)), DayBand.night);
  });

  test('learning until minDays of data, nothing flagged', () {
    final e = BaselineEngine();
    for (var i = 0; i < 6; i++) {
      addDay(e, day(i), seed: i);
    }
    e.catchUp(day(6));
    final a = e.assess(now: day(6));
    expect(a.status, ChangeStatus.learning);
    expect(a.daysOfData, 6);
    expect(a.summary, contains('day 7 of 7'));
  });

  test('steady days stay steady', () {
    final e = BaselineEngine();
    for (var i = 0; i < 14; i++) {
      addDay(e, day(i), seed: i);
    }
    e.catchUp(day(14));
    final a = e.assess(now: day(14));
    expect(a.status, ChangeStatus.steady);
    expect(a.days.where((d) => d.shifted), isEmpty);
  });

  test('one bad day never flags a change', () {
    final e = BaselineEngine();
    for (var i = 0; i < 12; i++) {
      addDay(e, day(i), seed: i);
    }
    addDay(e, day(12), rmssd: 22, eda: 3.4, hr: 76, seed: 99);
    addDay(e, day(13), seed: 13);
    e.catchUp(day(14));
    expect(e.assess(now: day(14)).status, isNot(ChangeStatus.changing));
  });

  test('a sustained multi-signal shift flags a change after the run rule', () {
    final e = BaselineEngine();
    for (var i = 0; i < 12; i++) {
      addDay(e, day(i), seed: i);
    }
    // Two shifted days: not yet.
    addDay(e, day(12), rmssd: 24, eda: 3.3, seed: 50);
    addDay(e, day(13), rmssd: 23, eda: 3.4, seed: 51);
    e.catchUp(day(14));
    expect(e.assess(now: day(14)).status, ChangeStatus.steady);

    // Third shifted day: change.
    addDay(e, day(14), rmssd: 22, eda: 3.5, seed: 52);
    e.catchUp(day(15));
    final a = e.assess(now: day(15));
    expect(a.status, ChangeStatus.changing);
    expect(a.changingSince, day(12));
    expect(a.shiftedSignals.keys, containsAll([PpSignal.rmssd, PpSignal.edaTonic]));
    expect(a.shiftedSignals[PpSignal.rmssd]!, lessThan(0));
    expect(a.summary, contains('heart-rate variability lower'));
    expect(a.summary, contains('not a diagnosis'));
  });

  test('a single drifting signal is not enough', () {
    final e = BaselineEngine();
    for (var i = 0; i < 12; i++) {
      addDay(e, day(i), seed: i);
    }
    for (var i = 12; i < 16; i++) {
      addDay(e, day(i), rmssd: 22, seed: i);
    }
    e.catchUp(day(16));
    expect(e.assess(now: day(16)).status, ChangeStatus.steady);
  });

  test('moving samples are ignored', () {
    final e = BaselineEngine();
    final t = DateTime(2026, 11, 1, 8, 0, 0);
    for (var s = 0; s < 120; s++) {
      e.addSample(t.add(Duration(seconds: s)), hr: 120, accelMag: 1.6);
    }
    e.addSample(t.add(const Duration(minutes: 5)), hr: 60, accelMag: 1.0);
    expect(e.toJson()['today'], isEmpty);
  });

  test('still samples become minute medians', () {
    final e = BaselineEngine();
    final t = DateTime(2026, 11, 1, 8, 0, 0);
    for (var s = 0; s < 61; s++) {
      e.addSample(t.add(Duration(seconds: s)), hr: 60 + (s % 3).toDouble(), accelMag: 1.0);
    }
    final today = e.toJson()['today'] as Map;
    expect((today['morning'] as Map)['hr'], [61.0]);
  });

  test('live deviation uses the band baseline and the size ramp', () {
    final e = BaselineEngine();
    for (var i = 0; i < 10; i++) {
      addDay(e, day(i), seed: i);
    }
    final t = DateTime(day(10).year, day(10).month, day(10).day, 9);
    expect(e.live(t, rmssd: 42).level, DeviationLevel.within);
    expect(e.live(t, rmssd: 20).level, DeviationLevel.marked);
    // No baseline for the night band yet.
    expect(e.live(DateTime(t.year, t.month, t.day, 2), rmssd: 20).hasBaseline, isFalse);
  });

  test('round-trips through JSON', () {
    final e = BaselineEngine();
    for (var i = 0; i < 9; i++) {
      addDay(e, day(i), seed: i);
    }
    addDay(e, day(9), seed: 9); // left as "today"
    final copy = BaselineEngine.fromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
    expect(copy.daysOfData, e.daysOfData);
    expect(copy.baselineFor(PpSignal.rmssd, DayBand.morning)!.median,
        closeTo(e.baselineFor(PpSignal.rmssd, DayBand.morning)!.median, 1e-9));
    expect(jsonEncode(copy.toJson()), jsonEncode(e.toJson()));
  });

  test('synthetic demo history is labelled and shows the change flow', () {
    final e = BaselineEngine();
    final now = DateTime(2026, 11, 18, 10);
    e.seedSyntheticHistory(now: now);
    final a = e.assess(now: now);
    expect(a.synthetic, isTrue);
    expect(a.daysOfData, 14);
    expect(a.status, ChangeStatus.changing);
  });
}
