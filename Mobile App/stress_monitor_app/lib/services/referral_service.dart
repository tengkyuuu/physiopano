/// Sends consented referrals and urgent call-back requests to the care
/// console, and lets the person stop sharing at any time.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/check_in.dart';
import '../models/referral.dart';
import '../theme/physiopano_tokens.dart';
import 'baseline_engine.dart';

class ReferralService {
  final FirebaseFirestore _fs;
  ReferralService([FirebaseFirestore? fs]) : _fs = fs ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _fs.collection('referrals');

  static dynamic _ts(dynamic v) {
    if (v is DateTime) return Timestamp.fromDate(v);
    if (v is Map) return v.map((k, x) => MapEntry(k, _ts(x)));
    return v;
  }

  Future<String> send({
    required String uid,
    required PpStation station,
    required ReferralKind kind,
    required ShareChoice choice,
    CheckInResult? checkIn,
    Map<String, dynamic>? weeklySummary,
  }) async {
    final docs = buildReferral(
      uid: uid,
      station: station,
      kind: kind,
      choice: choice,
      now: DateTime.now(),
      checkIn: checkIn,
      weeklySummary: weeklySummary,
    );
    final ref = _col.doc();
    final batch = _fs.batch();
    final meta = _ts(docs.meta) as Map<String, dynamic>;
    meta['createdAt'] = FieldValue.serverTimestamp();
    meta['updatedAt'] = FieldValue.serverTimestamp();
    batch.set(ref, meta);
    batch.set(ref.collection('shared').doc('data'), docs.shared);
    await batch.commit();
    return ref.id;
  }

  /// Stop sharing: the shared document is deleted and the console shows
  /// "Consent withdrawn". The referral record itself remains for the audit.
  Future<void> withdraw(String id) async {
    final ref = _col.doc(id);
    final batch = _fs.batch();
    batch.delete(ref.collection('shared').doc('data'));
    batch.delete(ref.collection('shared').doc('followUp'));
    batch.update(ref, {
      'consent.withdrawnAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Stream<bool> hasFollowUp(String id) => _col
      .doc(id).collection('shared').doc('followUp')
      .snapshots().map((snapshot) => snapshot.exists);

  Future<void> submitFollowUp({
    required String id,
    required bool receivedSupport,
    required String? helpfulness,
    int? phq4Total,
    int? pss4Total,
  }) {
    return _col.doc(id).collection('shared').doc('followUp').set({
      'receivedSupport': receivedSupport,
      'helpfulness': helpfulness,
      'submittedAt': FieldValue.serverTimestamp(),
      if (phq4Total != null) 'phq4Total': phq4Total,
      if (pss4Total != null) 'pss4Total': pss4Total,
    });
  }

  Stream<List<ReferralView>> mine(String uid) => _col
      .where('ownerUid', isEqualTo: uid)
      .snapshots()
      .map((q) => q.docs.map(_view).whereType<ReferralView>().toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  static ReferralView? _view(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    try {
      final m = d.data();
      final consent = (m['consent'] as Map).cast<String, dynamic>();
      DateTime? t(dynamic v) => v is Timestamp ? v.toDate() : null;
      return ReferralView(
        id: d.id,
        kind: ReferralKind.values.byName(m['kind'] as String),
        station: PpStation.values.byName(m['station'] as String),
        status: ReferralStatus.values.byName(m['status'] as String),
        createdAt: t(m['createdAt']) ?? DateTime.now(),
        expiresAt: t(consent['expiresAt']) ?? DateTime.now(),
        withdrawnAt: t(consent['withdrawnAt']),
        streams: (consent['streams'] as List? ?? const []).cast<String>(),
        outcome: m['outcome'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Derived numbers only: status, plain summary, last 7 days of smoothed
  /// distance-from-usual per signal. No raw sensor data, no identity.
  static Map<String, dynamic>? weeklySummaryFrom(ChangeAssessment? a) {
    if (a == null) return null;
    final days = a.days.length > 7 ? a.days.sublist(a.days.length - 7) : a.days;
    return {
      'status': a.status.name,
      'summary': a.summary,
      'synthetic': a.synthetic,
      'days': [
        for (final d in days)
          {
            'date': d.date.toIso8601String().substring(0, 10),
            'shifted': d.shifted,
            'z': {for (final e in d.z.entries) e.key.key: double.parse(e.value.toStringAsFixed(2))},
          },
      ],
    };
  }
}
