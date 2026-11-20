/// Consent-first referrals to a support station.
///
/// Data layout (enforced by firestore.rules):
///   referrals/{id}              routing metadata only: pseudonym, station,
///                               status, consent summary, timestamps.
///   referrals/{id}/shared/data  exactly what the person chose to share.
///                               Readable by navigators only while consent is
///                               active; deleted when the person stops sharing.
///
/// Nothing is shared by default. Employers can never be a recipient.
library;

import '../theme/physiopano_tokens.dart';
import 'check_in.dart';

enum ReferralKind { referral, urgent }

enum ReferralStatus { pending, accepted, closed }

/// What the person chose to share, and for how long.
class ShareChoice {
  final bool checkInScores;
  final bool weeklySummary;
  final String? note;
  final String? contact;
  final Duration shareFor;

  const ShareChoice({
    this.checkInScores = false,
    this.weeklySummary = false,
    this.note,
    this.contact,
    this.shareFor = const Duration(days: 30),
  });

  List<String> get streams => [
        if (checkInScores) 'check_in_scores',
        if (weeklySummary) 'weekly_summary',
        if (note != null && note!.trim().isNotEmpty) 'note',
        if (contact != null && contact!.trim().isNotEmpty) 'contact',
      ];
}

/// Stable, non-identifying label shown to navigators instead of a name.
String pseudonymFor(String uid) {
  var h = 0x811c9dc5; // FNV-1a 32-bit
  for (final c in uid.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return 'Client ${(h & 0xfff).toRadixString(16).toUpperCase().padLeft(3, '0')}';
}

/// Derived check-in numbers only; never the individual answers.
Map<String, dynamic> checkInSummary(CheckInResult r, {bool includeSafety = false}) => {
      'instrument': r.spec.shortName,
      'total': r.total,
      'max': r.spec.maxTotal,
      'band': r.band,
      if (r.instrument == Instrument.phq4) 'worry': r.anxiety,
      if (r.instrument == Instrument.phq4) 'mood': r.lowMood,
      'taken_at': r.takenAt.toIso8601String(),
      if (includeSafety) 'safety_answer': r.safety.name,
    };

/// Builds the two documents. Pure, so it can be tested without Firestore.
/// Returns (top-level metadata, shared payload). Timestamps are DateTime;
/// the service converts them.
({Map<String, dynamic> meta, Map<String, dynamic> shared}) buildReferral({
  required String uid,
  required PpStation station,
  required ReferralKind kind,
  required ShareChoice choice,
  required DateTime now,
  CheckInResult? checkIn,
  Map<String, dynamic>? weeklySummary,
}) {
  final shared = <String, dynamic>{
    if (choice.checkInScores && checkIn != null)
      'check_in': checkInSummary(checkIn, includeSafety: kind == ReferralKind.urgent),
    if (choice.weeklySummary && weeklySummary != null) 'weekly_summary': weeklySummary,
    if (choice.note != null && choice.note!.trim().isNotEmpty) 'note': choice.note!.trim(),
    if (choice.contact != null && choice.contact!.trim().isNotEmpty) 'contact': choice.contact!.trim(),
  };
  final meta = <String, dynamic>{
    'ownerUid': uid,
    'pseudonym': pseudonymFor(uid),
    'kind': kind.name,
    'station': station.name,
    'status': ReferralStatus.pending.name,
    'createdAt': now,
    'updatedAt': now,
    'consent': {
      'streams': choice.streams,
      'grantedAt': now,
      'expiresAt': now.add(choice.shareFor),
      'withdrawnAt': null,
    },
  };
  return (meta: meta, shared: shared);
}

/// A referral as the person sees it in Settings > Sharing.
class ReferralView {
  final String id;
  final ReferralKind kind;
  final PpStation station;
  final ReferralStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? withdrawnAt;
  final List<String> streams;
  final String? outcome;

  const ReferralView({
    required this.id,
    required this.kind,
    required this.station,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.withdrawnAt,
    required this.streams,
    this.outcome,
  });

  bool sharingActive(DateTime now) => withdrawnAt == null && expiresAt.isAfter(now);

  DateTime? get followUpAt {
    if (kind != ReferralKind.referral) return null;
    return switch (station) {
      PpStation.primaryCare => createdAt.add(const Duration(hours: 72)),
      PpStation.teleMH => createdAt.add(const Duration(hours: 48)),
      _ => null,
    };
  }

  bool canFollowUp(DateTime now) {
    final due = followUpAt;
    return due != null && !now.isBefore(due) && sharingActive(now);
  }

  static String streamLabel(String s) => switch (s) {
        'check_in_scores' => 'check-in scores',
        'weekly_summary' => '7-day summary',
        'note' => 'your note',
        'contact' => 'contact number',
        _ => s,
      };
}
