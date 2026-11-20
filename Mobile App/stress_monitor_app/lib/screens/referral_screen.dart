/// Ask for a referral to a support station, choosing exactly what to share
/// and for how long; and the urgent "call me back" request from CrisisBar.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/support_contacts.dart';
import '../models/check_in.dart';
import '../models/referral.dart';
import '../models/support_station.dart';
import '../services/change_detector.dart';
import '../services/referral_service.dart';
import '../theme/physiopano_tokens.dart';

class ReferralRequestScreen extends StatefulWidget {
  final SupportStation station;
  final String uid;
  final CheckInResult? checkIn;
  final ReferralService? service;

  const ReferralRequestScreen({
    super.key,
    required this.station,
    required this.uid,
    this.checkIn,
    this.service,
  });

  @override
  State<ReferralRequestScreen> createState() => _ReferralRequestScreenState();
}

class _ReferralRequestScreenState extends State<ReferralRequestScreen> {
  late bool _scores = widget.checkIn != null;
  bool _summary = false;
  late final _note = TextEditingController(
    text: widget.checkIn == null
        ? "I'd like some support."
        : "I'd like some support. My recent ${widget.checkIn!.spec.name.toLowerCase()} came out as "
            '${widget.checkIn!.band.toLowerCase()}.',
  );
  final _contact = TextEditingController();
  int _days = 30;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final summary = _summary
          ? ReferralService.weeklySummaryFrom(context.read<ChangeDetector>().assessment)
          : null;
      await (widget.service ?? ReferralService()).send(
        uid: widget.uid,
        station: widget.station.id,
        kind: ReferralKind.referral,
        checkIn: widget.checkIn,
        weeklySummary: summary,
        choice: ShareChoice(
          checkInScores: _scores,
          weeklySummary: _summary && summary != null,
          note: _note.text,
          contact: _contact.text,
          shareFor: Duration(days: _days),
        ),
      );
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'The request did not send. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final t = Theme.of(context).textTheme;
    final s = widget.station;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(title: Text('Referral to ${s.name.toLowerCase()}')),
      body: SafeArea(
        child: _sent
            ? _Sent(station: s, days: _days)
            : ListView(
                padding: const EdgeInsets.all(PpSpace.s4),
                children: [
                  Text(s.handOff, style: t.bodyLarge),
                  const SizedBox(height: PpSpace.s2),
                  Text(
                    'Nothing is shared unless you switch it on. You can stop sharing at any time '
                    'in Settings, and the navigator loses access straight away.',
                    style: t.bodyMedium?.copyWith(color: c.inkMuted),
                  ),
                  const SizedBox(height: PpSpace.s5),
                  Text('What to share', style: t.titleLarge),
                  const SizedBox(height: PpSpace.s2),
                  _Panel(children: [
                    _ConsentSwitch(
                      title: 'Latest check-in scores',
                      subtitle: widget.checkIn == null
                          ? 'No check-in yet'
                          : '${widget.checkIn!.spec.shortName}: ${widget.checkIn!.band}. Scores only, not your answers.',
                      value: _scores,
                      onChanged: widget.checkIn == null ? null : (v) => setState(() => _scores = v),
                    ),
                    _ConsentSwitch(
                      title: 'Your 7-day summary',
                      subtitle: 'How far your signals were from your usual each day. No raw sensor data.',
                      value: _summary,
                      onChanged: (v) => setState(() => _summary = v),
                    ),
                    const _LockedRow(),
                  ]),
                  const SizedBox(height: PpSpace.s5),
                  Text('A note in your words', style: t.titleLarge),
                  const SizedBox(height: PpSpace.s2),
                  TextField(
                    controller: _note,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 600,
                    decoration: const InputDecoration(hintText: 'Anything you want them to know. Optional.'),
                  ),
                  const SizedBox(height: PpSpace.s3),
                  Text('How they can reach you', style: t.titleLarge),
                  const SizedBox(height: PpSpace.s2),
                  TextField(
                    controller: _contact,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: 'Phone number. Optional: without it, check back here for updates.',
                    ),
                  ),
                  const SizedBox(height: PpSpace.s5),
                  Text('Share for', style: t.titleLarge),
                  const SizedBox(height: PpSpace.s2),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 7, label: Text('7 days')),
                      ButtonSegment(value: 30, label: Text('30 days')),
                      ButtonSegment(value: 90, label: Text('90 days')),
                    ],
                    selected: {_days},
                    onSelectionChanged: (v) => setState(() => _days = v.first),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: PpSpace.s4),
                    Text(_error!, style: t.bodyLarge?.copyWith(color: c.crisis)),
                  ],
                  const SizedBox(height: PpSpace.s5),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: Text(_sending ? 'Sending…' : 'Send request'),
                  ),
                  const SizedBox(height: PpSpace.s2),
                  Text(
                    'A licensed care navigator reviews every request and decides the next step with you.',
                    style: t.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}

