// Care queue: consented referrals and urgent call-back requests.
// A licensed navigator makes every decision here; the app never routes on its own.
import { createContext, useContext, useEffect, useMemo, useRef, useState, type Dispatch, type ReactNode, type SetStateAction } from "react";
import {
  collection, onSnapshot, orderBy, query, limit, doc, getDocFromServer, writeBatch, addDoc, serverTimestamp,
} from "firebase/firestore";
import { Phone, X, ShieldOff, Lock, Clock3, HandHeart, Timer, PhoneIncoming, Inbox, ChevronRight } from "lucide-react";
import { Pano } from "./ConsoleBrand";
import { db, auth } from "../firebase";
import {
  type Referral, type SharedData, type Station, type FollowUp, STATIONS, OUTCOMES, STREAM_LABEL, SIGNAL_LABEL,
  parseReferral, parseFollowUp, consentActive, dueInHours, lineState, fmtDue,
} from "../lib/referrals";
import { demoShared, demoFollowUp } from "../lib/demoReferrals";

const ROUTE_CLASS: Record<Station, string> = {
  selfHelp: "bg-route-1 text-[var(--pp-on-route)]",
  community: "bg-route-2 text-[var(--pp-on-route)]",
  primaryCare: "bg-route-3 text-[var(--pp-on-route-3)]",
  teleMH: "bg-route-4 text-[var(--pp-on-route)]",
  specialist: "bg-route-5 text-[var(--pp-on-route)]",
};

function audit(r: Referral, action: string, detail?: string) {
  const by = auth.currentUser?.uid ?? "unknown";
  return addDoc(collection(db, "referrals", r.id, "audit"), {
    by, action, detail: detail ?? null, at: serverTimestamp(),
  }).catch(() => undefined);
}

async function act(r: Referral, patch: Record<string, unknown>, action: string, detail?: string) {
  const by = auth.currentUser?.uid;
  if (!by) throw new Error("A navigator session is required.");
  const batch = writeBatch(db);
  batch.update(doc(db, "referrals", r.id), {
    ...patch, updatedAt: serverTimestamp(), handledBy: by,
  });
  batch.set(doc(collection(db, "referrals", r.id, "audit")), {
    by, action, detail: detail ?? null, at: serverTimestamp(),
  });
  await batch.commit();
}

const DemoActions = createContext<typeof act | null>(null);

function useAct() {
  return useContext(DemoActions) ?? act;
}

function StationChip({ s }: { s: Station }) {
  const st = STATIONS[s];
  return (
    <span className="inline-flex items-center gap-2 font-semibold whitespace-nowrap">
      <span className={`inline-grid place-items-center w-[22px] h-[22px] rounded-full text-[12px] font-extrabold ${ROUTE_CLASS[s]}`}>{st.n}</span>
      {st.name}
    </span>
  );
}

function LineForm({ state }: { state: ReturnType<typeof lineState> }) {
  if (state === "closed") return <span className="inline-block w-[26px]" />;
  const half = state === "stale";
  return (
    <svg width="26" height="24" aria-hidden className="text-ink shrink-0">
      <line x1="0" y1="12" x2="26" y2="12" stroke="currentColor" strokeWidth="3" strokeDasharray={state === "pending" ? "6 4" : undefined} />
      <line x1="24" y1={half ? 8 : 2} x2="24" y2={half ? 16 : 22} stroke="currentColor" strokeWidth="3" />
    </svg>
  );
}

function handoffText(r: Referral, now: Date) {
  if (r.status === "closed") return `Closed · ${r.outcome ?? "no outcome"}`;
  const due = fmtDue(dueInHours(r, now));
  return r.status === "accepted" ? `Accepted · ${due}` : `Waiting · ${due}`;
}

