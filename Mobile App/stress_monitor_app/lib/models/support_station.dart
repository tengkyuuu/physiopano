/// The stepped support ladder: the least intensive safe option first.
///
/// Crisis is deliberately NOT a station. Urgent risk skips the ladder and goes
/// straight to emergency guidance and a trained human (see CrisisBar).
library;

import 'package:flutter/material.dart';

import '../theme/physiopano_tokens.dart';

class SupportStation {
  final PpStation id;
  final int number;
  final String name;
  final IconData icon;
  final String whatItIs;
  final String whoItsFor;
  final String handOff;

  const SupportStation({
    required this.id,
    required this.number,
    required this.name,
    required this.icon,
    required this.whatItIs,
    required this.whoItsFor,
    required this.handOff,
  });

  bool get isSelfHelp => id == PpStation.selfHelp;

  static SupportStation of(PpStation id) => all.firstWhere((s) => s.id == id);

  static const all = <SupportStation>[
    SupportStation(
      id: PpStation.selfHelp,
      number: 1,
      name: 'Self-help',
      icon: Icons.spa_outlined,
      whatItIs: 'Short exercises you can do now: paced breathing, a mood journal, sleep and rest tips.',
      whoItsFor: 'Anyone, any time. A good first step when things feel a bit heavier than usual.',
      handOff: 'Nothing is shared. Everything stays on this phone.',
    ),
    SupportStation(
      id: PpStation.community,
      number: 2,
      name: 'Community & peer',
      icon: Icons.groups_outlined,
      whatItIs: 'Peer support groups and community wellbeing programmes, in person or online.',
      whoItsFor: 'People who would like to talk with others going through something similar.',
      handOff: 'You choose a group and contact them yourself. Nothing is shared by the app.',
    ),
    SupportStation(
      id: PpStation.primaryCare,
      number: 3,
      name: 'Primary care',
      icon: Icons.medical_services_outlined,
      whatItIs: 'Your family doctor or clinic, who can look at mental and physical health together.',
      whoItsFor: 'When a check-in suggests a closer look, or when sleep, appetite or energy have changed.',
      handOff: 'You choose what to share (for example your weekly summary and check-in scores) and for how long.',
    ),
    SupportStation(
      id: PpStation.teleMH,
      number: 4,
      name: 'Tele-mental health',
      icon: Icons.videocam_outlined,
      whatItIs: 'A video or phone session with a licensed counsellor or psychologist.',
      whoItsFor: 'When feelings are getting in the way of work, study or relationships.',
      handOff: 'A care navigator reviews your request and books you in. You choose what they can see.',
    ),
    SupportStation(
      id: PpStation.specialist,
      number: 5,
      name: 'Specialist',
      icon: Icons.local_hospital_outlined,
      whatItIs: 'Psychiatry and specialist mental health services.',
      whoItsFor: 'Reached through a clinician\'s referral, never directly from the app.',
      handOff: 'A clinician refers you. The app only keeps you informed about where you are on the route.',
    ),
  ];
}
