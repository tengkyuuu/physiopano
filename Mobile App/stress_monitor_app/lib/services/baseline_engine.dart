/// Personal-baseline change detection.
///
/// Replaces the WESAD-trained stress classifier. Instead of asking "is this
/// person stressed?" (a population label that did not transfer to our
/// sensors), it asks "is this person different from their OWN usual, for long
/// enough to be worth a check-in?".
///
/// Pipeline (all on the phone, no network):
///   1. Samples arrive at ~1 Hz. Moving samples are discarded.
///   2. Still samples are reduced to one median per signal per minute.
///   3. Minutes are grouped by day and time-of-day band (night, morning, day,
///      evening) because physiology has a daily rhythm.
///   4. A finished day keeps only its per-band median per signal.
///   5. Baseline for a band = median and MAD (scaled to σ) of the previous
///      [BaselineConfig.windowDays] daily values. Ready after
///      [BaselineConfig.minDays] days.
///   6. Each day gets a robust z-score per signal (mean over the bands it has),
///      smoothed across days with an EWMA.
///   7. A day "shifts" when at least [BaselineConfig.minSignals] signals have
///      |smoothed z| >= [BaselineConfig.zThreshold]. A CHANGE is flagged only
///      after [BaselineConfig.runDays] consecutive shifted days.
///
/// A change only ever OFFERS a validated check-in. It is never a diagnosis and
/// never triggers crisis handling on its own.
library;

import 'dart:math' as math;

/// Signals the engine tracks. Motion is used only to reject samples.
enum PpSignal { restingHr, rmssd, edaTonic, skinTemp }

extension PpSignalText on PpSignal {
  String get key => switch (this) {
        PpSignal.restingHr => 'hr',
        PpSignal.rmssd => 'rmssd',
        PpSignal.edaTonic => 'eda',
        PpSignal.skinTemp => 'temp',
      };

  String get label => switch (this) {
        PpSignal.restingHr => 'resting heart rate',
        PpSignal.rmssd => 'heart-rate variability',
        PpSignal.edaTonic => 'skin conductance',
        PpSignal.skinTemp => 'skin temperature',
      };

  /// Smallest meaningful spread, so a very steady baseline does not turn
  /// sensor noise into huge z-scores.
  double get minSigma => switch (this) {
        PpSignal.restingHr => 2.0, // bpm
        PpSignal.rmssd => 4.0, // ms
        PpSignal.edaTonic => 0.15, // µS
        PpSignal.skinTemp => 0.25, // °C
      };

  static PpSignal? fromKey(String k) {
    for (final s in PpSignal.values) {
      if (s.key == k) return s;
    }
    return null;
  }
}

/// Time-of-day bands. Baselines are compared within the same band.
enum DayBand { night, morning, day, evening }

DayBand bandOf(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 11) return DayBand.morning;
  if (h >= 11 && h < 17) return DayBand.day;
  if (h >= 17 && h < 22) return DayBand.evening;
  return DayBand.night;
}

/// Distance from the person's own usual, on a fixed ramp (design system:
/// deviation is shown by size, never by a red/amber/green scale).
enum DeviationLevel { within, notable, marked }

DeviationLevel levelFor(double absZ) {
  if (absZ < 1.0) return DeviationLevel.within;
  if (absZ <= 2.0) return DeviationLevel.notable;
  return DeviationLevel.marked;
}

enum ChangeStatus {
  /// Fewer than [BaselineConfig.minDays] days of data.
  learning,

  /// Baseline ready, no sustained change.
  steady,

  /// Sustained change for [BaselineConfig.runDays]+ days: offer a check-in.
  changing,
}

class BaselineConfig {
  final int windowDays;
  final int minDays;
  final int minMinutesPerBand;
  final double zThreshold;
  final int minSignals;
  final int runDays;
  final double ewmaAlpha;

  /// Samples whose accelerometer magnitude differs from 1 g by more than this
  /// are treated as movement and skipped.
  final double stillnessG;
  final int keepDays;

  const BaselineConfig({
    this.windowDays = 14,
    this.minDays = 7,
    this.minMinutesPerBand = 5,
    this.zThreshold = 1.5,
    this.minSignals = 2,
    this.runDays = 3,
    this.ewmaAlpha = 0.5,
    this.stillnessG = 0.12,
    this.keepDays = 28,
  });
}

class Baseline {
  final double median;
  final double sigma;
  final int days;
  const Baseline(this.median, this.sigma, this.days);

  double z(double value) => (value - median) / sigma;
}

/// Live comparison of the current reading with the usual for this band.
class LiveDeviation {
  final DayBand band;
  final Map<PpSignal, double> z;
  const LiveDeviation(this.band, this.z);

  bool get hasBaseline => z.isNotEmpty;

  double get maxAbsZ =>
      z.values.fold<double>(0, (m, v) => math.max(m, v.abs()));