export function CareQueue({ demoItems, setDemoItems }: {
  demoItems: Referral[] | null;
  setDemoItems: Dispatch<SetStateAction<Referral[] | null>>;
}) {
  const demo = demoItems !== null;
  const [items, setItems] = useState<Referral[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [openId, setOpenId] = useState<string | null>(null);
  const [showClosed, setShowClosed] = useState(false);
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 30_000);
    if (demo) return () => clearInterval(t);
    const q = query(collection(db, "referrals"), orderBy("createdAt", "desc"), limit(300));
    const unsub = onSnapshot(q,
      snap => {
        setItems(snap.docs.map(d => parseReferral(d.id, d.data())).filter((x): x is Referral => !!x));
        setLoading(false);
        setError(null);
      },
      e => { setError(e.code === "permission-denied" ? "This account is not a care navigator." : "Could not load the queue. Check the connection."); setLoading(false); });
    return () => { unsub(); clearInterval(t); };
  }, [demo]);

  const shown = demoItems ?? items;
  const demoAct: typeof act = async (referral, patch) => {
    const updatedAt = new Date();
    const localPatch = { ...patch, updatedAt };
    for (const field of ["acceptedAt", "closedAt", "firstContactAt"]) {
      if (field in patch) Object.assign(localPatch, { [field]: updatedAt });
    }
    setDemoItems(previous => previous?.map(row =>
      row.id === referral.id ? { ...row, ...localPatch } : row) ?? null);
  };

  const urgent = useMemo(() => shown
    .filter(r => r.kind === "urgent" && r.status !== "closed")
    .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime()), [shown]);
  const queue = useMemo(() => shown
    .filter(r => r.kind === "referral" && (showClosed || r.status !== "closed"))
    .sort((a, b) => (a.status === "closed" ? 1 : 0) - (b.status === "closed" ? 1 : 0) || dueInHours(a, now) - dueInHours(b, now)),
  [shown, showClosed, now]);
  const open = shown.find(r => r.id === openId) ?? null;

  const waiting = shown.filter(r => r.kind === "referral" && r.status === "pending").length;
  const overdue = shown.filter(r => r.status !== "closed" && dueInHours(r, now) < 0).length;

  const ready = demo || (!loading && !error);
  const metrics = [
    { label: "Waiting for review", total: waiting, icon: Inbox },
    { label: "Accepted referrals", total: shown.filter(r => r.kind === "referral" && r.status === "accepted").length, icon: HandHeart },
    { label: "Past follow-up window", total: overdue, icon: Timer },
    { label: "Urgent call-backs", total: urgent.length, icon: PhoneIncoming },
  ];
  return (
    <DemoActions.Provider value={demo ? demoAct : null}>
    <div className="desk-queue">
      <header className="desk-page-head"><p className="desk-kicker">Care navigation</p>
        <h1>Care queue</h1><p>Review requests, coordinate hand-offs, and follow up within each person’s sharing window.</p>
      </header>
      <dl className="queue-metrics" aria-label="Current queue totals">{metrics.map(({label,total,icon:Icon}) =>
        <div key={label}><dt><Icon size={16}/>{label}</dt><dd>{ready ? total : "—"}</dd></div>)}</dl>
      {!demo && loading && <p className="desk-message" role="status">Loading consented referrals…</p>}
      {!demo && error && <p className="desk-message" role="alert">{error}</p>}
      {ready && urgent.length > 0 && <section className="queue-section" aria-labelledby="urgent-h">
        <div className="section-head"><h2 id="urgent-h">Urgent call-backs</h2></div>
        <div className="urgent-list">{urgent.map(r => <UrgentCard key={r.id} r={r} now={now} onOpen={() => setOpenId(r.id)}/>)}</div>
      </section>}
      <section className="queue-section" aria-labelledby="queue-h">
        <div className="section-head"><h2 id="queue-h">Referrals</h2>
          <label className="closed-control"><input type="checkbox" checked={showClosed} onChange={e => setShowClosed(e.target.checked)}/>Show closed</label>
        </div>
        {ready && (queue.length ? <div className="queue-table-wrap"><table className="queue-table">
          <caption className="sr-only">Routine referrals by follow-up time</caption><thead><tr>
            {["Person","Shared context","Care station","Hand-off","Sharing"].map(label => <th key={label} scope="col">{label}</th>)}
          </tr></thead><tbody>{queue.map(r => <QueueRow key={r.id} r={r} now={now} onOpen={() => setOpenId(r.id)}/>)}</tbody>
        </table></div> : <div className="queue-empty"><Pano pose="sleepy"/><div><h3>{showClosed ? "No referrals yet" : "No open referrals"}</h3><p>Requests appear here when someone asks for support in the app.</p></div></div>)}
      </section>

      {open && <Detail key={open.id} r={open} now={now} onClose={() => setOpenId(null)} />}
    </div>
    </DemoActions.Provider>
  );
}

