import 'package:flutter_test/flutter_test.dart';
import 'package:stress_monitor_app/models/check_in.dart';
import 'package:stress_monitor_app/theme/physiopano_tokens.dart';

CheckInResult phq(List<int> a, {SafetyAnswer s = SafetyAnswer.notAsked}) =>
    CheckInResult(instrument: Instrument.phq4, answers: a, safety: s, takenAt: DateTime(2026, 11, 18));

CheckInResult pss(List<int> a) =>
    CheckInResult(instrument: Instrument.pss4, answers: a, safety: SafetyAnswer.notAsked, takenAt: DateTime(2026, 11, 18));

void main() {
  group('PHQ-4 scoring', () {
    test('total and subscales', () {
      final r = phq([3, 2, 1, 0]);
      expect(r.total, 6);
      expect(r.anxiety, 5);
      expect(r.lowMood, 1);
      expect(r.anxietyPositive, isTrue);
      expect(r.lowMoodPositive, isFalse);
    });

    test('bands follow the published cut-points', () {
      expect(phq([0, 0, 1, 1]).band, 'Within the usual range');
      expect(phq([1, 1, 1, 0]).band, 'Mild');
      expect(phq([2, 2, 1, 1]).band, 'Moderate');
      expect(phq([3, 3, 2, 1]).band, 'Severe');
    });
  });

  group('PSS-4 scoring', () {
    test('items 2 and 3 are reverse-scored', () {
      // Never unable to cope, very often confident, very often going my way, never piling up.
      expect(pss([0, 4, 4, 0]).total, 0);
      expect(pss([4, 0, 0, 4]).total, 16);
      expect(pss([2, 2, 2, 2]).total, 8);
    });

    test('never routes beyond community & peer', () {
      expect(pss([4, 0, 0, 4]).suggestedStation, PpStation.community);
      expect(pss([0, 4, 4, 0]).suggestedStation, PpStation.selfHelp);
    });

    test('never asks the safety question', () {
      expect(CheckInResult.safetyQuestionNeeded(Instrument.pss4, [4, 0, 0, 4]), isFalse);
    });
  });

  group('safety question', () {
    test('asked when PHQ-4 is mild or above', () {
      expect(CheckInResult.safetyQuestionNeeded(Instrument.phq4, [0, 0, 1, 1]), isFalse);
      expect(CheckInResult.safetyQuestionNeeded(Instrument.phq4, [1, 1, 1, 0]), isTrue);
    });

    test('asked on a positive subscale even with a low total', () {
      expect(CheckInResult.safetyQuestionNeeded(Instrument.phq4, [0, 0, 0, 3]), isTrue);
    });

    test('a yes needs crisis support regardless of score', () {
      expect(phq([1, 1, 1, 0], s: SafetyAnswer.yes).needsCrisisSupport, isTrue);
      expect(phq([1, 1, 1, 0], s: SafetyAnswer.no).needsCrisisSupport, isFalse);
    });
  });

  group('stepped routing', () {
    test('least intensive first', () {
      expect(phq([0, 0, 1, 1]).suggestedStation, PpStation.selfHelp);
      expect(phq([1, 1, 1, 1], s: SafetyAnswer.no).suggestedStation, PpStation.community);
      expect(phq([2, 2, 1, 1], s: SafetyAnswer.no).suggestedStation, PpStation.primaryCare);
      expect(phq([3, 3, 2, 2], s: SafetyAnswer.no).suggestedStation, PpStation.teleMH);
    });

    test('a positive subscale lifts mild to primary care', () {
      expect(phq([2, 1, 1, 0], s: SafetyAnswer.no).suggestedStation, PpStation.primaryCare);
    });

    test('declining the safety question never routes below primary care', () {
      expect(phq([1, 1, 1, 0], s: SafetyAnswer.declined).suggestedStation, PpStation.primaryCare);
    });

    test('specialist is never suggested directly', () {
      expect(phq([3, 3, 3, 3], s: SafetyAnswer.no).suggestedStation, isNot(PpStation.specialist));
    });
  });

  test('result round-trips through JSON', () {
    final r = phq([1, 2, 3, 0], s: SafetyAnswer.declined);
    final c = CheckInResult.fromJson(r.toJson());
    expect(c.answers, r.answers);
    expect(c.safety, r.safety);
    expect(c.total, r.total);
  });
}
