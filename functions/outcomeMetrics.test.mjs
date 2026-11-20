import { test } from "node:test";
import assert from "node:assert/strict";
import { reportOutcomes } from "./outcomeMetrics.mjs";

const hour = 3.6e6;
const now = 200 * hour;
const base = {
  uid: "a", station: "primaryCare", kind: "referral", createdAt: 0,
  acceptedAt: 2 * hour, firstContactAt: 3 * hour, outcomeConsent: true,
  initial: { instrument: "PHQ-4", total: 8 },
  followUp: { phq4Total: 5, submittedAt: 80 * hour },
  demographics: { language: "English" },
};

test("a navigator's acceptance alone does not count as urgent first contact", () => {
  const { metrics } = reportOutcomes([
    base,
    { ...base, kind: "urgent", firstContactAt: undefined },
    { ...base, kind: "urgent", firstContactAt: hour / 4 },
  ], now, 1);
  assert.equal(metrics.urgentContact.value, 50);
  assert.equal(metrics.handoff.value, 100);
});

test("small groups and measures are suppressed using distinct people", () => {
  const repeat = Array.from({ length: 7 }, () => base);
  const others = Array.from({ length: 4 }, (_, n) => ({
    ...base, uid: "person" + n, followUp: undefined,
  }));
  assert.equal(reportOutcomes(repeat, now).groups.language.length, 0);
  const { metrics } = reportOutcomes([...repeat, ...others], now).groups.language[0];
  assert.equal(metrics.handoff.value, 100);
  assert.equal(metrics.phq4Change, null);
});

test("follow-up metrics use only consented, elapsed windows and matching scores", () => {
  const { metrics, stations } = reportOutcomes([
    base,
    { ...base, uid: "b", outcomeConsent: false },
    { ...base, uid: "c", station: "teleMH", followUp: { pss4Total: 3, submittedAt: 90 * hour } },
    { ...base, uid: "d", createdAt: 150 * hour, followUp: undefined },
  ], now, 1);
  assert.deepEqual(metrics.timelyFollowUp, { value: 50, count: 2 });
  assert.deepEqual(metrics.phq4Change, { value: -3, count: 1 });
  assert.equal(metrics.pss4Change, null);
  assert.equal(stations.primaryCare.value, 3);
});