function useShared(r: Referral, now: Date) {
  const [data, setData] = useState<SharedData | null>(null);
  const [state, setState] = useState<"loading" | "ok" | "none">("loading");
  const active = consentActive(r, now);
  const demo = useContext(DemoActions) !== null;
  useEffect(() => {
    if (demo) return;
    if (!active) { setData(null); setState("none"); return; }
    let live = true;
    setState("loading");
    getDocFromServer(doc(db, "referrals", r.id, "shared", "data"))
      .then(s => { if (live) { setData(s.exists() ? (s.data() as SharedData) : null); setState(s.exists() ? "ok" : "none"); } })
      .catch(() => { if (live) { setData(null); setState("none"); } });
    return () => { live = false; };
  }, [r.id, active, demo]);
  if (demo) return { data: active ? demoShared(r) : null, state: active ? "ok" : "none", active } as const;
  return { data: active ? data : null, state, active };
}

function WhyText({ r, shared }: { r: Referral; shared: ReturnType<typeof useShared> }) {
  if (!shared.active) return <span className="text-ink-muted">{r.consent.withdrawnAt ? "Consent withdrawn" : "Sharing ended"}</span>;
  if (shared.state === "loading") return <span className="text-ink-muted">…</span>;
  const ci = shared.data?.check_in;
  const shifted = shared.data?.weekly_summary?.status === "changing";
  const parts = [
    ci ? `${ci.instrument} ${ci.total}/${ci.max} · ${ci.band}` : null,
    shifted ? "changed from usual" : null,
    shared.data?.note ? "note" : null,
  ].filter(Boolean);
  return <span>{parts.length ? parts.join(" · ") : <span className="text-ink-muted">Nothing shared beyond the request</span>}</span>;
}

function QueueRow({ r, now, onOpen }: { r: Referral; now: Date; onOpen: () => void }) {
  const shared = useShared(r, now);
  const ls = lineState(r, now);
  return (
    <tr className="referral-row" onClick={onOpen}>
      <th scope="row"><button type="button" className="person-link" aria-label={`Open referral for ${r.pseudonym}`} onClick={e=>{ e.stopPropagation(); onOpen(); }}>{r.pseudonym}<ChevronRight size={13}/></button></th>
      <td data-label="Shared context" className="px-4 py-3"><WhyText r={r} shared={shared} /></td>
      <td data-label="Care station" className="px-4 py-3"><StationChip s={r.station} /></td>
      <td data-label="Hand-off" className="px-4 py-3">
        <span className={`inline-flex items-center gap-2 whitespace-nowrap ${ls === "closed" ? "text-ink-muted" : ""}`}>
          <LineForm state={ls} />{handoffText(r, now)}
        </span>
      </td>
      <td data-label="Sharing" className="px-4 py-3 whitespace-nowrap text-ink-muted">
        {consentActive(r, now) ? `Until ${r.consent.expiresAt.toLocaleDateString()}` : (
          <span className="inline-flex items-center gap-1"><ShieldOff size={14} />{r.consent.withdrawnAt ? "Withdrawn" : "Ended"}</span>
        )}
      </td>
    </tr>
  );
}

