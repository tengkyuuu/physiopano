/// Two-minute validated check-in: one item per screen, an optional safety
/// question, then a result that explains itself and suggests the least
/// intensive safe next stop on the support route.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/support_contacts.dart';
import '../models/check_in.dart';
import '../models/support_station.dart';
import '../services/auth_service.dart';
import '../services/check_in_store.dart';
import '../theme/physiopano_tokens.dart';
import '../motion/motion.dart';
import '../widgets/crisis_bar.dart';
import '../widgets/station_strip.dart';
import 'referral_screen.dart';

class CheckInScreen extends StatefulWidget {
  final Instrument instrument;
  final bool promptedByChange;
  final bool returnResultForFollowUp;

  /// Defaults to the signed-in user; tests pass one in.
  final String? userId;

  const CheckInScreen({
    super.key,
    this.instrument = Instrument.phq4,
    this.promptedByChange = false,
    this.returnResultForFollowUp = false,
    this.userId,
  });

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

enum _Phase { items, safety, result }

class _CheckInScreenState extends State<CheckInScreen> {
  late Instrument _instrument = widget.instrument;
  late List<int?> _answers =
      List.filled(InstrumentSpec.of(_instrument).items.length, null);
  int _index = 0;
  _Phase _phase = _Phase.items;
  SafetyAnswer? _safety;
  CheckInResult? _result;
  CheckInResult? _previous;

  InstrumentSpec get _spec => InstrumentSpec.of(_instrument);

  void _restartWith(Instrument i) {
    setState(() {
      _instrument = i;
      _answers = List.filled(InstrumentSpec.of(i).items.length, null);
      _index = 0;
      _phase = _Phase.items;
      _safety = null;
      _result = null;
      _previous = null;
    });
  }

  void _next() {
    if (_phase == _Phase.items) {
      if (_index < _answers.length - 1) {
        setState(() => _index++);
        return;
      }
      final answers = _answers.cast<int>();
      if (CheckInResult.safetyQuestionNeeded(_instrument, answers)) {
        setState(() => _phase = _Phase.safety);
        return;
      }
      _finish(SafetyAnswer.notAsked);
    } else if (_phase == _Phase.safety && _safety != null) {
      _finish(_safety!);
    }
  }

