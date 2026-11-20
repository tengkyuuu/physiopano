import type { FollowUp, Referral, SharedData } from "./referrals";

const HOUR = 3.6e6;

export function demoReferrals(now = new Date()): Referral[] {
  const ago = (hours: number) => new Date(now.getTime() - hours * HOUR);
  const base = (id: string, hours: number, patch: Partial<Referral> = {}): Referral => ({
    id,
    ownerUid: id,
    pseudonym: "Synthetic " + id.slice(-1),
    kind: "referral",
    station: "primaryCare",
    status: "pending",
    createdAt: ago(hours),
    updatedAt: now,
    consent: {
      streams: ["check_in_scores"],
      grantedAt: ago(hours),
      expiresAt: ago(-168),
      withdrawnAt: null,
    },
    ...patch,
  });
  const withdrawn = base("demo-D", 80);
  withdrawn.consent.withdrawnAt = ago(10);
  return [
    base("demo-A", 2),
    base("demo-B", 100, {
      status: "accepted",
      acceptedAt: ago(74),
      firstContactAt: ago(73),
    }),
    base("demo-C", 56, { station: "teleMH" }),
    withdrawn,
    base("demo-E", 0.12, { kind: "urgent" }),
    base("demo-F", 80, {
      station: "teleMH",
      status: "closed",
      acceptedAt: ago(69),
      firstContactAt: ago(65),
      closedAt: ago(18),
      outcome: "Support completed",
    }),
  ];
}

export function demoShared(r: Referral): SharedData {
  const isPss = r.id === "demo-F";
  return {
    check_in: {
      instrument: isPss ? "PSS-4" : "PHQ-4",
      total: isPss ? 12 : 8,
      max: isPss ? 16 : 12,
      band: isPss ? "Perceived stress" : "Moderate",
      taken_at: r.createdAt.toISOString(),
      ...(r.kind === "urgent" ? { safety_answer: "yes" } : {}),
    },
  };
}

export function demoFollowUp(r: Referral): FollowUp | null {
  if (r.id !== "demo-B" && r.id !== "demo-F") return null;
  const receivedSupport = r.id === "demo-B";
  return {
    receivedSupport,
    helpfulness: receivedSupport ? "somewhat" : null,
    submittedAt: new Date(r.createdAt.getTime() + (receivedSupport ? 75 : 53) * HOUR),
    ...(receivedSupport ? { phq4Total: 5 } : { pss4Total: 9 }),
  };
}