function UrgentCard({ r, now, onOpen }: { r: Referral; now: Date; onOpen: () => void }) {
  const shared = useShared(r, now);
  const perform = useAct();
  const [actionError, setActionError] = useState(false);
  const contact = shared.data?.contact;
  const demo = useContext(DemoActions) !== null;
  const since = Math.max(1, Math.round((now.getTime() - r.createdAt.getTime()) / 60000));
  return (
    <div className="urgent-card"><span className="urgent-icon"><PhoneIncoming size={20}/></span>
      <div className="min-w-0 flex-1">
        <p className="urgent-person">{r.pseudonym} <span>requested a call-back</span></p>
        <p className="urgent-sub"><Clock3 size={13}/> {since} min ago · {shared.active ? (shared.data?.check_in ? `${shared.data.check_in.instrument} ${shared.data.check_in.band} · safety answer: ${shared.data.check_in.safety_answer ?? "not shared"}` : "No scores shared")
            : r.consent.withdrawnAt ? "Consent withdrawn" : "Sharing ended"}
          {r.status === "accepted" ? " · a navigator has taken this" : ""}
        </p>
      </div>
      {contact && consentActive(r, now) && (demo ? <span className="demo-contact">{contact}</span> : (
        <a href={`tel:${contact.replace(/\s+/g, "")}`} className="inline-flex items-center gap-2 rounded-control bg-crisis-on text-crisis px-4 min-h-touch font-bold">
          <Phone size={18} /> <span className="font-data">{contact}</span>
        </a>
      ))}
      {r.status === "pending" && shared.active && (
        <button className="urgent-accept"
          onClick={() => {
            setActionError(false);
            void perform(r, { status: "accepted", acceptedAt: serverTimestamp() }, "accepted")
              .catch(() => setActionError(true));
          }}>I'm calling</button>
      )}
      <button className="urgent-detail" onClick={onOpen}>Details</button>
      {actionError && <p role="alert" className="basis-full">Could not accept this request. Try again.</p>}
    </div>
  );
}

