// Consent rules for referrals. Run: npm test (starts the Firestore emulator).
import { readFileSync } from "node:fs";
import { test, before, after, beforeEach } from "node:test";
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from "@firebase/rules-unit-testing";
import {
  doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, collection, query, where, writeBatch,
  Timestamp, serverTimestamp, addDoc,
} from "firebase/firestore";

let env;
const DAY = 864e5;
const ts = (ms) => Timestamp.fromMillis(Date.now() + ms);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-physiopano",
    firestore: { rules: readFileSync("../firestore.rules", "utf8"), host: "127.0.0.1", port: 8089 },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const alice = () => env.authenticatedContext("alice").firestore();
const bob = () => env.authenticatedContext("bob").firestore();
const nav = () => env.authenticatedContext("nav1", { navigator: true }).firestore();

function meta(over = {}) {
  return {
    ownerUid: "alice", pseudonym: "Client 1A2", kind: "referral", station: "primaryCare",
    status: "pending", createdAt: ts(0), updatedAt: ts(0),
    consent: { streams: ["check_in_scores"], grantedAt: ts(0), expiresAt: ts(30 * DAY), withdrawnAt: null },
    ...over,
  };
}

async function seed(id = "r1", m = meta()) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "referrals", id), m);
    await setDoc(doc(db, "referrals", id, "shared", "data"), { check_in: { band: "Moderate", total: 7 } });
  });
}

test("owner can create a referral and its shared data in one batch", async () => {
  const db = alice();
  const b = writeBatch(db);
  b.set(doc(db, "referrals", "new"), meta());
  b.set(doc(db, "referrals", "new", "shared", "data"), { note: "hi" });
  await assertSucceeds(b.commit());
});

test("nobody can create a referral for someone else", async () => {
  await assertFails(setDoc(doc(bob(), "referrals", "x"), meta()));
});

test("consent longer than 90 days is refused", async () => {
  await assertFails(setDoc(doc(alice(), "referrals", "x"),
    meta({ consent: { streams: [], grantedAt: ts(0), expiresAt: ts(200 * DAY), withdrawnAt: null } })));
});

test("a referral cannot target an employer or unknown recipient", async () => {
  await assertFails(setDoc(doc(alice(), "referrals", "x"), meta({ station: "employer" })));
  await assertFails(setDoc(doc(alice(), "referrals", "x"), { ...meta(), employer: "ACME" }));
});

test("navigator reads shared data while consent is active", async () => {
  await seed();
  await assertSucceeds(getDoc(doc(nav(), "referrals", "r1", "shared", "data")));
});

test("another person can read neither the referral nor its data", async () => {
  await seed();
  await assertFails(getDoc(doc(bob(), "referrals", "r1")));
  await assertFails(getDoc(doc(bob(), "referrals", "r1", "shared", "data")));
});

test("navigator cannot read shared data after consent expires", async () => {
  await seed("r2", meta({ consent: { streams: [], grantedAt: ts(-40 * DAY), expiresAt: ts(-1 * DAY), withdrawnAt: null } }));
  await assertFails(getDoc(doc(nav(), "referrals", "r2", "shared", "data")));
});