  DeviationLevel get level => levelFor(maxAbsZ);

  /// The signal furthest from its usual, if any.
  MapEntry<PpSignal, double>? get strongest {
    MapEntry<PpSignal, double>? best;
    for (final e in z.entries) {
      if (best == null || e.value.abs() > best.value.abs()) best = e;
    }
    return best;
  }
}

/// One day's smoothed comparison with the person's usual.
class DayAssessment {
  final DateTime date;
  final Map<PpSignal, double> z; // EWMA-smoothed robust z
  final bool shifted;
  const DayAssessment(this.date, this.z, this.shifted);
}

class ChangeAssessment {
  final ChangeStatus status;

  /// Days with enough still data to count.
  final int daysOfData;

  /// Days needed before anything can be flagged.
  final int daysNeeded;

  /// When status is [ChangeStatus.changing]: first day of the current run.
  final DateTime? changingSince;

  /// Signals beyond the threshold today (smoothed z).
  final Map<PpSignal, double> shiftedSignals;
  final List<DayAssessment> days;
  final bool synthetic;

  const ChangeAssessment({
    required this.status,
    required this.daysOfData,
    required this.daysNeeded,
    required this.changingSince,
    required this.shiftedSignals,
    required this.days,
    required this.synthetic,
  });

  /// Plain-language summary, following the design system's content rules:
  /// compare to YOUR usual, say what it does not mean.
  String get summary {
    switch (status) {
      case ChangeStatus.learning:
        return 'Learning your usual: day ${math.min(daysOfData + 1, daysNeeded)} of $daysNeeded. '
            'Nothing is flagged while your baseline forms.';
      case ChangeStatus.steady:
        return 'Your signals are within your usual range.';
      case ChangeStatus.changing:
        final parts = shiftedSignals.entries
            .map((e) => '${e.key.label} ${e.value < 0 ? 'lower' : 'higher'}')
            .join(', ');
        return 'For a few days your $parts than your usual. '
            'This is not a diagnosis. Short sleep, illness or a heavy week '
            'can all do this.';
    }
  }
}

/// Running per-minute accumulator for the current minute.
class _MinuteBucket {
  final DateTime minute;
  final Map<PpSignal, List<double>> values = {};
  _MinuteBucket(this.minute);

  void add(PpSignal s, double v) => values.putIfAbsent(s, () => []).add(v);
}

String _dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

DateTime _parseDay(String k) => DateTime.parse(k);

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  if (n == 0) return double.nan;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

class BaselineEngine {
  final BaselineConfig config;

  /// Finished days: day -> band -> signal -> (median, minutes).
  final Map<String, Map<DayBand, Map<PpSignal, _DayValue>>> _days = {};

  /// Today's minute medians: band -> signal -> values.
  String? _todayKey;
  final Map<DayBand, Map<PpSignal, List<double>>> _today = {};

  _MinuteBucket? _bucket;

  /// True when the history was generated for a demo, never real data.
  bool synthetic = false;

  BaselineEngine({this.config = const BaselineConfig()});

  // ── Ingest ────────────────────────────────────────────────────────────────

  /// Feed one live sample. Pass null for any signal that is not valid right
  /// now. Returns true when a minute was completed (a good moment to persist
  /// and re-assess).
  bool addSample(
    DateTime t, {
    double? hr,
    double? rmssd,
    double? eda,
    double? temp,
    double? accelMag,
  }) {
    if (accelMag != null && (accelMag - 1.0).abs() > config.stillnessG) {
      return false; // moving: not a resting sample
    }
    final minute = DateTime(t.year, t.month, t.day, t.hour, t.minute);
    var completed = false;
    if (_bucket != null && _bucket!.minute != minute) {
      _closeMinute(_bucket!);
      _bucket = null;
      completed = true;
    }
    final cur = _bucket ??= _MinuteBucket(minute);
    if (hr != null && hr > 30 && hr < 200) cur.add(PpSignal.restingHr, hr);
    if (rmssd != null && rmssd > 0 && rmssd < 300) cur.add(PpSignal.rmssd, rmssd);
    if (eda != null && eda > 0 && eda < 60) cur.add(PpSignal.edaTonic, eda);
    if (temp != null && temp > 20 && temp < 45) cur.add(PpSignal.skinTemp, temp);
    return completed;
  }

  /// Add an already-reduced minute (used by tests and demo seeding).
  void addMinute(DateTime minute, Map<PpSignal, double> values) {
    final b = _MinuteBucket(minute);
    values.forEach(b.add);
    _closeMinute(b);
  }

