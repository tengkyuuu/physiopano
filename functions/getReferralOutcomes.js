const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");

const LIMIT = 300;
const ms = value => value && typeof value.toMillis === "function" ? value.toMillis() : undefined;

exports.getReferralOutcomes = onCall(async request => {
  if (request.auth?.token.navigator !== true) {
    throw new HttpsError("permission-denied", "A navigator account is required for outcomes reporting.");
  }

  const { reportOutcomes } = await import("./outcomeMetrics.mjs");
  const db = getFirestore();
  const now = Date.now();

  // Read consent and its protected data from one consistent snapshot.
  return db.runTransaction(async tx => {
    const referrals = await tx.get(db.collection("referrals")
      .orderBy("createdAt", "desc").limit(LIMIT));
    const rows = referrals.docs.flatMap(doc => {
      const referral = doc.data();
      const createdAt = ms(referral.createdAt);
      if (createdAt === undefined || typeof referral.ownerUid !== "string") return [];
      return [{
        doc, referral,
        input: {
          uid: referral.ownerUid, kind: referral.kind, station: referral.station,
          createdAt, acceptedAt: ms(referral.acceptedAt),
          firstContactAt: ms(referral.firstContactAt),
          adverseEventCount: Number.isInteger(referral.adverseEventCount) ? referral.adverseEventCount : 0,
        },
      }];
    });

    const active = rows.filter(({ referral }) => referral.consent?.withdrawnAt === null &&
      (ms(referral.consent.expiresAt) ?? 0) > now);
    const eligibleUids = [...new Set(active.map(({ input }) => input.uid))];
    if (eligibleUids.length > 0) {
      const preferences = await tx.getAll(...eligibleUids.map(uid =>
        db.collection("outcome_demographics").doc(uid)));
      const byUid = new Map(preferences.filter(doc => doc.exists).map(doc => [doc.id, doc.data()]));
      const optedIn = active.filter(({ input }) => byUid.has(input.uid));
      if (optedIn.length > 0) {
        const snapshots = await tx.getAll(...optedIn.flatMap(({ doc }) => [
          doc.ref.collection("shared").doc("data"),
          doc.ref.collection("shared").doc("followUp"),
        ]));
        optedIn.forEach(({ referral, input }, i) => {
          input.outcomeConsent = true;
          input.demographics = byUid.get(input.uid).groups;
          if (Array.isArray(referral.consent.streams) && referral.consent.streams.includes("check_in_scores")) {
            input.initial = snapshots[i * 2].data()?.check_in;
          }
          const followUp = snapshots[i * 2 + 1].data();
          if (followUp) input.followUp = { ...followUp, submittedAt: ms(followUp.submittedAt) };
        });
      }
    }
    return reportOutcomes(rows.map(({ input }) => input), now);
  }, { readOnly: true });
});
