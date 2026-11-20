// Care-queue data model and pure helpers (mirror of the app's lib/models/referral.dart).
import type { Timestamp } from "firebase/firestore";

export type Station = "selfHelp" | "community" | "primaryCare" | "teleMH" | "specialist";
export type Kind = "referral" | "urgent";
export type Status = "pending" | "accepted" | "closed";

export interface Referral {
  id: string;
  ownerUid: string;
  pseudonym: string;
  kind: Kind;
  station: Station;
  status: Status;
  createdAt: Date;
  updatedAt: Date;
  acceptedAt?: Date;
  closedAt?: Date;
  firstContactAt?: Date;
  adverseEventCount?: number;
  outcome?: string;
  consent: { streams: string[]; grantedAt: Date; expiresAt: Date; withdrawnAt: Date | null };
}

export interface FollowUp {
  receivedSupport: boolean;
  helpfulness: "yes" | "somewhat" | "no" | "unsure" | null;
  submittedAt: Date;
  phq4Total?: number;
  pss4Total?: number;
}

export function parseFollowUp(data: Record<string, unknown>): FollowUp | null {
  const submittedAt = toDate(data.submittedAt);
  if (!submittedAt || typeof data.receivedSupport !== "boolean") return null;
  return {
    receivedSupport: data.receivedSupport,
    helpfulness: data.helpfulness as FollowUp["helpfulness"],
    submittedAt,
    phq4Total: typeof data.phq4Total === "number" ? data.phq4Total : undefined,
    pss4Total: typeof data.pss4Total === "number" ? data.pss4Total : undefined,
  };
}

export interface SharedData {
  check_in?: { instrument: string; total: number; max: number; band: string; worry?: number; mood?: number; taken_at: string; safety_answer?: string };
  weekly_summary?: { status: string; summary: string; synthetic?: boolean; days: { date: string; shifted: boolean; z: Record<string, number> }[] };
  note?: string;
  contact?: string;
}

export const STATIONS: Record<Station, { n: number; name: string }> = {
  selfHelp: { n: 1, name: "Self-help" },
  community: { n: 2, name: "Community & peer" },
  primaryCare: { n: 3, name: "Primary care" },
  teleMH: { n: 4, name: "Tele-mental health" },
  specialist: { n: 5, name: "Specialist" },
};

/** Follow-up windows per station (pilot values, to be agreed with partners). */
export const SLA_HOURS: Record<Kind | Station, number> = {
  urgent: 0.25,
  referral: 72,
  selfHelp: 0,
  community: 0,
  primaryCare: 72,
  teleMH: 48,
  specialist: 168,
};

export const OUTCOMES = [
  "Appointment booked",
  "Referred on to another service",
  "Call-back completed",
  "Support completed",
  "Person declined",
  "No response after 3 attempts",
] as const;

const toDate = (v: unknown): Date | undefined =>
  v && typeof (v as Timestamp).toDate === "function" ? (v as Timestamp).toDate() : undefined;

export function parseReferral(id: string, d: Record<string, unknown>): Referral | null {
  try {
    const c = (d.consent ?? {}) as Record<string, unknown>;
    return {
      id,
      ownerUid: String(d.ownerUid ?? ""),
      pseudonym: String(d.pseudonym ?? "Client"),
      kind: (d.kind as Kind) ?? "referral",
      station: (d.station as Station) ?? "primaryCare",
      status: (d.status as Status) ?? "pending",
      createdAt: toDate(d.createdAt) ?? new Date(),
      updatedAt: toDate(d.updatedAt) ?? new Date(),
      acceptedAt: toDate(d.acceptedAt),
      closedAt: toDate(d.closedAt),
      firstContactAt: toDate(d.firstContactAt),
      adverseEventCount: typeof d.adverseEventCount === "number" ? d.adverseEventCount : undefined,
      outcome: d.outcome as string | undefined,
      consent: {
        streams: (c.streams as string[]) ?? [],
        grantedAt: toDate(c.grantedAt) ?? new Date(),
        expiresAt: toDate(c.expiresAt) ?? new Date(0),
        withdrawnAt: toDate(c.withdrawnAt) ?? null,
      },
    };
  } catch {
    return null;
  }
}

export const consentActive = (r: Referral, now = new Date()) =>
  !r.consent.withdrawnAt && r.consent.expiresAt > now;

export function followUpAt(r: Referral): Date | undefined {
  if (r.kind !== "referral" || (r.station !== "primaryCare" && r.station !== "teleMH")) return;
  return new Date(r.createdAt.getTime() + SLA_HOURS[r.station] * 3.6e6);
}

/** Hours until the follow-up window closes (negative = overdue). */
export function dueInHours(r: Referral, now = new Date()): number {
  const sla = r.kind === "urgent" ? SLA_HOURS.urgent : SLA_HOURS[r.station] || SLA_HOURS.referral;
  const start = r.status === "accepted" && r.acceptedAt ? r.acceptedAt : r.createdAt;
  return sla - (now.getTime() - start.getTime()) / 3.6e6;
}

/** Line form (design system): live = solid, pending = dashed, stale = half height. */
export function lineState(r: Referral, now = new Date()): "live" | "pending" | "stale" | "closed" {
  if (r.status === "closed") return "closed";
  if (dueInHours(r, now) < 0) return "stale";
  return r.status === "accepted" ? "live" : "pending";
}

export function fmtDue(h: number): string {
  const abs = Math.abs(h);
  const txt = abs < 1 ? `${Math.max(1, Math.round(abs * 60))} min` : abs < 48 ? `${Math.round(abs)} h` : `${Math.round(abs / 24)} d`;
  return h < 0 ? `Overdue ${txt}` : `Due in ${txt}`;
}

export const STREAM_LABEL: Record<string, string> = {
  check_in_scores: "Check-in scores",
  weekly_summary: "7-day summary",
  note: "Note",
  contact: "Contact number",
};

export const SIGNAL_LABEL: Record<string, string> = {
  hr: "Resting HR",
  rmssd: "HRV",
  eda: "Skin conductance",
  temp: "Skin temp",
};
