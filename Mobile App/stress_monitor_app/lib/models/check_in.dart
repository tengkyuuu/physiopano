/// Validated self-report check-ins and the stepped-support routing rules.
///
/// Instruments (English wording as published; do not rephrase):
///   - PHQ-4 (Kroenke et al., 2009): 2 anxiety items (GAD-2) + 2 depression
///     items (PHQ-2), past 2 weeks, 0–3 each, total 0–12.
///     Bands: 0–2 none, 3–5 mild, 6–8 moderate, 9–12 severe.
///     A subscale score >= 3 is a positive screen for that domain.
///   - PSS-4 (Cohen et al., 1983): perceived stress, past month, 0–4 each,
///     items 2 and 3 reverse-scored, total 0–16. It has NO diagnostic cut-off.
///
/// Arabic: validated Arabic versions exist; their exact wording must be added
/// from the licensed source, never machine-translated.
///
/// ROUTING RULES ARE PILOT RULES for the hackathon. They must be reviewed and
/// signed off by the clinical partner before real use.
library;

import '../theme/physiopano_tokens.dart';

enum Instrument { phq4, pss4 }

class CheckInItem {
  final String text;
  final bool reverse;
  const CheckInItem(this.text, {this.reverse = false});
}

class InstrumentSpec {
  final Instrument id;
  final String name;
  final String shortName;
  final String stem;
  final List<CheckInItem> items;
  final List<String> options;
  final String source;

  const InstrumentSpec({
    required this.id,
    required this.name,
    required this.shortName,
    required this.stem,
    required this.items,
    required this.options,
    required this.source,
  });

  int get maxPerItem => options.length - 1;
  int get maxTotal => maxPerItem * items.length;

  static InstrumentSpec of(Instrument i) => i == Instrument.phq4 ? phq4 : pss4;

  static const phq4 = InstrumentSpec(
    id: Instrument.phq4,
    name: 'Mood check',
    shortName: 'PHQ-4',
    stem: 'Over the last 2 weeks, how often have you been bothered by the following problems?',
    items: [
      CheckInItem('Feeling nervous, anxious or on edge'),
      CheckInItem('Not being able to stop or control worrying'),
      CheckInItem('Little interest or pleasure in doing things'),
      CheckInItem('Feeling down, depressed or hopeless'),
    ],
    options: ['Not at all', 'Several days', 'More than half the days', 'Nearly every day'],
    source: 'PHQ-4, a validated 4-question screen for anxiety and low mood.',
  );

  static const pss4 = InstrumentSpec(
    id: Instrument.pss4,
    name: 'Stress check',
    shortName: 'PSS-4',
    stem: 'In the last month, how often have you felt…',
    items: [
      CheckInItem('…that you were unable to control the important things in your life?'),
      CheckInItem('…confident about your ability to handle your personal problems?', reverse: true),
      CheckInItem('…that things were going your way?', reverse: true),
      CheckInItem('…that difficulties were piling up so high that you could not overcome them?'),
    ],
    options: ['Never', 'Almost never', 'Sometimes', 'Fairly often', 'Very often'],
    source: 'PSS-4, the 4-question Perceived Stress Scale.',
  );
}

/// Answer to the safety question.
enum SafetyAnswer { notAsked, no, yes, declined }

const safetyQuestion =
    'Over the last 2 weeks, have you had thoughts that you would be better off dead, '
    'or of hurting yourself in some way?';

class CheckInResult {
  final Instrument instrument;
  final List<int> answers; // raw option index per item
  final SafetyAnswer safety;
  final DateTime takenAt;
  final bool promptedByChange;

  const CheckInResult({
    required this.instrument,
    required this.answers,
    required this.safety,
    required this.takenAt,
    this.promptedByChange = false,
  });

  InstrumentSpec get spec => InstrumentSpec.of(instrument);

  int _scored(int i) =>
      spec.items[i].reverse ? spec.maxPerItem - answers[i] : answers[i];

  int get total => List.generate(answers.length, _scored).fold(0, (a, b) => a + b);

