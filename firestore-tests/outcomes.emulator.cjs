// Exercises the callable handler against the isolated demo Firestore emulator.
const assert = require("node:assert/strict");
const { createRequire } = require("node:module");
const requireFunction = createRequire(require("node:path").resolve(__dirname, "../functions/index.js"));
const { initializeApp, deleteApp } = requireFunction("firebase-admin/app");
const { getFirestore, Timestamp } = requireFunction("firebase-admin/firestore");

(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? "", /^(127\.0\.0\.1|localhost):8089$/);
  const app = initializeApp({ projectId: "demo-physiopano" });
  const { getReferralOutcomes } = requireFunction("./getReferralOutcomes");
  const db = getFirestore(app);
  try {
    await assert.rejects(getReferralOutcomes.run({ auth: { token: {} } }), { code: "permission-denied" });
    const now = Date.now();
    const hour = 3.6e6;
    const between = h => Timestamp.fromMillis(now + hour * h);
    const batch = db.batch();
    for (let n = 0; n < 7; n++) {
      const uid = "synthetic-person-" + n;
      const ref = db.collection("referrals").doc("synthetic-r-" + n);
      batch.set(ref, {
        ownerUid: uid, pseudonym: "private-fixture-label", kind: "referral",
        station: "primaryCare", createdAt: between(-100), acceptedAt: between(-90),
        firstContactAt: between(-89), consent: {
          streams: ["check_in_scores"], expiresAt: between(n === 5 ? -1 : 24),
          withdrawnAt: n === 6 ? between(-1) : null,
        },
      });
      batch.set(ref.collection("shared").doc("data"), { check_in: { instrument: "PHQ-4", total: 8 } });
      batch.set(ref.collection("shared").doc("followUp"), { submittedAt: between(-25), phq4Total: 5 });
      batch.set(db.collection("outcome_demographics").doc(uid), { groups: { language: "Arabic" } });
    }
    await batch.commit();
    const request = { auth: { uid: "navigator", token: { navigator: true } } };
    const report = await getReferralOutcomes.run(request);
    assert.equal(report.sampleSize, 7);
    assert.deepEqual(report.metrics.phq4Change, { value: -3, count: 5 });
    assert.equal(report.groups.language.length, 1);
    assert.equal(report.groups.language[0].label, "Arabic");
    assert.ok(!JSON.stringify(report).includes("synthetic-person"));
    assert.ok(!JSON.stringify(report).includes("private-fixture-label"));
    await db.collection("outcome_demographics").doc("synthetic-person-0").delete();
    const afterWithdrawal = await getReferralOutcomes.run(request);
    assert.equal(afterWithdrawal.metrics.phq4Change, null);
    assert.equal(afterWithdrawal.groups.language.length, 0);
    console.log("Callable returned aggregates only, applied consent and hid groups after opt-out.");
  } finally {
    await db.terminate();
    await deleteApp(app);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