  void _back() {
    if (_phase == _Phase.safety) {
      setState(() => _phase = _Phase.items);
    } else if (_index > 0) {
      setState(() => _index--);
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _finish(SafetyAnswer safety) async {
    final result = CheckInResult(
      instrument: _instrument,
      answers: _answers.cast<int>(),
      safety: safety,
      takenAt: DateTime.now(),
      promptedByChange: widget.promptedByChange,
    );
    final uid = widget.userId ?? context.read<AuthService>().userId;
    final history = await CheckInStore.load(uid);
    await CheckInStore.add(uid, result);
    if (!mounted) return;
    setState(() {
      _result = result;
      _previous = CheckInStore.previous(history, _instrument, result.takenAt);
      _phase = _Phase.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    return PopScope(
      canPop: _phase != _Phase.items || _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(
          title: Text(_phase == _Phase.result
              ? 'Your check-in'
              : '${_spec.name} · 2 minutes'),
        ),
        body: SafeArea(
          child: switch (_phase) {
            _Phase.items => _buildItem(context),
            _Phase.safety => _buildSafety(context),
            _Phase.result => _ResultView(
                result: _result!,
                uid: widget.userId ?? context.read<AuthService>().userId,
                previous: _previous,
                onTakePhq4: () => _restartWith(Instrument.phq4),
                onAttach: widget.returnResultForFollowUp
                    ? () => Navigator.of(context).pop(_result)
                    : null,
              ),
          },
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final item = _spec.items[_index];
    return _QuestionLayout(
      progress: _Progress(
          count: _answers.length, current: _index, answered: _answers),
      kicker: 'Question ${_index + 1} of ${_answers.length}',
      stem: _spec.stem,
      question: item.text,
      options: _spec.options,
      selected: _answers[_index],
      onSelect: (v) => setState(() => _answers[_index] = v),
      footer: Text(
        '${_spec.source} Your answers stay on this phone unless you choose to share them.',
        style: t.bodySmall,
      ),
      onBack: _back,
      onNext: _answers[_index] == null ? null : _next,
      nextLabel: _index == _answers.length - 1 ? 'See my result' : 'Next',
    );
  }

  Widget _buildSafety(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const options = ['No', 'Yes', "I'd rather not answer"];
    const values = [SafetyAnswer.no, SafetyAnswer.yes, SafetyAnswer.declined];
    return _QuestionLayout(
      progress: null,
      kicker: 'One more question',
      stem: 'We ask everyone whose answers show some difficult days.',
      question: safetyQuestion,
      options: options,
      selected: _safety == null ? null : values.indexOf(_safety!),
      onSelect: (i) => setState(() => _safety = values[i]),
      footer: Text(
        'If you answer yes, we will show you how to reach a trained person straight away. '
        'Nobody is contacted unless you choose to call.',
        style: t.bodySmall,
      ),
      onBack: _back,
      onNext: _safety == null ? null : _next,
      nextLabel: 'See my result',
    );
  }
}

class _QuestionLayout extends StatelessWidget {
  final Widget? progress;
  final String kicker;
  final String stem;
  final String question;
  final List<String> options;
  final int? selected;
  final ValueChanged<int> onSelect;
  final Widget footer;
  final VoidCallback onBack;
  final VoidCallback? onNext;
  final String nextLabel;

  const _QuestionLayout({
    required this.progress,
    required this.kicker,
    required this.stem,
    required this.question,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.footer,
    required this.onBack,
    required this.onNext,
    required this.nextLabel,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).extension<PpColors>()!;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FadeThroughSwitcher(
              axis: Axis.horizontal,
              child: KeyedSubtree(
                key: ValueKey(question),
                child: Material(
              color: c.surface,
              elevation: 8,
              shadowColor: c.shade.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PpRadius.panel),
                side: BorderSide(color: c.highlight, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(PpSpace.s5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child:
                              Text(kicker.toUpperCase(), style: PpTheme.eyebrow(context))),
                      if (progress != null) progress!,
                    ]),
                    const SizedBox(height: PpSpace.s4),
                    Text(stem,
                        style: t.bodyMedium?.copyWith(color: c.inkMuted)),
                    const SizedBox(height: PpSpace.s2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(question, style: t.headlineSmall)),
                        const SizedBox(width: 8),
                        const PanoMascot(mood: PanoMood.thinking, size: 58),
                      ],
                    ),
                    const SizedBox(height: PpSpace.s4),
                    Semantics(
                      label: 'Choose one',
                      child: Column(
                        children: [
                          for (var i = 0; i < options.length; i++)
                            _Option(
                              label: options[i],
                              selected: selected == i,
                              onTap: () => onSelect(i),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: PpSpace.s4),
                    footer,
                  ],
                ),
              ),
            ),
              ),
            ),
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(PpSpace.s4, 0, PpSpace.s4, PpSpace.s4),
          child: Row(children: [
            OutlinedButton(onPressed: onBack, child: const Text('Back')),
            const SizedBox(width: PpSpace.s3),
            Expanded(
              child: AnimatedOpacity(
                duration: PpMotion.base,
                opacity: onNext == null ? 0.5 : 1,
                child: SpringPress(
                  onTap: onNext,
                  child: IgnorePointer(
                    child: FilledButton(onPressed: onNext == null ? null : () {}, child: Text(nextLabel)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Option(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: PpSpace.s2),
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        button: true,
        child: SpringPress(
          onTap: onTap,
          pressedScale: 0.97,
          child: AnimatedContainer(
            duration: PpMotion.base,
            curve: PpMotion.ease,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: PpSpace.s4, vertical: PpSpace.s3),
            decoration: BoxDecoration(
              color: selected ? c.brand.withValues(alpha: 0.16) : c.surfaceSunk,
              borderRadius: BorderRadius.circular(PpRadius.control),
              border: Border.all(color: selected ? c.brand : Colors.transparent, width: 1.5),
            ),
            child: Row(children: [
              AnimatedContainer(
                duration: PpMotion.base,
                curve: PpMotion.settle,
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? c.brand : Colors.transparent,
                  border: Border.all(color: selected ? c.brand : c.inkMuted, width: 2),
                ),
                child: selected
                    ? DrawOn(
                        pathBuilder: DrawOn.check,
                        color: c.onBrand,
                        size: const Size(22, 22),
                        strokeWidth: 2.6,
                        duration: const Duration(milliseconds: 320),
                      )
                    : null,
              ),
              const SizedBox(width: PpSpace.s3),
              Expanded(child: Text(label, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w500))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Outline dots, filled when answered. Never a percentage bar.
class _Progress extends StatelessWidget {
  final int count;
  final int current;
  final List<int?> answered;
  const _Progress(
      {required this.count, required this.current, required this.answered});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: PpMotion.slow,
            curve: PpMotion.settle,
            margin: const EdgeInsets.only(left: 6),
            width: i == current ? 24 : 10,
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PpRadius.pill),
              color: answered[i] != null || i < current ? c.brand : null,
              border: Border.all(color: i == current || answered[i] != null ? c.brand : c.line, width: 2),
            ),
          ),
      ],
    );
  }
}

class _ResultView extends StatefulWidget {
  final CheckInResult result;
  final String uid;
  final CheckInResult? previous;
  final VoidCallback onTakePhq4;
  final VoidCallback? onAttach;

  const _ResultView(
      {required this.result,
      required this.uid,
      required this.previous,
      required this.onTakePhq4,
      this.onAttach});

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> {
  final _confetti = ConfettiController();

  CheckInResult get result => widget.result;
  String get uid => widget.uid;
  CheckInResult? get previous => widget.previous;
  VoidCallback get onTakePhq4 => widget.onTakePhq4;
  VoidCallback? get onAttach => widget.onAttach;

  /// Celebrate finishing only when the outcome is light. A difficult result
  /// gets a calm, supportive Paño instead: no confetti.
  bool get _light => !result.needsCrisisSupport && result.suggestedStation == PpStation.selfHelp;

  @override
  void initState() {
    super.initState();
    if (_light) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _confetti.fire(origin: const Offset(0.5, 0.18));
      });
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConfettiOverlay(controller: _confetti, child: _body(context));
  }

  Widget _body(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final t = Theme.of(context).textTheme;
    final suggested = SupportStation.of(result.suggestedStation);
    final prev = previous;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // Safety first: the crisis bar is always the first thing on screen.
        if (result.needsCrisisSupport) ...[
          CrisisBar(
            onRequestCallback: () =>
                showUrgentCallbackSheet(context, uid: uid, checkIn: result),
          ),
          const SizedBox(height: PpSpace.s5),
        ],
        // The one sign panel on this screen.
        Container(
          padding: const EdgeInsets.all(PpSpace.s5),
          decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.alphaBlend(c.brand.withValues(alpha: 0.22), c.panel), c.panel],
              ),
              borderRadius: BorderRadius.circular(PpRadius.panel)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(result.band,
                        style: t.displayMedium
                            ?.copyWith(color: c.onPanel, fontSize: 36, height: 1.1)),
                  ),
                  // Paño sits beside the result: celebrating light results,
                  // calm with a heart for harder ones.
                  PanoMascot(
                    mood: _light ? PanoMood.celebrate : PanoMood.calm,
                    size: 64,
                    prop: _light ? null : PanoProp.heart,
                  ),
                ],
              ),
              const SizedBox(height: PpSpace.s2),
              Text(
                result.instrument == Instrument.phq4
                    ? 'PHQ-4 ${result.total} of 12 · worry ${result.anxiety} of 6 · mood ${result.lowMood} of 6'
                    : 'PSS-4 perceived stress, last month',
                style:
                    PpTheme.data(context, size: 14).copyWith(color: c.onPanel),
              ),
              if (prev != null) ...[
                const SizedBox(height: PpSpace.s2),
                Text(
                    'Last time: ${prev.instrument == Instrument.pss4 ? prev.band : '${prev.total} of 12'}',
                    style: PpTheme.data(context, size: 14)
                        .copyWith(color: c.onPanel.withValues(alpha: 0.86))),
              ],
            ],
          ),
        ),
        const SizedBox(height: PpSpace.s5),
        Text(result.meaning, style: t.titleMedium),
        const SizedBox(height: PpSpace.s2),
        Text(CheckInResult.notADiagnosis,
            style: t.bodyLarge?.copyWith(color: c.inkMuted)),
        if (onAttach != null) ...[
          const SizedBox(height: PpSpace.s4),
          FilledButton(
            onPressed: onAttach,
            child: const Text('Attach total to follow-up'),
          ),
        ],
        if (result.safety == SafetyAnswer.declined) ...[
          const SizedBox(height: PpSpace.s4),
          _InfoPanel(
            text:
                'If things feel hard to carry, you can talk to someone any time: '
                '${SupportContacts.supportLine.label}, ${SupportContacts.supportLine.display}. '
                'In an emergency call ${SupportContacts.emergency.display}.',
          ),
        ],
        const SizedBox(height: PpSpace.s6),
        Text('Your support route',
            style: t.headlineMedium?.copyWith(fontSize: 24)),
        const SizedBox(height: PpSpace.s2),
        Text(
          suggested.isSelfHelp
              ? 'Self-help is a good next step. Every stop on the route stays open to you.'
              : 'Suggested next stop: ${suggested.number} · ${suggested.name}. You decide whether to go. '
                  'Self-help stays open to you along the way.',
          style: t.bodyLarge,
        ),
        const SizedBox(height: PpSpace.s4),
        StationStrip(
          suggested: suggested.isSelfHelp ? null : suggested.id,
          onSelect: (s) =>
              showStationSheet(context, s, checkIn: result, uid: uid),
        ),
        const SizedBox(height: PpSpace.s4),
        FilledButton(
          onPressed: () =>
              showStationSheet(context, suggested, checkIn: result, uid: uid),
          child: Text('See ${suggested.name.toLowerCase()}'),
        ),
        if (result.instrument == Instrument.pss4) ...[
          const SizedBox(height: PpSpace.s2),
          OutlinedButton(
            onPressed: onTakePhq4,
            child: const Text('Also do the 4-question mood check'),
          ),
        ],
        const SizedBox(height: PpSpace.s2),
        TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Done')),
        const SizedBox(height: PpSpace.s4),
        Text(
            'Routing rules are a pilot and will be reviewed by our clinical partner.',
            style: t.bodySmall,
            textAlign: TextAlign.center),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final String text;
  const _InfoPanel({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    return Container(
      padding: const EdgeInsets.all(PpSpace.s4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PpRadius.panel),
        border: Border.all(color: c.line),
      ),
      child: SelectableText(text, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
