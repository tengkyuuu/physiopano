/// The stepped support ladder drawn as a transit line (design system:
/// StationStrip). Each station carries its number, pictogram and name, never
/// colour alone. The travelled part of the line is solid; the rest is dashed.
library;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../models/check_in.dart';
import '../models/support_station.dart';
import '../screens/referral_screen.dart';
import '../services/auth_service.dart';
import '../screens/breathing_screen.dart';
import '../screens/mood_journal_screen.dart';
import '../theme/physiopano_tokens.dart';

class StationStrip extends StatelessWidget {
  final PpStation current;
  final PpStation? suggested;
  final ValueChanged<SupportStation>? onSelect;

  const StationStrip({
    super.key,
    this.current = PpStation.selfHelp,
    this.suggested,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    return LayoutBuilder(builder: (context, box) {
      const dot = 44.0;
      final colW = box.maxWidth / 5;
      return Semantics(
        label: 'Support route. You are at ${SupportStation.of(current).name}.'
            '${suggested == null ? '' : ' Suggested next stop: ${SupportStation.of(suggested!).name}.'}',
        child: Stack(
          children: [
            Positioned(
              left: colW / 2,
              right: colW / 2,
              top: dot / 2 - 1.5,
              height: 3,
              child: CustomPaint(
                painter: _RoutePainter(
                  travelledFraction: current.index / 4,
                  travelled: c.ink,
                  ahead: c.inkMuted,
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in SupportStation.all)
                  Expanded(
                    child: _StationStop(
                      station: s,
                      here: s.id == current,
                      next: s.id == suggested,
                      onTap: onSelect == null ? null : () => onSelect!(s),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _StationStop extends StatelessWidget {
  final SupportStation station;
  final bool here;
  final bool next;
  final VoidCallback? onTap;

  const _StationStop({required this.station, required this.here, required this.next, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PpRadius.control),
      child: Padding(
        padding: const EdgeInsets.only(bottom: PpSpace.s2),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.route(station.id),
                shape: BoxShape.circle,
                border: Border.all(color: c.ground, width: 4),
                boxShadow: next ? [BoxShadow(color: c.ink, spreadRadius: 3)] : null,
              ),
              child: Icon(station.icon, size: 18, color: c.onRoute(station.id)),
            ),
            const SizedBox(height: PpSpace.s1),
            Text('${station.number}', style: t.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w800)),
            Text(
              station.name,
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(fontSize: 12, height: 1.25, fontWeight: FontWeight.w600),
            ),
            if (here || next) ...[
              const SizedBox(height: PpSpace.s1),
              Text(
                here ? 'YOU ARE HERE' : 'SUGGESTED\nNEXT STOP',
                textAlign: TextAlign.center,
                style: t.labelSmall?.copyWith(fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final double travelledFraction;
  final Color travelled;
  final Color ahead;

  _RoutePainter({required this.travelledFraction, required this.travelled, required this.ahead});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final split = size.width * travelledFraction;
    final solid = Paint()
      ..color = travelled
      ..strokeWidth = 3;
    if (split > 0) canvas.drawLine(Offset(0, y), Offset(split, y), solid);
    final dash = Paint()
      ..color = ahead
      ..strokeWidth = 3;
    // Pending = dashed 6/4 (design system: line form carries state).
    for (var x = split; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, y), Offset((x + 6).clamp(0, size.width), y), dash);
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.travelledFraction != travelledFraction || old.travelled != travelled || old.ahead != ahead;
}

/// Bottom sheet describing a station: what it is, who it's for, what is shared.
Future<void> showStationSheet(BuildContext context, SupportStation s, {CheckInResult? checkIn, String? uid}) {
  final c = Theme.of(context).extension<PpColors>()!;
  final t = Theme.of(context).textTheme;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(PpSpace.s5, 0, PpSpace.s5, PpSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: c.route(s.id),
                child: Icon(s.icon, size: 18, color: c.onRoute(s.id)),
              ),
              const SizedBox(width: PpSpace.s3),
              Expanded(
                child: Text('${s.number} · ${s.name}', style: t.titleLarge),
              ),
            ]),
            const SizedBox(height: PpSpace.s4),
            _Block(title: 'What it is', body: s.whatItIs),
            _Block(title: 'Who it is for', body: s.whoItsFor),
            _Block(title: 'What gets shared', body: s.handOff),
            const SizedBox(height: PpSpace.s2),
            if (s.isSelfHelp) ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const BreathingScreen()));
                },
                icon: const Icon(Icons.air),
                label: const Text('Start a breathing exercise'),
              ),
              const SizedBox(height: PpSpace.s2),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodJournalScreen()));
                },
                icon: const Icon(Icons.edit_note),
                label: const Text('Write in your mood journal'),
              ),
            ] else if (s.id == PpStation.primaryCare || s.id == PpStation.teleMH) ...[
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReferralRequestScreen(
                        station: s,
                        uid: uid ?? context.read<AuthService>().userId,
                        checkIn: checkIn,
                      ),
                    ),
                  );
                },
                child: const Text('Request a referral'),
              ),
              const SizedBox(height: PpSpace.s2),
              Text('You choose what to share on the next screen. Nothing is sent until you press Send.',
                  style: t.bodySmall),
            ] else ...[
              Text(
                s.id == PpStation.community
                    ? 'Local groups for this stop will be listed here once they are confirmed with our partners.'
                    : 'A clinician refers you here. Start with primary care or tele-mental health.',
                style: t.bodySmall,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _Block extends StatelessWidget {
  final String title;
  final String body;
  const _Block({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: PpSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.labelLarge),
          const SizedBox(height: PpSpace.s1),
          Text(body, style: t.bodyLarge),
        ],
      ),
    );
  }
}