  void _closeMinute(_MinuteBucket b) {
    final key = _dayKey(b.minute);
    if (_todayKey != null && _todayKey != key) _rollDay();
    _todayKey = key;
    final band = bandOf(b.minute);
    final dest = _today.putIfAbsent(band, () => {});
    b.values.forEach((s, vs) {
      if (vs.isEmpty) return;
      final list = dest.putIfAbsent(s, () => []);
      list.add(_median(vs));
      if (list.length > 400) list.removeAt(0);
    });
  }

  /// Compress today's minutes into per-band medians and start a new day.
  void _rollDay() {
    final key = _todayKey;
    if (key == null) return;
    final day = <DayBand, Map<PpSignal, _DayValue>>{};
    _today.forEach((band, signals) {
      signals.forEach((s, mins) {
        if (mins.length >= config.minMinutesPerBand) {
          day.putIfAbsent(band, () => {})[s] = _DayValue(_median(mins), mins.length);
        }
      });
    });
    if (day.isNotEmpty) _days[key] = day;
    _today.clear();
    _todayKey = null;
    _prune();
  }

  void _prune() {
    if (_days.length <= config.keepDays) return;
    final keys = _days.keys.toList()..sort();
    for (final k in keys.take(keys.length - config.keepDays)) {
      _days.remove(k);
    }
  }

  /// Today's per-band values so far (only bands with enough minutes).
  Map<DayBand, Map<PpSignal, _DayValue>> _todaySoFar() {
    final out = <DayBand, Map<PpSignal, _DayValue>>{};
    _today.forEach((band, signals) {
      signals.forEach((s, mins) {
        if (mins.length >= config.minMinutesPerBand) {
          out.putIfAbsent(band, () => {})[s] = _DayValue(_median(mins), mins.length);
        }
      });
    });
    return out;
  }

  // ── Baseline ──────────────────────────────────────────────────────────────

  /// Usual value for [signal] in [band], from days strictly before [before].
  Baseline? baselineFor(PpSignal signal, DayBand band, {DateTime? before}) {
    final cutoff = before == null ? null : _dayKey(before);
    final keys = _days.keys.where((k) => cutoff == null || k.compareTo(cutoff) < 0).toList()
      ..sort();
    final window = keys.length > config.windowDays
        ? keys.sublist(keys.length - config.windowDays)
        : keys;
    final xs = <double>[];
    for (final k in window) {
      final v = _days[k]?[band]?[signal];
      if (v != null) xs.add(v.median);
    }
    if (xs.length < config.minDays) return null;
    final med = _median(xs);
    final mad = _median(xs.map((x) => (x - med).abs()).toList());
    final sigma = math.max(mad * 1.4826, signal.minSigma);
    return Baseline(med, sigma, xs.length);
  }

  int get daysOfData => _days.length;

  // ── Live ──────────────────────────────────────────────────────────────────

  LiveDeviation live(
    DateTime t, {
    double? hr,
    double? rmssd,
    double? eda,
    double? temp,
  }) {
    final band = bandOf(t);
    final z = <PpSignal, double>{};
    void put(PpSignal s, double? v) {
      if (v == null) return;
      final b = baselineFor(s, band, before: t);
      if (b != null) z[s] = b.z(v);
    }

    put(PpSignal.restingHr, hr);
    put(PpSignal.rmssd, rmssd);
    put(PpSignal.edaTonic, eda);
    put(PpSignal.skinTemp, temp);
    return LiveDeviation(band, z);
  }

  // ── Days ──────────────────────────────────────────────────────────────────