test("owner withdraws: data deleted, navigator loses access, owner cannot re-open", async () => {
  await seed();
  const db = alice();
  await assertSucceeds(deleteDoc(doc(db, "referrals", "r1", "shared", "data")));
  await assertSucceeds(updateDoc(doc(db, "referrals", "r1"), { "consent.withdrawnAt": serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertFails(getDoc(doc(nav(), "referrals", "r1", "shared", "data")));
  await assertFails(updateDoc(doc(db, "referrals", "r1"), { "consent.withdrawnAt": null }));
});

test("owner cannot change routing or extend consent", async () => {
  await seed();
  await assertFails(updateDoc(doc(alice(), "referrals", "r1"), { status: "accepted" }));
  await assertFails(updateDoc(doc(alice(), "referrals", "r1"), { "consent.expiresAt": ts(300 * DAY) }));
});

test("navigator can accept, re-route and close while consent is active", async () => {
  await seed();
  const db = nav();
  await assertSucceeds(updateDoc(doc(db, "referrals", "r1"), { status: "accepted", acceptedAt: serverTimestamp(), updatedAt: serverTimestamp(), handledBy: "nav1" }));
  await assertSucceeds(updateDoc(doc(db, "referrals", "r1"), { station: "teleMH", updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(db, "referrals", "r1"), { status: "closed", outcome: "Appointment booked", closedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
});

test("navigator cannot touch consent", async () => {
  await seed();
  await assertFails(updateDoc(doc(nav(), "referrals", "r1"), { "consent.expiresAt": ts(80 * DAY) }));
});

test("after withdrawal a navigator may only close the referral", async () => {
  await seed("r3", meta({ consent: { streams: [], grantedAt: ts(0), expiresAt: ts(30 * DAY), withdrawnAt: ts(0) } }));
  await assertFails(updateDoc(doc(nav(), "referrals", "r3"), { status: "accepted", updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(nav(), "referrals", "r3"), { status: "closed", outcome: "Person declined", updatedAt: serverTimestamp() }));
});

test("non-navigators cannot list the queue; owners can list their own", async () => {
  await seed();
  await assertFails(getDocs(collection(bob(), "referrals")));
  await assertSucceeds(getDocs(query(collection(alice(), "referrals"), where("ownerUid", "==", "alice"))));
  await assertSucceeds(getDocs(collection(nav(), "referrals")));
});

test("audit log is append-only and written by navigators as themselves", async () => {
  await seed();
  await assertSucceeds(addDoc(collection(nav(), "referrals", "r1", "audit"), { by: "nav1", action: "viewed", at: serverTimestamp() }));
  await assertFails(addDoc(collection(nav(), "referrals", "r1", "audit"), { by: "someone-else", action: "viewed" }));
  await assertFails(addDoc(collection(alice(), "referrals", "r1", "audit"), { by: "alice", action: "viewed" }));
});

test("referrals are never deleted", async () => {
  await seed();
  await assertFails(deleteDoc(doc(nav(), "referrals", "r1")));
  await assertFails(deleteDoc(doc(alice(), "referrals", "r1")));
});

const followUp = (db, id = "r1") => doc(db, "referrals", id, "shared", "followUp");
const response = (fields = {}) => ({
  receivedSupport: true, helpfulness: "somewhat", submittedAt: serverTimestamp(), ...fields,
});

test("only the owner can submit an eligible follow-up once", async () => {
  await seed("r1", meta({ createdAt: ts(-4 * DAY) }));
  await assertFails(setDoc(followUp(bob()), response()));
  await assertFails(setDoc(followUp(nav()), response()));
  await assertFails(setDoc(followUp(alice()), response({ phq4Total: 13 })));
  await assertFails(setDoc(followUp(alice()), response({ safetyAnswer: "yes" })));
  await assertSucceeds(setDoc(followUp(alice()), response({ phq4Total: 5 })));
  await assertFails(setDoc(followUp(alice()), response({ phq4Total: 3 })));
  await assertSucceeds(getDoc(followUp(nav())));
  await assertFails(getDoc(followUp(bob())));
});

test("follow-up honours station windows, urgent requests and consent expiry", async () => {
  await seed("r1", meta({ createdAt: ts(-2.5 * DAY) }));
  await assertFails(setDoc(followUp(alice()), response()));
  await seed("tele", meta({ station: "teleMH", createdAt: ts(-2.5 * DAY) }));
  await assertSucceeds(setDoc(followUp(alice(), "tele"), response()));
  await seed("urgent", meta({ kind: "urgent", createdAt: ts(-5 * DAY) }));
  await assertFails(setDoc(followUp(alice(), "urgent"), response()));
  await seed("expired", meta({
    createdAt: ts(-10 * DAY),
    consent: { ...meta().consent, expiresAt: ts(-DAY) },
  }));
  await assertFails(setDoc(followUp(alice(), "expired"), response()));
});

test("withdrawal removes both shared documents and prevents follow-up re-creation", async () => {
  await seed("r1", meta({ createdAt: ts(-4 * DAY) }));
  const db = alice();
  await assertSucceeds(setDoc(followUp(db), response()));
  await assertFails(deleteDoc(followUp(db)));
  const batch = writeBatch(db);
  batch.delete(followUp(db));
  batch.delete(doc(db, "referrals", "r1", "shared", "data"));
  batch.update(doc(db, "referrals", "r1"), { "consent.withdrawnAt": serverTimestamp(), updatedAt: serverTimestamp() });
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(followUp(nav())));
  await assertFails(setDoc(followUp(db), response()));
});

test("first contact is recorded once by a navigator using server time", async () => {
  await seed();
  await assertFails(updateDoc(doc(alice(), "referrals", "r1"), { firstContactAt: serverTimestamp() }));
  const ref = doc(nav(), "referrals", "r1");
  await assertFails(updateDoc(ref, { firstContactAt: ts(-DAY) }));
  await assertSucceeds(updateDoc(ref, { firstContactAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { firstContactAt: serverTimestamp() }));
});

test("outcome demographics can only be read, edited or deleted by their owner", async () => {
  const prefs = db => doc(db, "outcome_demographics", "alice");
  const data = { groups: { language: "Arabic", ageBand: "18–24" }, consentedAt: serverTimestamp() };
  await assertFails(setDoc(prefs(bob()), data));
  await assertFails(setDoc(prefs(alice()), { ...data, groups: { ageBand: "exact date" } }));
  await assertFails(setDoc(prefs(alice()), { ...data, groups: { name: "Alice" } }));
  await assertSucceeds(setDoc(prefs(alice()), data));
  await assertSucceeds(getDoc(prefs(alice())));
  await assertFails(getDoc(prefs(nav())));
  await assertFails(getDocs(collection(nav(), "outcome_demographics")));
  await assertFails(deleteDoc(prefs(bob())));
  await assertSucceeds(deleteDoc(prefs(alice())));
});

test("legacy sessions remain owner-writable and hidden from unrelated accounts", async () => {
  const session = db => doc(db, "users", "alice", "sessions", "s1");
  await assertSucceeds(setDoc(session(alice()), { createdAt: serverTimestamp() }));
  await assertSucceeds(getDoc(session(alice())));
  await assertFails(getDoc(session(bob())));
  await assertFails(getDoc(session(nav())));
  await assertFails(updateDoc(session(bob()), { createdAt: serverTimestamp() }));
});

test("a new referral cannot use a backdated creation time to bypass the wait", async () => {
  await assertFails(setDoc(doc(alice(), "referrals", "backdated"), meta({ createdAt: ts(-4 * DAY) })));
});

test("adverse-event counts are whole numbers changed only by navigators with active consent", async () => {
  await seed();
  await assertFails(updateDoc(doc(alice(), "referrals", "r1"), { adverseEventCount: 1 }));
  const ref = doc(nav(), "referrals", "r1");
  await assertFails(updateDoc(ref, { adverseEventCount: -1 }));
  await assertFails(updateDoc(ref, { adverseEventCount: 1.5 }));
  await assertSucceeds(updateDoc(ref, { adverseEventCount: 2 }));
  await updateDoc(doc(alice(), "referrals", "r1"), { "consent.withdrawnAt": serverTimestamp() });
  await assertFails(updateDoc(ref, { status: "closed", adverseEventCount: 3 }));
});