class _Sent extends StatelessWidget {
  final SupportStation station;
  final int days;
  const _Sent({required this.station, required this.days});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(PpSpace.s4),
      children: [
        Container(
          padding: const EdgeInsets.all(PpSpace.s5),
          decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(PpRadius.panel)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Request sent', style: t.displayMedium?.copyWith(color: c.onPanel, fontSize: 36)),
            const SizedBox(height: PpSpace.s3),
            Row(children: [
              const _DashedLine(),
              const SizedBox(width: PpSpace.s2),
              Expanded(
                child: Text('Waiting for a navigator to accept',
                    style: t.bodyLarge?.copyWith(color: c.onPanel)),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: PpSpace.s5),
        Text(
          'A care navigator will review your request for ${station.name.toLowerCase()}. '
          'You are sharing what you chose for $days days. You can stop sharing any time in Settings › Sharing.',
          style: t.bodyLarge,
        ),
        const SizedBox(height: PpSpace.s5),
        FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Done')),
      ],
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    return Row(children: [
      for (var i = 0; i < 3; i++)
        Container(width: 6, height: 3, margin: const EdgeInsets.only(right: 4), color: c.onPanel),
    ]);
  }
}

class _Panel extends StatelessWidget {
  final List<Widget> children;
  const _Panel({required this.children});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    // Material (not a painted box) so the switch rows keep their ink feedback.
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PpRadius.panel),
        side: BorderSide(color: c.line),
      ),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, color: c.line),
          children[i],
        ],
      ]),
    );
  }
}

class _ConsentSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _ConsentSwitch({required this.title, required this.subtitle, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      );
}

/// The permanent guarantee, visible rather than buried in a policy.
class _LockedRow extends StatelessWidget {
  const _LockedRow();
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    return ListTile(
      title: const Text('Your employer', style: TextStyle(fontWeight: FontWeight.w700)),
      subtitle: const Text('Never. Employers cannot be added.'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline, size: 16, color: c.inkMuted),
        const SizedBox(width: 4),
        Text('Locked off', style: TextStyle(color: c.inkMuted, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// From CrisisBar: ask a PHYSIOPAÑO care navigator to call back. The person
/// starts this; nobody is contacted without it.
Future<void> showUrgentCallbackSheet(
  BuildContext context, {
  required String uid,
  CheckInResult? checkIn,
  ReferralService? service,
}) {
  final phone = TextEditingController();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      var sending = false;
      var sent = false;
      String? error;
      return StatefulBuilder(builder: (ctx, setState) {
        final t = Theme.of(ctx).textTheme;
        final c = Theme.of(ctx).extension<PpColors>()!;
        Future<void> send() async {
          if (phone.text.trim().length < 7) {
            setState(() => error = 'Add a phone number so they can call you.');
            return;
          }
          setState(() {
            sending = true;
            error = null;
          });
          try {
            await (service ?? ReferralService()).send(
              uid: uid,
              station: PpStation.teleMH,
              kind: ReferralKind.urgent,
              checkIn: checkIn,
              choice: ShareChoice(
                checkInScores: checkIn != null,
                contact: phone.text,
                shareFor: const Duration(days: 7),
              ),
            );
            setState(() => sent = true);
          } catch (_) {
            setState(() => error = 'It did not send. Please call ${SupportContacts.supportLine.display} instead.');
          } finally {
            setState(() => sending = false);
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
              PpSpace.s5, 0, PpSpace.s5, MediaQuery.of(ctx).viewInsets.bottom + PpSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: sent
                ? [
                    Text('Request sent', style: t.titleLarge),
                    const SizedBox(height: PpSpace.s2),
                    Text(
                      'A care navigator has been alerted and will call you. If you feel unsafe before then, '
                      'call ${SupportContacts.supportLine.display} or ${SupportContacts.emergency.display}.',
                      style: t.bodyLarge,
                    ),
                    const SizedBox(height: PpSpace.s4),
                    FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                  ]
                : [
                    Text('Ask a care navigator to call you', style: t.titleLarge),
                    const SizedBox(height: PpSpace.s2),
                    Text(
                      'They will see your answer to the safety question, your check-in score and this number. '
                      'Shared for 7 days. If you are in danger now, call ${SupportContacts.emergency.display}.',
                      style: t.bodyLarge,
                    ),
                    const SizedBox(height: PpSpace.s4),
                    TextField(
                      controller: phone,
                      autofocus: true,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Your phone number'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: PpSpace.s2),
                      Text(error!, style: t.bodyLarge?.copyWith(color: c.crisis)),
                    ],
                    const SizedBox(height: PpSpace.s4),
                    FilledButton(
                      onPressed: sending ? null : send,
                      child: Text(sending ? 'Sending…' : 'Ask them to call me'),
                    ),
                  ],
          ),
        );
      });
    },
  );
}
