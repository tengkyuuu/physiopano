import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/check_in.dart';
import '../models/referral.dart';
import '../models/support_station.dart';
import '../services/auth_service.dart';
import '../services/referral_service.dart';
import '../theme/physiopano_tokens.dart';
import 'check_in_screen.dart';

class ReferralFollowUps extends StatelessWidget {
  const ReferralFollowUps({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthService>().userId;
    if (uid.isEmpty) return const SizedBox.shrink();
    return _DueFollowUps(key: ValueKey(uid), uid: uid);
  }
}

class _DueFollowUps extends StatefulWidget {
  const _DueFollowUps({super.key, required this.uid});
  final String uid;

  @override
  State<_DueFollowUps> createState() => _DueFollowUpsState();
}

class _DueFollowUpsState extends State<_DueFollowUps> {
  late final _service = ReferralService();
  late final _referrals = _service.mine(widget.uid);
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ReferralView>>(
      stream: _referrals,
      builder: (context, snapshot) {
        final now = DateTime.now();
        return Column(
          children: [
            for (final referral in snapshot.data ?? const <ReferralView>[])
              if (referral.canFollowUp(now))
                _FollowUpPrompt(
                  key: ValueKey(referral.id),
                  referral: referral,
                  service: _service,
                ),
          ],
        );
      },
    );
  }
}

class _FollowUpPrompt extends StatefulWidget {
  const _FollowUpPrompt({
    super.key,
    required this.referral,
    required this.service,
  });

  final ReferralView referral;
  final ReferralService service;

  @override
  State<_FollowUpPrompt> createState() => _FollowUpPromptState();
}

class _FollowUpPromptState extends State<_FollowUpPrompt> {
  late final _submitted = widget.service.hasFollowUp(widget.referral.id);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<PpColors>()!;
    return StreamBuilder<bool>(
      stream: _submitted,
      builder: (context, snapshot) {
        if (snapshot.data != false || snapshot.hasError) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: PpSpace.s4),
          child: Material(
            color: colors.surface,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: colors.line),
              borderRadius: BorderRadius.circular(PpRadius.panel),
            ),
            child: ListTile(
              minTileHeight: PpSpace.touch,
              title: const Text('How did your referral go?'),
              subtitle: Text(SupportStation.of(widget.referral.station).name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _FollowUpScreen(
                    referral: widget.referral,
                    service: widget.service,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FollowUpScreen extends StatefulWidget {
  const _FollowUpScreen({required this.referral, required this.service});
  final ReferralView referral;
  final ReferralService service;

  @override
  State<_FollowUpScreen> createState() => _FollowUpScreenState();
}

class _FollowUpScreenState extends State<_FollowUpScreen> {
  bool? _received;
  String? _helpfulness;
  final _scores = <Instrument, int>{};
  bool _busy = false;
  String? _error;

  Future<void> _repeat(Instrument instrument) async {
    final result = await Navigator.of(context).push<CheckInResult>(
      MaterialPageRoute(
        builder: (_) => CheckInScreen(
          instrument: instrument,
          returnResultForFollowUp: true,
        ),
      ),
    );
    if (mounted && result != null) {
      setState(() => _scores[result.instrument] = result.total);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.submitFollowUp(
        id: widget.referral.id,
        receivedSupport: _received!,
        helpfulness: _received! ? _helpfulness : null,
        phq4Total: _scores[Instrument.phq4],
        pss4Total: _scores[Instrument.pss4],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow-up shared with your navigator.')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Could not share your follow-up. Check your connection and whether sharing is still active.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final station =
        SupportStation.of(widget.referral.station).name.toLowerCase();
    final expiry = MaterialLocalizations.of(context)
        .formatMediumDate(widget.referral.expiresAt.toLocal());
    return Scaffold(
      appBar: AppBar(title: const Text('Referral follow-up')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PpSpace.s4),
          children: [
            Text('Did you get support?', style: theme.textTheme.headlineMedium),
            const SizedBox(height: PpSpace.s2),
            Text('Think about your $station referral.'),
            const SizedBox(height: PpSpace.s3),
            Wrap(
              spacing: PpSpace.s2,
              children: [
                for (final answer in [true, false])
                  _option(
                    answer ? 'Yes' : 'No',
                    _received == answer,
                    () => setState(() {
                      _received = answer;
                      if (!answer) _helpfulness = null;
                    }),
                  ),
              ],
            ),
            if (_received == true) ...[
              const SizedBox(height: PpSpace.s5),
              Text('Did it help?', style: theme.textTheme.titleLarge),
              Wrap(
                spacing: PpSpace.s2,
                runSpacing: PpSpace.s2,
                children: [
                  for (final option in const {
                    'yes': 'Yes',
                    'somewhat': 'Somewhat',
                    'no': 'No',
                    'unsure': 'Unsure',
                  }.entries)
                    _option(
                      option.value,
                      _helpfulness == option.key,
                      () => setState(() => _helpfulness = option.key),
                    ),
                ],
              ),
            ],
            const SizedBox(height: PpSpace.s5),
            Text('Repeat a check-in', style: theme.textTheme.titleLarge),
            const Text('Optional. You can attach just the total score.'),
            const SizedBox(height: PpSpace.s2),
            for (final instrument in Instrument.values)
              _checkInOption(instrument),
            const SizedBox(height: PpSpace.s5),
            Text(
              'Your care navigator can see these answers and any attached scores until $expiry. You can stop sharing in Settings.',
            ),
            if (_error != null) ...[
              const SizedBox(height: PpSpace.s3),
              Text(_error!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: PpSpace.s3),
            FilledButton(
              onPressed: _busy ||
                      _received == null ||
                      (_received == true && _helpfulness == null)
                  ? null
                  : _submit,
              child: Text(_busy ? 'Sharing…' : 'Share follow-up'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkInOption(Instrument instrument) {
    final name = InstrumentSpec.of(instrument).shortName;
    final score = _scores[instrument];
    if (score == null) {
      return OutlinedButton(
        onPressed: _busy ? null : () => _repeat(instrument),
        child: Text('Repeat $name'),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('$name total: $score'),
      trailing: TextButton(
        onPressed:
            _busy ? null : () => setState(() => _scores.remove(instrument)),
        child: const Text('Remove'),
      ),
    );
  }

  Widget _option(String label, bool selected, VoidCallback onTap) {
    return Semantics(
      selected: selected,
      child: selected
          ? FilledButton(onPressed: _busy ? null : onTap, child: Text(label))
          : OutlinedButton(onPressed: _busy ? null : onTap, child: Text(label)),
    );
  }
}
