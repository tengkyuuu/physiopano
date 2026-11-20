export type Dimension = "ageBand" | "gender" | "nationalityGroup" | "language" | "area";
export type MetricKey = "handoff" | "timelyFollowUp" | "urgentContact" | "adverseEvents" | "phq4Change" | "pss4Change";
export type ContactStation = "community" | "primaryCare" | "teleMH" | "specialist";
export type Measurement = { value: number; count: number } | null;
export interface OutcomeInput {
  uid: string;
  kind: string;
  station: string;
  createdAt: number;
  acceptedAt?: number;
  firstContactAt?: number;
  adverseEventCount?: number;
  outcomeConsent?: boolean;
  demographics?: Partial<Record<Dimension, string>>;
  initial?: { instrument: string; total: number };
  followUp?: { submittedAt: number; phq4Total?: number; pss4Total?: number };
}
export interface OutcomeGroup {
  label: string;
  metrics: Record<MetricKey, Measurement>;
  stations: Record<ContactStation, Measurement>;
}
export interface OutcomeReport extends Omit<OutcomeGroup, "label"> {
  sampleSize: number;
  groups: Record<Dimension, OutcomeGroup[]>;
}
export function reportOutcomes(rows: OutcomeInput[], now: number, privacyMinimum?: number): OutcomeReport;
