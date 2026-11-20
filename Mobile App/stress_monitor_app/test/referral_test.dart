import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:stress_monitor_app/models/check_in.dart';
import 'package:stress_monitor_app/models/referral.dart';
import 'package:stress_monitor_app/models/support_station.dart';
import 'package:stress_monitor_app/screens/referral_screen.dart';
import 'package:stress_monitor_app/services/referral_service.dart';
import 'package:stress_monitor_app/theme/physiopano_tokens.dart';

final checkIn = CheckInResult(
  instrument: Instrument.phq4,
  answers: const [2, 2, 1, 1],
  safety: SafetyAnswer.no,
  takenAt: DateTime(2026, 11, 18, 9),
);

class FakeReferrals implements ReferralService {
  ShareChoice? lastChoice;
  ReferralKind? lastKind;
  PpStation? lastStation;

  @override
  Future<String> send({
    required String uid,
    required PpStation station,
    required ReferralKind kind,
    required ShareChoice choice,
    CheckInResult? checkIn,
    Map<String, dynamic>? weeklySummary,
  }) async {
    lastChoice = choice;
    lastKind = kind;
    lastStation = station;
    return 'r1';
  }

  @override
  Future<void> withdraw(String id) async {}

  @override
  Stream<List<ReferralView>> mine(String uid) => const Stream.empty();

  @override
  Stream<bool> hasFollowUp(String id) => Stream.value(false);

  @override
  Future<void> submitFollowUp({
    required String id,
    required bool receivedSupport,
    required String? helpfulness,
    int? phq4Total,
    int? pss4Total,
  }) async {}
}

void main() {
  group('payload', () {
    final now = DateTime(2026, 11, 18, 10);

    test('nothing is shared unless chosen', () {
      final r = buildReferral(
        uid: 'u1',
        station: PpStation.primaryCare,
        kind: ReferralKind.referral,
        choice: const ShareChoice(),
        now: now,
        checkIn: checkIn,
        weeklySummary: {'status': 'changing'},
      );
      expect(r.shared, isEmpty);
      expect((r.meta['consent'] as Map)['streams'], isEmpty);
    });

    test('only chosen streams are included, scores not answers', () {
      final r = buildReferral(
        uid: 'u1',
        station: PpStation.primaryCare,
        kind: ReferralKind.referral,
        choice: const ShareChoice(checkInScores: true, note: '  hello  '),
        now: now,
        checkIn: checkIn,
        weeklySummary: {'status': 'changing'},
      );
      expect(r.shared.keys, containsAll(['check_in', 'note']));
      expect(r.shared.containsKey('weekly_summary'), isFalse);
      expect(r.shared['note'], 'hello');
      final ci = r.shared['check_in'] as Map;
      expect(ci['total'], 6);
      expect(ci.containsKey('answers'), isFalse);
      expect(ci.containsKey('safety_answer'), isFalse); // only for urgent
    });

    test('metadata carries a pseudonym, never the name, and an expiry', () {
      final r = buildReferral(
        uid: 'firebase-uid-123',
        station: PpStation.teleMH,
        kind: ReferralKind.urgent,
        choice: const ShareChoice(checkInScores: true, contact: '050 123 4567', shareFor: Duration(days: 7)),
        now: now,
        checkIn: checkIn,
      );
      expect(r.meta['pseudonym'], matches(RegExp(r'^Client [0-9A-F]{3}$')));
      expect(r.meta['pseudonym'], pseudonymFor('firebase-uid-123'));
      expect((r.meta['consent'] as Map)['expiresAt'], now.add(const Duration(days: 7)));
      expect((r.shared['check_in'] as Map)['safety_answer'], 'no');
    });
  });

  testWidgets('request screen sends exactly what was switched on', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    final fake = FakeReferrals();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, extensions: const [PpColors.light]),
      home: ReferralRequestScreen(
        station: SupportStation.of(PpStation.primaryCare),
        uid: 'u1',
        checkIn: checkIn,
        service: fake,
      ),
    ));
    expect(find.text('Your employer'), findsOneWidget);
    expect(find.text('Never. Employers cannot be added.'), findsOneWidget);
    await tester.tap(find.text('7 days'));
    await tester.pump();
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(fake.lastKind, ReferralKind.referral);
    expect(fake.lastStation, PpStation.primaryCare);
    expect(fake.lastChoice!.streams, ['check_in_scores', 'note']);
    expect(fake.lastChoice!.shareFor, const Duration(days: 7));
    expect(find.text('Request sent'), findsOneWidget);
  });
}