  /// PHQ-4 only: GAD-2 (items 1–2) and PHQ-2 (items 3–4).
  int get anxiety => instrument == Instrument.phq4 ? _scored(0) + _scored(1) : 0;
  int get lowMood => instrument == Instrument.phq4 ? _scored(2) + _scored(3) : 0;
  bool get anxietyPositive => instrument == Instrument.phq4 && anxiety >= 3;
  bool get lowMoodPositive => instrument == Instrument.phq4 && lowMood >= 3;

  bool get needsCrisisSupport => safety == SafetyAnswer.yes;

  /// Plain-language band.
  String get band {
    if (instrument == Instrument.pss4) return '$total of 16';
    if (total <= 2) return 'Within the usual range';
    if (total <= 5) return 'Mild';
    if (total <= 8) return 'Moderate';
    return 'Severe';
  }

  /// What the result means and what it does not mean (design-system content rule).
  String get meaning {
    if (instrument == Instrument.pss4) {
      return 'Higher scores mean you have felt more stress over the last month. '
          'This scale has no cut-off for a diagnosis, so the most useful comparison '
          'is with your own earlier check-ins.';
    }
    final parts = <String>[];
    if (anxietyPositive) parts.add('worry and nerves');
    if (lowMoodPositive) parts.add('low mood');
    final domains = parts.isEmpty ? '' : ' Your answers point mostly to ${parts.join(' and ')}.';
    switch (total) {
      case <= 2:
        return 'Your answers are within the usual range for the last 2 weeks.$domains';
      case <= 5:
        return 'You have had some difficult days in the last 2 weeks.$domains';
      case <= 8:
        return 'A fair amount has been weighing on you in the last 2 weeks.$domains '
            'Talking it through with a doctor could help.';
      default:
        return 'A lot has been weighing on you in the last 2 weeks.$domains '
            'Talking to a professional soon is a good idea.';
    }
  }

  static const notADiagnosis =
      'This is a screen, not a diagnosis. Only a clinician can diagnose. '
      'Your answers stay on this phone unless you choose to share them.';

  /// Suggested next stop on the support route (pilot rules, see file header).
  PpStation get suggestedStation {
    if (instrument == Instrument.pss4) {
      // No validated cut-off: only self-help or peer support are suggested.
      // Pilot rule: above the scale midpoint suggests community & peer.
      return total >= 8 ? PpStation.community : PpStation.selfHelp;
    }
    var s = switch (total) {
      <= 2 => PpStation.selfHelp,
      <= 5 => PpStation.community,
      <= 8 => PpStation.primaryCare,
      _ => PpStation.teleMH,
    };
    // A positive subscale screen warrants a closer look by primary care.
    if ((anxietyPositive || lowMoodPositive) && s.index < PpStation.primaryCare.index) {
      s = PpStation.primaryCare;
    }
    // Declining the safety question when it was asked: never route lower than
    // primary care, and the support line is shown.
    if (safety == SafetyAnswer.declined && s.index < PpStation.primaryCare.index) {
      s = PpStation.primaryCare;
    }
    // Specialist is reached only through a clinician, never suggested directly.
    return s;
  }

  /// Whether the safety question must be asked for these answers.
  static bool safetyQuestionNeeded(Instrument instrument, List<int> answers) {
    if (instrument != Instrument.phq4) return false;
    final r = CheckInResult(
        instrument: instrument, answers: answers, safety: SafetyAnswer.notAsked, takenAt: DateTime(2000));
    return r.total >= 3 || r.anxietyPositive || r.lowMoodPositive;
  }

  Map<String, dynamic> toJson() => {
        'i': instrument.name,
        'a': answers,
        's': safety.name,
        't': takenAt.toIso8601String(),
        'c': promptedByChange,
      };

  factory CheckInResult.fromJson(Map<String, dynamic> j) => CheckInResult(
        instrument: Instrument.values.byName(j['i'] as String),
        answers: (j['a'] as List).map((e) => (e as num).toInt()).toList(),
        safety: SafetyAnswer.values.byName(j['s'] as String),
        takenAt: DateTime.parse(j['t'] as String),
        promptedByChange: j['c'] as bool? ?? false,
      );
}