  /// Assess every day that has data, oldest first, including today so far.
  ChangeAssessment assess({DateTime? now}) {
    final today = now ?? DateTime.now();
    final todayKey = _dayKey(today);
    final all = <String, Map<DayBand, Map<PpSignal, _DayValue>>>{..._days};
    final soFar = _todaySoFar();
    if (soFar.isNotEmpty && _todayKey == todayKey) all[todayKey] = soFar;
    final keys = all.keys.toList()..sort();

    if (_days.length < config.minDays) {
      return ChangeAssessment(
        status: ChangeStatus.learning,
        daysOfData: _days.length,
        daysNeeded: config.minDays,
        changingSince: null,
        shiftedSignals: const {},
        days: const [],
        synthetic: synthetic,
      );
    }

    final ewma = <PpSignal, double>{};
    final days = <DayAssessment>[];
    for (final k in keys) {
      final date = _parseDay(k);
      final raw = <PpSignal, double>{};
      for (final s in PpSignal.values) {
        final zs = <double>[];
        all[k]!.forEach((band, signals) {
          final v = signals[s];
          if (v == null) return;
          final b = baselineFor(s, band, before: date);
          if (b != null) zs.add(b.z(v.median));
        });
        if (zs.isNotEmpty) raw[s] = zs.reduce((a, b) => a + b) / zs.length;
      }
      if (raw.isEmpty) continue; // still learning on this day
      raw.forEach((s, z) {
        final prev = ewma[s];
        ewma[s] = prev == null ? z : config.ewmaAlpha * z + (1 - config.ewmaAlpha) * prev;
      });
      final smoothed = {for (final s in raw.keys) s: ewma[s]!};
      final over = smoothed.values.where((z) => z.abs() >= config.zThreshold).length;
      days.add(DayAssessment(date, smoothed, over >= config.minSignals));
    }

    // Count the run of shifted days ending at the latest assessed day.
    var run = 0;
    for (final d in days.reversed) {
      if (!d.shifted) break;
      run++;
    }
    final changing = run >= config.runDays;
    final latest = days.isEmpty ? null : days.last;
    final shiftedSignals = <PpSignal, double>{
      if (latest != null)
        for (final e in latest.z.entries)
          if (e.value.abs() >= config.zThreshold) e.key: e.value,
    };
    return ChangeAssessment(
      status: changing ? ChangeStatus.changing : ChangeStatus.steady,
      daysOfData: _days.length,
      daysNeeded: config.minDays,
      changingSince: changing ? days[days.length - run].date : null,
      shiftedSignals: changing ? shiftedSignals : const {},
      days: days,
      synthetic: synthetic,
    );
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'v': 1,
        'synthetic': synthetic,
        'days': {
          for (final e in _days.entries)
            e.key: {
              for (final b in e.value.entries)
                b.key.name: {
                  for (final s in b.value.entries) s.key.key: [s.value.median, s.value.minutes],
                },
            },
        },
        'todayKey': _todayKey,
        'today': {
          for (final b in _today.entries)
            b.key.name: {for (final s in b.value.entries) s.key.key: s.value},
        },
      };

  factory BaselineEngine.fromJson(Map<String, dynamic> j, {BaselineConfig config = const BaselineConfig()}) {
    final e = BaselineEngine(config: config);
    e.synthetic = j['synthetic'] as bool? ?? false;
    final days = (j['days'] as Map?) ?? {};
    days.forEach((k, bands) {
      final day = <DayBand, Map<PpSignal, _DayValue>>{};
      (bands as Map).forEach((bn, signals) {
        final band = DayBand.values.byName(bn as String);
        (signals as Map).forEach((sk, pair) {
          final s = PpSignalText.fromKey(sk as String);
          final p = pair as List;
          if (s != null) {
            day.putIfAbsent(band, () => {})[s] =
                _DayValue((p[0] as num).toDouble(), (p[1] as num).toInt());
          }
        });
      });
      e._days[k as String] = day;
    });
    e._todayKey = j['todayKey'] as String?;
    final today = (j['today'] as Map?) ?? {};
    today.forEach((bn, signals) {
      final band = DayBand.values.byName(bn as String);
      (signals as Map).forEach((sk, list) {
        final s = PpSignalText.fromKey(sk as String);
        if (s != null) {
          e._today.putIfAbsent(band, () => {})[s] =
              (list as List).map((x) => (x as num).toDouble()).toList();
        }
      });
    });
    return e;
  }

  /// Close out a stale "today" left over from an earlier app session.
  void catchUp(DateTime now) {
    if (_todayKey != null && _todayKey != _dayKey(now)) _rollDay();
  }

  void clear() {
    _days.clear();
    _today.clear();
    _todayKey = null;
    _bucket = null;
    synthetic = false;
  }

  // ── Demo ──────────────────────────────────────────────────────────────────

  /// Replace history with [days] days of SYNTHETIC data ending yesterday, so a
  /// demo can show a formed baseline. The last [driftDays] days drift (HRV
  /// lower, skin conductance higher) so the change flow can be shown.
  /// Always labelled synthetic; never mix with a real user's history.
  void seedSyntheticHistory({
    required DateTime now,
    int days = 14,
    int driftDays = 4,
    int seed = 7,
  }) {
    clear();
    synthetic = true;
    final rnd = math.Random(seed);
    double noise(double sd) => (rnd.nextDouble() * 2 - 1) * sd;
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
    for (var d = 0; d < days; d++) {
      final date = start.add(Duration(days: d));
      // A clear step that keeps growing, so the run rule fires inside the demo.
      final k = d - (days - driftDays);
      final drift = k >= 0 ? 0.6 + 0.4 * (k + 1) / driftDays : 0.0;
      for (final hour in [8, 13, 19]) {
        for (var m = 0; m < 10; m++) {
          addMinute(DateTime(date.year, date.month, date.day, hour, m), {
            PpSignal.restingHr: 66 + noise(2) + drift * 6,
            PpSignal.rmssd: 42 + noise(4) - drift * 16,
            PpSignal.edaTonic: 2.2 + noise(0.15) + drift * 1.0,
            PpSignal.skinTemp: 33.6 + noise(0.2),
          });
        }
      }
    }
    _rollDay();
  }
}

class _DayValue {
  final double median;
  final int minutes;
  const _DayValue(this.median, this.minutes);
}
