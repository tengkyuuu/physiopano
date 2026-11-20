import { useEffect, useMemo, useState } from "react";
import { getFunctions, httpsCallable } from "firebase/functions";
import {
  reportOutcomes, type ContactStation, type Dimension, type Measurement,
  type MetricKey, type OutcomeInput, type OutcomeReport,
} from "../../../functions/outcomeMetrics.mjs";
import { demoFollowUp, demoShared } from "../lib/demoReferrals";
import { consentActive, STATIONS, type Referral } from "../lib/referrals";

const METRICS: { key: MetricKey; label: string; unit: string; definition: string }[] = [
  { key: "handoff", label: "Hand-off success", unit: "%", definition: "Routine referrals accepted divided by routine referrals sent." },
  { key: "timelyFollowUp", label: "Follow-ups within a day", unit: "%", definition: "Eligible referrals with a response within 24 hours of the pilot prompt (72 hours for primary care or 48 for tele-mental health). Includes only referrals with an elapsed response window and active outcome consent." },
  { key: "urgentContact", label: "Urgent contact within 15 min", unit: "%", definition: "Urgent requests with first contact recorded within 15 minutes, divided by urgent requests at least 15 minutes old." },
  { key: "phq4Change", label: "PHQ-4 change", unit: " pts", definition: "Median repeat total minus original total for referrals with both PHQ-4 scores shared and active outcome consent." },
  { key: "pss4Change", label: "PSS-4 change", unit: " pts", definition: "Median repeat total minus original total for referrals with both PSS-4 scores shared and active outcome consent." },
  { key: "adverseEvents", label: "Recorded adverse events", unit: "", definition: "Sum of adverse events recorded by navigators across the referrals in this report." },
];

const DIMENSIONS: Record<Dimension, string> = {
  ageBand: "Age band",
  gender: "Gender",
  nationalityGroup: "Nationality group",
  language: "Preferred language",
  area: "Area",
};
const CONTACT_STATIONS: ContactStation[] = ["community", "primaryCare", "teleMH", "specialist"];
const number = new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 });
const format = (measurement: Measurement, unit: string) =>
  measurement ? number.format(measurement.value) + unit : "—";
const HOUR = 3.6e6;

function syntheticReport(referrals: Referral[], now: number) {
  const queue: OutcomeInput[] = referrals.map(referral => {
    const followUp = demoFollowUp(referral);
    return {
      uid: referral.ownerUid,
      kind: referral.kind,
      station: referral.station,
      createdAt: +referral.createdAt,
      acceptedAt: referral.acceptedAt?.getTime(),
      firstContactAt: referral.firstContactAt?.getTime(),
      adverseEventCount: referral.adverseEventCount,
      outcomeConsent: consentActive(referral, new Date(now)),
      initial: demoShared(referral).check_in,
      followUp: followUp ? { ...followUp, submittedAt: +followUp.submittedAt } : undefined,
    };
  });

  // An independent synthetic cohort makes the privacy threshold visible
  // without inventing individual demographic answers for the care queue.
  const cohorts: OutcomeInput[] = Array.from({ length: 18 }, (_, i) => {
    const group = i < 9 ? 0 : 1;
    const urgent = i % 3 === 0;
    const station = group === 0 ? "primaryCare" : "teleMH";
    const createdAt = now - (100 + i) * HOUR;
    const isPhq = i % 2 === 0;
    return {
      uid: "synthetic-cohort-" + i,
      kind: urgent ? "urgent" : "referral",
      station,
      createdAt,
      acceptedAt: i % 8 === 0 ? undefined : createdAt + HOUR,
      firstContactAt: createdAt + HOUR * (urgent ? 0.15 + (i % 2) * 0.2 : 2 + i),
      adverseEventCount: i === 14 ? 1 : 0,
      outcomeConsent: true,
      initial: { instrument: isPhq ? "PHQ-4" : "PSS-4", total: isPhq ? 7 : 10 },
      followUp: urgent ? undefined : {
        submittedAt: createdAt + HOUR * ((group === 0 ? 72 : 48) + 3),
        ...(isPhq ? { phq4Total: 5 } : { pss4Total: 7 }),
      },
      demographics: {
        ageBand: group === 0 ? "18–24" : "25–34",
        gender: i % 2 === 0 ? "Woman" : "Man",
        nationalityGroup: group === 0 ? "Emirati" : "Other nationality",
        language: group === 0 ? "Arabic" : "English",
        area: group === 0 ? "Abu Dhabi city" : "Al Ain",
      },
    };
  });
  return { ...reportOutcomes(queue, now, 1), groups: reportOutcomes(cohorts, now).groups };
}

