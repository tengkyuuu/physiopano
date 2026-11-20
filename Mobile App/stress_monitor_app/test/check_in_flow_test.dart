import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stress_monitor_app/models/check_in.dart';
import 'package:stress_monitor_app/screens/check_in_screen.dart';
import 'package:stress_monitor_app/theme/physiopano_tokens.dart';
import 'package:stress_monitor_app/widgets/crisis_bar.dart';

// The UI has ambient idle animations (Paño breathing/blinking) that loop
// forever, so pumpAndSettle would never settle. Render as a reduce-motion user
// would see it: the motion kit stops its loops when animations are disabled.
Widget app(Widget home) => MaterialApp(
      theme: ThemeData(useMaterial3: true, extensions: const [PpColors.light]),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    );

Future<void> answerAll(WidgetTester tester, String option) async {
  for (var i = 0; i < 4; i++) {
    await tester.tap(find.text(option));
    await tester.pump();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('low PHQ-4: no safety question, self-help suggested', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpWidget(app(const CheckInScreen(userId: 'test')));
    expect(find.text('Feeling nervous, anxious or on edge'), findsOneWidget);
    await answerAll(tester, 'Not at all');
    expect(find.text(safetyQuestionText), findsNothing);
    expect(find.text('Within the usual range'), findsOneWidget);
    expect(find.byType(CrisisBar), findsNothing);
    expect(find.textContaining('Self-help is a good next step'), findsOneWidget);
  });

  testWidgets('high PHQ-4 + safety yes shows the crisis bar first', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpWidget(app(const CheckInScreen(userId: 'test')));
    await answerAll(tester, 'Nearly every day');
    expect(find.text(safetyQuestionText), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await tester.pump();
    await tester.tap(find.text('See my result'));
    await tester.pumpAndSettle();
    expect(find.byType(CrisisBar), findsOneWidget);
    expect(find.textContaining('800 4673'), findsWidgets);
    expect(find.text('Severe'), findsOneWidget);
  });

  testWidgets('declining the safety question still shows the support line', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpWidget(app(const CheckInScreen(userId: 'test')));
    await answerAll(tester, 'Several days');
    await tester.tap(find.text("I'd rather not answer"));
    await tester.pump();
    await tester.tap(find.text('See my result'));
    await tester.pumpAndSettle();
    expect(find.byType(CrisisBar), findsNothing);
    expect(find.textContaining('National support line'), findsOneWidget);
    expect(find.textContaining('3 · Primary care'), findsOneWidget);
  });

  testWidgets('repeat check-in returns a result only when attached', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    CheckInResult? attached;
    await tester.pumpWidget(app(Builder(builder: (context) {
      return Scaffold(
        body: TextButton(
          onPressed: () async {
            attached = await Navigator.of(context).push<CheckInResult>(
              MaterialPageRoute(
                builder: (_) => const CheckInScreen(
                  userId: 'test',
                  returnResultForFollowUp: true,
                ),
              ),
            );
          },
          child: const Text('Repeat'),
        ),
      );
    })));
    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();
    await answerAll(tester, 'Not at all');
    expect(attached, isNull);
    await tester.tap(find.text('Attach total to follow-up'));
    await tester.pumpAndSettle();
    expect(attached?.total, 0);
  });
}

const safetyQuestionText =
    'Over the last 2 weeks, have you had thoughts that you would be better off dead, '
    'or of hurting yourself in some way?';
