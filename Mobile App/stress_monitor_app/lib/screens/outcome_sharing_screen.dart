import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/physiopano_tokens.dart';

class OutcomeSharingScreen extends StatefulWidget {
  const OutcomeSharingScreen(
      {super.key, required this.uid, this.onboarding = false});
  final String uid;
  final bool onboarding;

  @override
  State<OutcomeSharingScreen> createState() => _OutcomeSharingScreenState();
}

class _OutcomeSharingScreenState extends State<OutcomeSharingScreen> {
  static const _fields = {
    'ageBand': ('Age band', ['18–24', '25–34', '35–44', '45 and over']),
    'gender': ('Gender', ['Woman', 'Man', 'Another gender']),
    'nationalityGroup': (
      'Nationality group',
      [
        'Emirati',
        'Other Gulf nationality',
        'Other nationality',
      ]
    ),
    'language': (
      'Preferred language',
      ['Arabic', 'English', 'Another language']
    ),
    'area': ('Area', ['Abu Dhabi city', 'Al Ain', 'Al Dhafra', 'Other area']),
  };

  late final _document = FirebaseFirestore.instance
      .collection('outcome_demographics')
      .doc(widget.uid);
  final _answers = <String, String>{};
  bool _busy = true;
  bool _enabled = false;
  bool _loadFailed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await _document.get();
      if (!mounted) return;
      final groups = snapshot.data()?['groups'];
      setState(() {
        _busy = false;
        _enabled = snapshot.exists;
        _answers.clear();
        if (groups is Map) {
          for (final field in _fields.entries) {
            final value = groups[field.key];
            if (value is String && field.value.$2.contains(value)) {
              _answers[field.key] = value;
            }
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loadFailed = true;
        _error = 'Could not load your sharing choice. Check your connection.';
      });
    }
  }

  Future<void> _save({required bool share}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (share) {
        await _document.set({
          'groups': _answers,
          'consentedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _document.delete();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(share ? 'Outcome sharing saved.' : 'Outcome sharing stopped.'),
      ));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Could not save your choice. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Outcome sharing')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PpSpace.s4),
          children: [
            Text('Help check who gets support', style: type.headlineMedium),
            const SizedBox(height: PpSpace.s2),
            const Text(
              'You can choose to include your currently shared referrals, check-in totals '
              'and follow-ups in outcome reports. These reports show group results only.',
            ),
            const SizedBox(height: PpSpace.s2),
            const Text(
              'Every question is optional. You can skip this or stop sharing in Settings. '
              'Your choice does not affect your care.',
            ),
            if (_busy && !_enabled) ...[
              const SizedBox(height: PpSpace.s4),
              const LinearProgressIndicator(),
            ],
            if (!_loadFailed)
              for (final field in _fields.entries) ...[
                const SizedBox(height: PpSpace.s4),
                DropdownMenu<String>(
                  key: ValueKey((field.key, _enabled, _busy)),
                  expandedInsets: EdgeInsets.zero,
                  label: Text(field.value.$1),
                  enabled: !_busy,
                  initialSelection: _answers[field.key] ?? '',
                  dropdownMenuEntries: [
                    const DropdownMenuEntry(
                        value: '', label: 'Skip this question'),
                    for (final value in field.value.$2)
                      DropdownMenuEntry(value: value, label: value),
                  ],
                  onSelected: (value) => setState(() {
                    if (value == null || value.isEmpty) {
                      _answers.remove(field.key);
                    } else {
                      _answers[field.key] = value;
                    }
                  }),
                ),
              ],
            if (_error != null) ...[
              const SizedBox(height: PpSpace.s4),
              Text(_error!),
            ],
            const SizedBox(height: PpSpace.s5),
            if (!_loadFailed)
              FilledButton(
                onPressed: _busy ? null : () => _save(share: true),
                child: Text(_enabled
                    ? 'Save sharing choices'
                    : 'Share for outcome reporting'),
              ),
            if (_loadFailed)
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _busy = true;
                    _loadFailed = false;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('Try again'),
              ),
            if (_enabled)
              OutlinedButton(
                onPressed: _busy ? null : () => _save(share: false),
                child: const Text('Stop outcome sharing'),
              )
            else if (widget.onboarding)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Skip for now'),
              ),
          ],
        ),
      ),
    );
  }
}