export function Outcomes({ demoItems }: { demoItems: Referral[] | null }) {
  const [live, setLive] = useState<OutcomeReport | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [refresh, setRefresh] = useState(0);
  const [dimension, setDimension] = useState<Dimension>("ageBand");
  const demo = demoItems !== null;
  const synthetic = useMemo(() => demoItems ? syntheticReport(demoItems, Date.now()) : null, [demoItems]);

  useEffect(() => {
    if (demo) return;
    let current = true;
    setState("loading");
    setLive(null);
    httpsCallable<undefined, OutcomeReport>(getFunctions(), "getReferralOutcomes")()
      .then(response => {
        if (!current) return;
        setLive(response.data);
        setState("ready");
      })
      .catch(() => { if (current) setState("error"); });
    return () => { current = false; };
  }, [demo, refresh]);

  const report = synthetic ?? live;
  const groups = report?.groups[dimension] ?? [];
  const longest = Math.max(1, ...CONTACT_STATIONS.map(station => report?.stations[station]?.value ?? 0));

  return (
    <div className="desk-report">
      <header className="desk-page-head flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="desk-kicker">Care navigation</p><h1>Outcomes and fairness</h1>
          <p className="mt-2 text-body text-ink-muted max-w-[64ch]">
            {demo ? "Synthetic demo results. The group comparison uses a separate synthetic cohort."
              : "Results from the most recent 300 referrals. Follow-up and score aggregates use active referral and outcome sharing."}
          </p>
        </div>
        {!demo && <button type="button" disabled={state === "loading"}
          className="min-h-touch rounded-control border border-line px-4 font-semibold disabled:opacity-60"
          onClick={() => setRefresh(key => key + 1)}>Refresh results</button>}
      </header>

      {!demo && state === "loading" && <p role="status" className="text-ink-muted">Loading outcomes…</p>}
      {!demo && state === "error" && <p role="alert" className="text-ink">
        Live outcomes are unavailable. A navigator account and the reporting service are required. You can open the synthetic demo to preview the report.
      </p>}
      {report && <>
        <section aria-labelledby="outcome-metrics">
          <h2 id="outcome-metrics" className="text-title">Referral outcomes</h2>
          <p className="mt-1 text-small text-ink-muted">Referrals in this report: {report.sampleSize}</p>
          <dl className="report-metrics">
            {METRICS.map(metric => (
              <div key={metric.key} title={metric.definition}
                className="report-metric">
                <dt className="font-semibold">{metric.label}</dt>
                <dd className="font-data text-lead text-right">{format(report.metrics[metric.key], metric.unit)}</dd>
                <dd className="metric-definition">{metric.definition}</dd>
              </div>
            ))}
          </dl>
        </section>
        <section aria-labelledby="contact-times">
          <h2 id="contact-times" className="text-title">Time to first contact</h2>
          <p className="mt-1 text-small text-ink-muted" title="Median elapsed hours from referral submission to the first contact recorded by a navigator.">
            Median hours from routine referral to recorded contact, by current station.
          </p>
          <dl className="report-bars">
            {CONTACT_STATIONS.map(station => {
              const value = report.stations[station];
              return (
                <div key={station} className="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)_4rem] sm:grid-cols-[minmax(0,1fr)_minmax(0,2fr)_4rem] items-center gap-3">
                  <dt className="text-small font-semibold">{STATIONS[station].name}</dt>
                  <dd aria-hidden="true" className="h-2 bg-surface-sunk">
                    <div className="h-full bg-brand" style={{ width: ((value?.value ?? 0) / longest * 100) + "%" }} />
                  </dd>
                  <dd className="font-data text-right">{format(value, " h")}</dd>
                </div>
              );
            })}
          </dl>
        </section>
        <section aria-labelledby="group-comparison">
          <div className="flex flex-wrap justify-between items-end gap-4">
            <div>
              <h2 id="group-comparison" className="text-title">Compare groups</h2>
              <p className="mt-1 text-small text-ink-muted">
                Results appear only when at least five distinct people contributed to the group and the measure.
              </p>
            </div>
            <label className="grid gap-1 text-small font-semibold">
              Group by
              <select className="min-h-touch rounded-control border border-white/75 bg-surface px-3 shadow-raised"
                value={dimension} onChange={event => setDimension(event.target.value as Dimension)}>
                {Object.entries(DIMENSIONS).map(([key, label]) => <option key={key} value={key}>{label}</option>)}
              </select>
            </label>
          </div>
          {groups.length === 0 ? <p className="mt-4 rounded-panel border border-white/75 bg-surface p-4 text-ink-muted shadow-raised">
            There are no groups with enough consented results to show.
          </p> : (
            <div role="region" aria-label="Group comparison table" tabIndex={0}
              className="report-table">
              <table className="w-full min-w-[960px] text-small">
                <caption className="sr-only">Outcome comparisons by {DIMENSIONS[dimension]}</caption>
                <thead className="bg-surface-sunk text-left">
                  <tr>
                    <th scope="col" className="p-3">{DIMENSIONS[dimension]}</th>
                    {METRICS.map(metric => <th scope="col" key={metric.key} title={metric.definition} className="p-3">{metric.label}</th>)}
                    {CONTACT_STATIONS.map(station => <th scope="col" key={station} className="p-3">{STATIONS[station].name} contact</th>)}
                  </tr>
                </thead>
                <tbody>
                  {groups.map(group => <tr key={group.label} className="border-t border-line">
                    <th scope="row" className="p-3 text-left">{group.label}</th>
                    {METRICS.map(metric => <td key={metric.key} className="p-3 font-data">{format(group.metrics[metric.key], metric.unit)}</td>)}
                    {CONTACT_STATIONS.map(station => <td key={station} className="p-3 font-data">{format(group.stations[station], " h")}</td>)}
                  </tr>)}
                </tbody>
              </table>
            </div>
          )}
          <p className="mt-2 text-small text-ink-muted">A dash means too few eligible results or no data for that measure.</p>
        </section>
      </>}
    </div>
  );
}
