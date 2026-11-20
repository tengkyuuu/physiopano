/// Immediate guidance and a route to a trained person (design system:
/// CrisisBar). The only full crisis-red surface in the app. Shown when a
/// check-in answer indicates risk; never triggered by sensor data alone.
/// It does not auto-dismiss.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/support_contacts.dart';
import '../theme/physiopano_tokens.dart';

class CrisisBar extends StatelessWidget {
  /// Opens the "ask a care navigator to call me" request. Optional: without
  /// it, only the phone numbers are shown.
  final VoidCallback? onRequestCallback;

  const CrisisBar({super.key, this.onRequestCallback});

  Future<void> _call(BuildContext context, SupportContact contact) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: contact.dial));
    if (!ok && context.mounted) {
      await Clipboard.setData(ClipboardData(text: contact.dial));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the dialler. ${contact.display} is copied, so you can paste it.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final t = Theme.of(context).textTheme;
    final onCrisis = Theme.of(context).colorScheme.onError;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        decoration: BoxDecoration(color: c.crisis, borderRadius: BorderRadius.circular(PpRadius.panel)),
        padding: const EdgeInsets.all(PpSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("You don't have to handle this alone.",
                style: t.titleLarge?.copyWith(color: onCrisis, fontWeight: FontWeight.w800)),
            const SizedBox(height: PpSpace.s2),
            Text(
              'You told us you have had thoughts of hurting yourself. A trained person can talk '
              'with you now, in Arabic or English. If you are in immediate danger, call an ambulance.',
              style: t.bodyLarge?.copyWith(color: onCrisis),
            ),
            const SizedBox(height: PpSpace.s4),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: onCrisis, foregroundColor: c.crisis),
              onPressed: () => _call(context, SupportContacts.supportLine),
              icon: const Icon(Icons.phone_in_talk),
              label: Text('Talk to someone now · ${SupportContacts.supportLine.display}'),
            ),
            const SizedBox(height: PpSpace.s2),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: onCrisis,
                side: BorderSide(color: onCrisis, width: 1.5),
              ),
              onPressed: () => _call(context, SupportContacts.emergency),
              icon: const Icon(Icons.emergency_outlined),
              label: Text('${SupportContacts.emergency.label} · ${SupportContacts.emergency.display}'),
            ),
            if (onRequestCallback != null) ...[
              const SizedBox(height: PpSpace.s2),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: onCrisis),
                onPressed: onRequestCallback,
                icon: const Icon(Icons.support_agent),
                label: const Text('Ask a PHYSIOPAÑO care navigator to call me'),
              ),
            ],
            const SizedBox(height: PpSpace.s3),
            SelectableText(
              '${SupportContacts.supportLine.note} This message stays until you close the check-in.',
              style: t.bodyMedium?.copyWith(color: onCrisis),
            ),
          ],
        ),
      ),
    );
  }
}