function Detail({ r, now, onClose }: { r: Referral; now: Date; onClose: () => void }) {
  const shared = useShared(r, now);
  const perform = useAct();
  const demo = useContext(DemoActions) !== null;
  const followUp = useFollowUp(r, demo, shared.active);
  const [station, setStation] = useState<Station>(r.station);
  const [outcome, setOutcome] = useState<string>(OUTCOMES[0]);
  const [eventCount, setEventCount] = useState(String(r.adverseEventCount ?? 0));
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  useEffect(() => { if (!demo && shared.active && shared.state === "ok") audit(r, "viewed_shared_data"); },
    [shared.state, shared.active, r.id, demo]);
  const dialogRef = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = dialogRef.current;
    const previousOverflow = document.body.style.overflow;
    dialog?.showModal();
    document.body.style.overflow = "hidden";
    return () => { dialog?.close(); document.body.style.overflow = previousOverflow; };
  }, []);

  const run = async (fn: () => Promise<void>, done: string) => {
    setBusy(true); setMsg(null);
    try { await fn(); setMsg(done); } catch { setMsg("That did not save. Check the connection and try again."); }
    finally { setBusy(false); }
  };
  const d = shared.data;
  const count = Number(eventCount);
  const validCount = eventCount !== "" && Number.isInteger(count) && count >= 0 && count <= 999;

  return (
    <dialog ref={dialogRef} className="referral-drawer" aria-label={`Referral for ${r.pseudonym}`}
      onCancel={e => { e.preventDefault(); onClose(); }}
      onClick={e => { if (e.target === e.currentTarget && e.clientX < e.currentTarget.getBoundingClientRect().left) onClose(); }}>
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 className="text-heading text-ink">{r.pseudonym}</h2>
            <p className="mt-1 text-small text-ink-muted">
              {r.kind === "urgent" ? "Urgent call-back request" : "Referral request"} · {r.createdAt.toLocaleString()}
            </p>
          </div>
          <button aria-label="Close" className="p-2 rounded-control hover:bg-surface-sunk" onClick={onClose}><X size={20} /></button>
        </div>

        <div className="mt-5 flex items-center gap-3"><StationChip s={r.station} /><span className="inline-flex items-center gap-2 text-small"><LineForm state={lineState(r, now)} />{handoffText(r, now)}</span></div>

        <section className="mt-6 rounded-panel border border-line p-4">
          <h3 className="text-caption uppercase text-ink-muted">Consent</h3>
          {consentActive(r, now) ? (
            <p className="mt-2 text-body">Shares {r.consent.streams.length ? r.consent.streams.map(s => STREAM_LABEL[s] ?? s).join(", ").toLowerCase() : "nothing"} until {r.consent.expiresAt.toLocaleDateString()}.</p>
          ) : (
            <p className="mt-2 text-body inline-flex items-center gap-2"><Lock size={16} />{r.consent.withdrawnAt ? `The person stopped sharing on ${r.consent.withdrawnAt.toLocaleDateString()}. Their data is no longer available.` : "Sharing has ended. Their data is no longer available."}</p>
          )}
        </section>

        {shared.active && d && (
          <div className="mt-6 grid gap-5">
            {d.contact && (
              <Block title="Contact">
                {demo ? <span className="font-data">{d.contact}</span> : <a className="font-data text-lead text-brand underline underline-offset-4" href={`tel:${d.contact.replace(/\s+/g, "")}`}>{d.contact}</a>}
              </Block>
            )}
            {d.check_in && (
              <Block title={`${d.check_in.instrument} check-in`}>
                <p className="text-lead">{d.check_in.band} · <span className="font-data">{d.check_in.total}/{d.check_in.max}</span></p>
                {d.check_in.worry !== undefined && <p className="text-small text-ink-muted mt-1">Worry <span className="font-data">{d.check_in.worry}/6</span> · mood <span className="font-data">{d.check_in.mood}/6</span> · {new Date(d.check_in.taken_at).toLocaleDateString()}</p>}
                {d.check_in.safety_answer && <p className="text-small mt-1">Safety question: <b>{d.check_in.safety_answer}</b></p>}
              </Block>
            )}
            {d.note && <Block title="In their words"><p className="text-body whitespace-pre-wrap max-w-[60ch]">{d.note}</p></Block>}
            {d.weekly_summary && (
              <Block title={`7-day summary${d.weekly_summary.synthetic ? " (synthetic demo data)" : ""}`}>
                <p className="text-body">{d.weekly_summary.summary}</p>
                <table className="mt-3 w-full text-small">
                  <thead><tr className="text-ink-muted text-left"><th className="py-1 font-semibold">Day</th>{Object.keys(SIGNAL_LABEL).map(k => <th key={k} className="py-1 font-semibold">{SIGNAL_LABEL[k]}</th>)}</tr></thead>
                  <tbody>
                    {d.weekly_summary.days.map(day => (
                      <tr key={day.date} className="border-t border-line">
                        <td className="py-1 font-data">{day.date.slice(5)}{day.shifted ? " •" : ""}</td>
                        {Object.keys(SIGNAL_LABEL).map(k => <td key={k} className="py-1 font-data">{day.z[k] === undefined ? "–" : `${day.z[k] > 0 ? "+" : ""}${day.z[k].toFixed(1)}σ`}</td>)}
                      </tr>
                    ))}
                  </tbody>
                </table>
                <p className="mt-2 text-small text-ink-muted">σ = distance from this person's own usual. • = day counted as shifted.</p>
              </Block>
            )}
          </div>
        )}
        {shared.active && shared.state === "loading" && <p className="mt-6 text-ink-muted">Loading what they shared…</p>}
        {followUp && (
          <div className="mt-6">
            <Block title="Referral follow-up">
              <p>Received support: {followUp.receivedSupport ? "Yes" : "No"}</p>
              {followUp.helpfulness && <p>Did it help? <span className="capitalize">{followUp.helpfulness}</span></p>}
              {followUp.phq4Total !== undefined && <p>Repeat PHQ-4: {followUp.phq4Total}/12</p>}
              {followUp.pss4Total !== undefined && <p>Repeat PSS-4: {followUp.pss4Total}/16</p>}
              <p className="mt-1 text-small text-ink-muted">Shared {followUp.submittedAt.toLocaleString()}</p>
            </Block>
          </div>
        )}

        <section className="mt-8 grid gap-4 border-t border-line pt-6">
          <h3 className="text-title text-ink">Your decision</h3>
          {r.status === "pending" && (
            <button disabled={busy || !consentActive(r, now)} className="min-h-touch rounded-control bg-brand text-brand-on font-bold disabled:bg-surface-sunk disabled:text-ink-muted shadow-brand"
              onClick={() => run(() => perform(r, { status: "accepted", acceptedAt: serverTimestamp() }, "accepted"), "Referral accepted.")}>
              Accept and contact them
            </button>
          )}
          {r.status !== "closed" && r.kind === "referral" && (
            <div className="flex gap-2 items-center flex-wrap">
              <label htmlFor="reroute" className="text-small font-semibold">Re-route to</label>
              <select id="reroute" value={station} onChange={e => setStation(e.target.value as Station)}
                className="min-h-touch rounded-control border border-line bg-ground px-3 text-ink">
                {(["community", "primaryCare", "teleMH", "specialist"] as Station[]).map(s => <option key={s} value={s}>{STATIONS[s].n} · {STATIONS[s].name}</option>)}
              </select>
              <button disabled={busy || !shared.active || station === r.station} className="min-h-touch rounded-control border-[1.5px] border-ink px-4 font-bold disabled:opacity-40"
                onClick={() => run(() => perform(r, { station }, "rerouted", `${r.station} -> ${station}`), "Re-routed.")}>Re-route</button>
            </div>
          )}
          {r.status !== "closed" && (
            <div className="flex gap-2 items-center flex-wrap">
              <label htmlFor="outcome" className="text-small font-semibold">Close with</label>
              <select id="outcome" value={outcome} onChange={e => setOutcome(e.target.value)}
                className="min-h-touch rounded-control border border-line bg-ground px-3 text-ink">
                {OUTCOMES.map(o => <option key={o}>{o}</option>)}
              </select>
              <button disabled={busy} className="min-h-touch rounded-control border-[1.5px] border-ink px-4 font-bold disabled:opacity-40"
                onClick={() => run(() => perform(r, { status: "closed", outcome, closedAt: serverTimestamp() }, "closed", outcome), "Closed with an outcome.")}>Close</button>
            </div>
          )}
          {shared.active && r.status !== "closed" && !r.firstContactAt && (
            <button disabled={busy} className="min-h-touch rounded-control border border-line px-4 font-semibold"
              onClick={() => run(() => perform(r, { firstContactAt: serverTimestamp() }, "first_contact"), "First contact recorded.")}>
              Record first contact
            </button>
          )}
          {r.firstContactAt && <p className="text-small">First contact recorded {r.firstContactAt.toLocaleString()}.</p>}
          {shared.active && (
            <div className="flex flex-wrap items-end gap-2">
              <label className="grid gap-1 text-small font-semibold">
                Recorded adverse events
                <input type="number" inputMode="numeric" min={0} max={999} step={1}
                  className="min-h-touch w-24 rounded-control border border-line bg-ground px-3"
                  value={eventCount} disabled={busy} onChange={e => setEventCount(e.target.value)} />
              </label>
              <button disabled={busy || !validCount || count === (r.adverseEventCount ?? 0)}
                className="min-h-touch rounded-control border border-line px-4 font-semibold disabled:opacity-50"
                onClick={() => run(() => perform(r, { adverseEventCount: count }, "adverse_event_count_updated", String(count)), "Adverse event count saved.")}>
                Save count
              </button>
            </div>
          )}
          {msg && <p className="text-small" role="status">{msg}</p>}
          <p className="text-small text-ink-muted">{demo ? "Changes to synthetic referrals last for this demo session." : "Views and decisions are recorded in this referral's audit log."}</p>
        </section>
    </dialog>
  );
}

function useFollowUp(r: Referral, demo: boolean, active: boolean) {
  const [data, setData] = useState<FollowUp | null>(null);
  useEffect(() => {
    if (demo || !active || r.kind === "urgent") return;
    return onSnapshot(doc(db, "referrals", r.id, "shared", "followUp"), snap => {
      if (snap.metadata.fromCache) return;
      const result = snap.exists() ? parseFollowUp(snap.data()) : null;
      setData(result);
      if (result) void audit(r, "viewed_follow_up");
    }, () => setData(null));
  }, [r.id, r.kind, demo, active]);
  if (!active) return null;
  return demo ? demoFollowUp(r) : data;
}

function Block({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h3 className="text-caption uppercase text-ink-muted mb-2">{title}</h3>
      {children}
    </section>
  );
}
