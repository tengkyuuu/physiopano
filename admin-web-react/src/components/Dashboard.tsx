import React, {
  useEffect, useState, useMemo, useCallback, useContext, createContext, useRef,
} from "react";
import {
  collection, getDocs, onSnapshot, query, orderBy, Timestamp,
  doc, getDoc,
} from "firebase/firestore";
import { signOut } from "firebase/auth";
import { db, auth } from "../firebase";
import {
  AreaChart, Area, LineChart, Line, BarChart, Bar,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  Legend, PieChart, Pie, Cell, ReferenceLine,
} from "recharts";
import {
  Chart as ChartJS, CategoryScale, LinearScale, PointElement, LineElement,
  BarElement, Title, Tooltip as ChartTooltip, Legend as ChartLegend, Filler,
} from "chart.js";
import ZoomPlugin from "chartjs-plugin-zoom";
import { Line as CJSLine, Bar as CJSBar } from "react-chartjs-2";
import {
  LayoutDashboard, Users, ClipboardList, BarChart2,
  Download, LogOut, HeartPulse, Brain, Thermometer,
  Zap, Activity, ChevronDown, ChevronUp, Search,
  RefreshCw, AlertCircle, CheckCircle2, Clock, User, Sun, Moon,
  TrendingUp, TrendingDown, Minus, HeartHandshake,
} from "lucide-react";
import { CareQueue } from "./CareQueue";
import { Outcomes } from "./Outcomes";
import { demoReferrals } from "../lib/demoReferrals";
import type { Referral } from "../lib/referrals";
import { ConsoleBrand } from "./ConsoleBrand";
import { ChevronRight, Menu, X, FlaskConical, ShieldCheck, Inbox } from "lucide-react";

// ── Register Chart.js + Zoom ───────────────────────────────────────────────────
ChartJS.register(
  CategoryScale, LinearScale, PointElement, LineElement,
  BarElement, Title, ChartTooltip, ChartLegend, Filler, ZoomPlugin,
);

// ── Types ─────────────────────────────────────────────────────────────────────
interface Participant {
  id: string;
  name: string;
  studentId: string;
  course: string;
  yearLevel: string;
  sex: string;
  age: number;
  email: string;
  onboardingComplete: boolean;
  createdAt: Date | null;
}

interface Session {
  id: string;
  participantId: string;
  startTime: Date;
  endTime: Date | null;
  snapshotCount: number;
  tags: string[];
  avgStress: number;
  avgHr: number;
  avgHrv: number;
  avgGsr: number;
  avgTemp: number;
  avgAccelMag: number;
  notes: string;
}

interface Baseline {
  hrMean: number; hrStd: number;
  hrvMean: number; hrvStd: number;
  gsrMean: number; gsrStd: number;
  tempMean: number; tempStd: number;
  accelMean: number; accelStd: number;
  sampleCount: number;
  calibratedAt: Date | null;
}

type TabId = "care" | "outcomes" | "overview" | "participants" | "sessions" | "analytics" | "export";

// ── Theme Context ─────────────────────────────────────────────────────────────
interface Theme {
  dark: boolean;
  bg: string;
  surface: string;
  card: string;
  border: string;
  text: string;
  textSub: string;
  textDim: string;
  inputBg: string;
  hoverBg: string;
  gridColor: string;
  tooltipBg: string;
  tooltipBorder: string;
}

const ThemeCtx = createContext<{ theme: Theme; toggle: () => void }>({
  theme: darkTheme(),
  toggle: () => {},
});

function darkTheme(): Theme {
  return {
    dark: true,
    bg: "#16191E", surface: "#16191E", card: "#1D2128",
    border: "#2B3039", text: "#F1EEE7", textSub: "#A4ABB6",
    textDim: "#8A92A0", inputBg: "#14171B", hoverBg: "rgba(232,237,234,0.04)",
    gridColor: "#2B3039", tooltipBg: "#1D2128", tooltipBorder: "#2B3039",
  };
}

function lightTheme(): Theme {
  return {
    dark: false,
    bg: "#F4F1EA", surface: "#F4F1EA", card: "#F3F0EA",
    border: "#E2DED5", text: "#242A32", textSub: "#505966",
    textDim: "#505966", inputBg: "#EDEEF0", hoverBg: "rgba(16,32,31,0.04)",
    gridColor: "#E2DED5", tooltipBg: "#F3F0EA", tooltipBorder: "#E2DED5",
  };
}

// ── Palette ───────────────────────────────────────────────────────────────────
const C = {
  // Series colours: mid-tones legible on both grounds. Levels are ONE hue (no traffic lights).
  stress: "#0758E8", hr: "#6E9BF0", hrv: "#6D5BD0",
  gsr: "#C98A1B", temp: "#5B6678", accel: "#646D7A",
  low: "#8FB2FA", mod: "#0758E8", high: "#0546BA", accent: "#0758E8",
};

// ── Helpers ───────────────────────────────────────────────────────────────────
const fmtDate = (d: Date) =>
  d.toLocaleDateString("en-PH", { month: "short", day: "numeric", year: "numeric" });

const fmtTime = (d: Date) =>
  d.toLocaleTimeString("en-PH", { hour: "2-digit", minute: "2-digit" });

const fmtDuration = (start: Date, end: Date | null) => {
  if (!end) return "—";
  const secs = Math.round((end.getTime() - start.getTime()) / 1000);
  const m = Math.floor(secs / 60), s = secs % 60;
  return `${m}m ${s}s`;
};

const stressColor = (v: number) => v >= 75 ? C.high : v >= 25 ? C.mod : C.low;
const stressLabel = (v: number) => v >= 75 ? "High" : v >= 25 ? "Moderate" : "Low";

const toDate = (val: unknown): Date | null => {
  if (!val) return null;
  if (val instanceof Date) return val;
  if (val instanceof Timestamp) return val.toDate();
  if (typeof val === "number") return new Date(val);
  return null;
};

const num = (v: unknown, fallback = 0): number => {
  const n = Number(v);
  return isNaN(n) ? fallback : n;
};

const fmt = (v: number, decimals = 1, unit = "", zero = "—") =>
  v === 0 ? zero : v.toFixed(decimals) + (unit ? " " + unit : "");

// ── CSV export ────────────────────────────────────────────────────────────────
function downloadCSV(filename: string, headers: string[], rows: string[][]) {
  const csv = [headers, ...rows].map(r => r.map(c => `"${c}"`).join(",")).join("\n");
  const url = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
  const a = document.createElement("a"); a.href = url; a.download = filename; a.click();
  URL.revokeObjectURL(url);
}

// ── Zoom Chart Components (Chart.js) ──────────────────────────────────────────
function ZoomLineChart({
  labels, datasets, yLabel, height = 220, yMin, yMax, refLines = [],
}: {
  labels: string[];
  datasets: { label: string; data: (number | null)[]; color: string }[];
  yLabel?: string;
  height?: number;
  yMin?: number;
  yMax?: number;
  refLines?: { value: number; color: string; label: string }[];
}) {
  const { theme } = useContext(ThemeCtx);
  const chartRef = useRef<ChartJS<"line"> | null>(null);

  const annotations: Record<string, object> = {};
  refLines.forEach((r, i) => {
    annotations[`ref${i}`] = {
      type: "line",
      yMin: r.value, yMax: r.value,
      borderColor: r.color, borderWidth: 1.5,
      borderDash: [5, 5],
      label: {
        display: true, content: r.label, color: r.color, font: { size: 10 },
        position: "end",
      },
    };
  });

  const options: Parameters<typeof CJSLine>[0]["options"] = {
    responsive: true,
    maintainAspectRatio: false,
    animation: false,
    plugins: {
      legend: {
        labels: { color: theme.textSub, boxWidth: 12, font: { size: 11 } },
      },
      tooltip: {
        backgroundColor: theme.tooltipBg,
        borderColor: theme.tooltipBorder,
        borderWidth: 1,
        titleColor: theme.text,
        bodyColor: theme.textSub,
      },
      zoom: {
        pan: { enabled: true, mode: "x" },
        zoom: {
          wheel: { enabled: true },
          pinch: { enabled: true },
          mode: "x",
        },
      },
      // @ts-expect-error annotation plugin not typed here
      annotation: { annotations },
    },
    scales: {
      x: {
        ticks: { color: theme.textDim, font: { size: 10 }, maxTicksLimit: 10 },
        grid: { color: theme.gridColor + "55" },
      },
      y: {
        ticks: { color: theme.textDim, font: { size: 10 } },
        grid: { color: theme.gridColor + "55" },
        title: yLabel ? { display: true, text: yLabel, color: theme.textDim, font: { size: 10 } } : undefined,
        min: yMin, max: yMax,
      },
    },
  };

  const data = {
    labels,
    datasets: datasets.map(d => ({
      label: d.label,
      data: d.data,
      borderColor: d.color,
      backgroundColor: d.color + "22",
      borderWidth: 2,
      pointRadius: labels.length < 20 ? 3 : 1.5,
      pointBackgroundColor: d.color,
      tension: 0.3,
      fill: datasets.length === 1,
    })),
  };

  return (
    <div style={{ position: "relative", height }}>
      <CJSLine ref={chartRef} data={data} options={options} />
      <button
        onClick={() => chartRef.current?.resetZoom()}
        className="absolute top-0 right-0 text-[10px] px-2 py-0.5 rounded"
        style={{ background: theme.border, color: theme.textSub }}
      >
        Reset zoom
      </button>
    </div>
  );
}

function ZoomBarChart({
  labels, dataValues, color, yLabel, height = 220,
}: {
  labels: string[];
  dataValues: number[];
  color: string;
  yLabel?: string;
  height?: number;
}) {
  const { theme } = useContext(ThemeCtx);
  const chartRef = useRef<ChartJS<"bar"> | null>(null);

  const options: Parameters<typeof CJSBar>[0]["options"] = {
    responsive: true,
    maintainAspectRatio: false,
    animation: false,
    plugins: {
      legend: { display: false },
      tooltip: {
        backgroundColor: theme.tooltipBg,
        borderColor: theme.tooltipBorder,
        borderWidth: 1,
        titleColor: theme.text,
        bodyColor: theme.textSub,
      },
      zoom: {
        pan: { enabled: true, mode: "x" },
        zoom: { wheel: { enabled: true }, pinch: { enabled: true }, mode: "x" },
      },
    },
    scales: {
      x: {
        ticks: { color: theme.textDim, font: { size: 10 }, maxTicksLimit: 14 },
        grid: { display: false },
      },
      y: {
        ticks: { color: theme.textDim, font: { size: 10 } },
        grid: { color: theme.gridColor + "55" },
        title: yLabel ? { display: true, text: yLabel, color: theme.textDim, font: { size: 10 } } : undefined,
      },
    },
  };

  const data = {
    labels,
    datasets: [{ label: yLabel ?? "", data: dataValues, backgroundColor: color + "cc", borderRadius: 4 }],
  };

  return (
    <div style={{ position: "relative", height }}>
      <CJSBar ref={chartRef} data={data} options={options} />
      <button
        onClick={() => chartRef.current?.resetZoom()}
        className="absolute top-0 right-0 text-[10px] px-2 py-0.5 rounded"
        style={{ background: theme.border, color: theme.textSub }}
      >
        Reset zoom
      </button>
    </div>
  );
}

// ── Main Dashboard ─────────────────────────────────────────────────────────────
export function Dashboard({ canViewResearch = false, previewOnly = false, onExitPreview }: {
  canViewResearch?: boolean; previewOnly?: boolean; onExitPreview?: () => void;
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  // Care console defaults to light (desk, daylight); the toggle also drives the token theme.
  const [isDark, setIsDark] = useState(false);
  const theme = isDark ? darkTheme() : lightTheme();
  useEffect(() => {
    document.documentElement.dataset.theme = isDark ? "dark" : "light";
    return () => { delete document.documentElement.dataset.theme; };
  }, [isDark]);

  const [activeTab, setActiveTab] = useState<TabId>("care");
  const [demoItems, setDemoItems] = useState<Referral[] | null>(() => previewOnly ? demoReferrals() : null);
  const careTab = activeTab === "care" || activeTab === "outcomes";
  const [participants, setParticipants] = useState<Participant[]>([]);
  const [sessionMap, setSessionMap] = useState<Record<string, Session[]>>({});
  const [selectedPid, setSelectedPid] = useState<string | null>(null);
  const [loadingUsers, setLoadingUsers] = useState(true);
  const [loadingSessions, setLoadingSessions] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const [baselineMap, setBaselineMap] = useState<Record<string, Baseline>>({});

  // ── Fetch participants ──────────────────────────────────────────────────────
  useEffect(() => {
    if (!canViewResearch) return;
    setLoadingUsers(true);
    getDocs(collection(db, "users"))
      .then(snap => {
        const list: Participant[] = snap.docs.map(doc => {
          const d = doc.data();
          return {
            id: doc.id,
            name: d.display_name || d.displayName || d.name || "Unknown",
            studentId: d.student_id || d.studentId || "—",
            course: d.course || "—",
            yearLevel: d.year_level || d.yearLevel || "—",
            sex: d.sex || d.gender || "—",
            age: num(d.age),
            email: d.email || "",
            onboardingComplete: d.onboarding_complete ?? d.onboardingComplete ?? false,
            createdAt: toDate(d.created_at ?? d.createdAt),
          };
        });
        setParticipants(list);
        if (list.length > 0) setSelectedPid(list[0].id);
      })
      .catch(() => setParticipants([]))
      .finally(() => setLoadingUsers(false));
  }, [refreshKey, canViewResearch]);

  // ── Fetch sessions ──────────────────────────────────────────────────────────
  useEffect(() => {
    if (participants.length === 0) return;
    setLoadingSessions(true);
    const unsubs: (() => void)[] = [];
    let pending = participants.length;

    participants.forEach(p => {
      const q = query(
        collection(db, "users", p.id, "sessions"),
        orderBy("start_time", "asc"),
      );
      const unsub = onSnapshot(q, snap => {
        const sess: Session[] = snap.docs.map(doc => {
          const d = doc.data();
          return {
            id: doc.id,
            participantId: p.id,
            startTime: toDate(d.start_time ?? d.startTime) ?? new Date(),
            endTime: toDate(d.end_time ?? d.endTime),
            snapshotCount: num(d.snapshot_count ?? d.snapshotCount),
            tags: Array.isArray(d.tags) ? d.tags : [],
            // Try multiple field name variants
            avgStress: num(d.avg_stress_index ?? d.avg_stress ?? d.avgStress ?? d.avgStressIndex),
            avgHr: num(d.avg_hr ?? d.avgHr ?? d.avg_heart_rate),
            avgHrv: num(d.avg_hrv ?? d.avgHrv ?? d.avg_rmssd),
            // GSR tries eda, gsr, skin_conductance
            avgGsr: num(d.avg_gsr ?? d.avg_eda ?? d.avgGsr ?? d.avgEda ?? d.avg_skin_conductance),
            // Temp tries multiple names
            avgTemp: num(d.avg_temp ?? d.avgTemp ?? d.avg_temperature ?? d.avg_skin_temp),
            // Motion tries accel_mag, motion, acceleration
            avgAccelMag: num(d.avg_accel_mag ?? d.avgAccelMag ?? d.avg_accel ?? d.avg_motion ?? d.avg_acceleration),
            notes: String(d.notes ?? ""),
          };
        });
        setSessionMap(prev => ({ ...prev, [p.id]: sess }));
        if (pending > 0) { pending--; if (pending === 0) setLoadingSessions(false); }
      }, () => {
        if (pending > 0) { pending--; if (pending === 0) setLoadingSessions(false); }
      });
      unsubs.push(unsub);
    });

    return () => unsubs.forEach(u => u());
  }, [participants]);

  // ── Fetch baseline calibration per participant ──────────────────────────────
  useEffect(() => {
    if (participants.length === 0) return;
    participants.forEach(p => {
      getDoc(doc(db, "users", p.id, "baseline", "current"))
        .then(snap => {
          if (!snap.exists()) return;
          const d = snap.data();
          setBaselineMap(prev => ({
            ...prev,
            [p.id]: {
              hrMean: num(d.hr_mean), hrStd: num(d.hr_std),
              hrvMean: num(d.hrv_mean), hrvStd: num(d.hrv_std),
              gsrMean: num(d.gsr_mean), gsrStd: num(d.gsr_std),
              tempMean: num(d.temp_mean), tempStd: num(d.temp_std),
              accelMean: num(d.accmag_mean ?? d.accel_mean), accelStd: num(d.accmag_std ?? d.accel_std),
              sampleCount: num(d.sample_count),
              calibratedAt: toDate(d.calibrated_at),
            },
          }));
        })
        .catch(() => {});
    });
  }, [participants]);

  const allSessions = useMemo(() => Object.values(sessionMap).flat(), [sessionMap]);

  const selectedSessions = useMemo(
    () => (selectedPid ? sessionMap[selectedPid] ?? [] : []),
    [selectedPid, sessionMap],
  );

  const participantsWithStats = useMemo(() =>
    participants.map(p => ({
      ...p,
      sessionCount: (sessionMap[p.id] ?? []).length,
      avgStress: (() => {
        const ss = sessionMap[p.id] ?? [];
        if (!ss.length) return null;
        return ss.reduce((a, s) => a + s.avgStress, 0) / ss.length;
      })(),
    })),
  [participants, sessionMap]);

  const nav: { id: TabId; label: string; icon: React.ReactNode }[] = [
    { id: "care",         label: "Care queue",    icon: <HeartHandshake size={18} /> },
    { id: "outcomes",     label: "Outcomes",      icon: <Activity size={18} /> },
    { id: "overview",     label: "Overview",      icon: <LayoutDashboard size={18} /> },
    { id: "participants", label: "Participants",   icon: <Users size={18} /> },
    { id: "sessions",     label: "Session data",  icon: <ClipboardList size={18} /> },
    { id: "analytics",    label: "Analytics",     icon: <BarChart2 size={18} /> },
    { id: "export",       label: "Export",        icon: <Download size={18} /> },
  ];
  const allowedNav = canViewResearch ? nav : nav.filter(item => item.id === "care" || item.id === "outcomes");

  const isLoading = loadingUsers || loadingSessions;
  const current = nav.find(item => item.id === activeTab)!;
  const role = previewOnly ? "Demo workspace" : canViewResearch ? "Research administrator" : "Care navigator";
  const researchIntro: Partial<Record<TabId, string>> = {
    overview: "Participation, recorded sessions, and recent activity.",
    participants: "Find a participant and open their recorded sessions.",
    sessions: "Review a participant’s recorded signals and session details.",
    analytics: "Explore measurements and patterns across recorded sessions.",
    export: "Download research records for further analysis.",
  };
  function navigate(tab: TabId) {
    setActiveTab(tab);
    setMenuOpen(false);
    window.scrollTo(0, 0);
  }
  function navSection(title: string, items: typeof nav) {
    if (!items.length) return null;
    return <div className="rail-section"><p>{title}</p>{items.map(n =>
      <button key={n.id} aria-current={activeTab === n.id ? "page" : undefined} onClick={() => navigate(n.id)}>
        {n.icon}<span>{n.label}</span>{activeTab === n.id && <i/>}
      </button>)}</div>;
  }

  return (
    <ThemeCtx.Provider value={{ theme, toggle: () => setIsDark(d => !d) }}>
      <div className="desk-shell">
        <a className="desk-skip" href="#workspace-content" onClick={e => { e.preventDefault(); document.getElementById("workspace-content")?.focus(); }}>Skip to workspace</a>
        <aside className="desk-rail">
          <div className="rail-head"><ConsoleBrand /><button className="mobile-menu" aria-label={menuOpen ? "Close navigation" : "Open navigation"} aria-expanded={menuOpen} aria-controls="workspace-nav" onClick={() => setMenuOpen(!menuOpen)}>{menuOpen ? <X size={20}/> : <Menu size={20}/>}</button></div>
          <div id="workspace-nav" className={"rail-body" + (menuOpen ? " is-open" : "")}>
            <nav aria-label="Workspace navigation">
              {navSection("Care navigation", allowedNav.slice(0, 2))}
              {navSection("Research", allowedNav.slice(2))}
            </nav>
            <div className="rail-footer"><span><ShieldCheck size={17}/>{role}</span>
              {canViewResearch && <button onClick={() => setRefreshKey(k => k + 1)}><RefreshCw size={16}/>Refresh research data</button>}
              <button onClick={previewOnly ? onExitPreview : () => signOut(auth)}><LogOut size={16}/>{previewOnly ? "Leave demo" : "Sign out"}</button>
            </div>
          </div>
        </aside>
        <main id="workspace-content" tabIndex={-1} className="desk-main">
          <div className="desk-top"><div className="desk-crumb"><span>Workspace</span><ChevronRight size={14}/><strong>{current.label}</strong></div>
            <div className="desk-tools">{careTab && (previewOnly
              ? <span className="demo-badge"><FlaskConical size={14}/>Synthetic demo</span>
              : <button aria-pressed={demoItems !== null} onClick={() => setDemoItems(items => items ? null : demoReferrals())}><FlaskConical size={15}/>{demoItems ? "Exit synthetic demo" : "Load synthetic demo"}</button>)}
              <button className="theme-switch" aria-label={isDark ? "Switch to light theme" : "Switch to dark theme"} onClick={() => setIsDark(!isDark)}>{isDark ? <Sun size={17}/> : <Moon size={17}/>}</button>
            </div>
          </div>
          <div className="desk-content">
            {careTab && demoItems && <p className="demo-note"><span/>Demo changes stay in this session</p>}
            {!careTab && <header className="desk-page-head"><p className="desk-kicker">Research workspace</p><h1>{current.label}</h1>
              <p>{researchIntro[activeTab]}</p><small role="status">{isLoading ? "Loading research data…" : `${participants.length} participant${participants.length === 1 ? "" : "s"} · ${allSessions.length} session${allSessions.length === 1 ? "" : "s"}`}</small></header>}
            {activeTab === "care"         && <CareQueue key={demoItems ? "demo" : "live"} demoItems={demoItems} setDemoItems={setDemoItems} />}
            {activeTab === "outcomes"     && <Outcomes demoItems={demoItems} />}
            {activeTab === "overview"     && <OverviewTab participants={participantsWithStats} allSessions={allSessions} />}
            {activeTab === "participants" && <ParticipantsTab participants={participantsWithStats} onSelect={pid => { setSelectedPid(pid); setActiveTab("sessions"); }} />}
            {activeTab === "sessions"     && <SessionsTab participants={participants} selectedPid={selectedPid} sessions={selectedSessions} onSelect={setSelectedPid} baseline={selectedPid ? baselineMap[selectedPid] : undefined} />}
            {activeTab === "analytics"    && <AnalyticsTab participants={participantsWithStats} allSessions={allSessions} sessionMap={sessionMap} />}
            {activeTab === "export"       && <ExportTab participants={participantsWithStats} allSessions={allSessions} />}
          </div>
        </main>
      </div>
    </ThemeCtx.Provider>
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 1 — OVERVIEW
// ═════════════════════════════════════════════════════════════════════════════
function OverviewTab({ participants, allSessions }: {
  participants: (Participant & { sessionCount: number; avgStress: number | null })[];
  allSessions: Session[];
}) {
  const { theme } = useContext(ThemeCtx);
  const totalParticipants = participants.length;
  const totalSessions     = allSessions.length;
  const totalSamples      = allSessions.reduce((a, s) => a + s.snapshotCount, 0);
  const avgStressAll      = allSessions.length
    ? allSessions.reduce((a, s) => a + s.avgStress, 0) / allSessions.length : 0;

  const stressDist = useMemo(() => {
    let low = 0, mod = 0, high = 0;
    allSessions.forEach(s => {
      if (s.avgStress >= 75) high++;
      else if (s.avgStress >= 25) mod++;
      else low++;
    });
    return [
      { name: "Low (0–24)", value: low, color: C.low },
      { name: "Moderate (25–74)", value: mod, color: C.mod },
      { name: "High (75–100)", value: high, color: C.high },
    ];
  }, [allSessions]);

  const sessionsPerDay = useMemo(() => {
    const map: Record<string, number> = {};
    const now = new Date();
    for (let i = 13; i >= 0; i--) {
      const d = new Date(now); d.setDate(d.getDate() - i);
      map[d.toDateString()] = 0;
    }
    allSessions.forEach(s => {
      const k = s.startTime.toDateString();
      if (k in map) map[k]++;
    });
    return Object.entries(map).map(([k, v]) => ({
      date: new Date(k).toLocaleDateString("en-PH", { month: "short", day: "numeric" }),
      sessions: v,
    }));
  }, [allSessions]);

  const recent = useMemo(
    () => [...allSessions].sort((a, b) => b.startTime.getTime() - a.startTime.getTime()).slice(0, 8),
    [allSessions],
  );

  const tt: React.CSSProperties = { backgroundColor: theme.tooltipBg, border: `1px solid ${theme.tooltipBorder}`, borderRadius: 10, fontSize: 12, color: theme.text };

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard icon={<Users size={18} />}       label="Participants"     value={totalParticipants.toString()} color="green" />
        <StatCard icon={<ClipboardList size={18} />} label="Total Sessions" value={totalSessions.toString()} color="blue" />
        <StatCard icon={<Activity size={18} />}    label="Total Samples"    value={totalSamples.toLocaleString()} color="purple" />
        <StatCard icon={<Brain size={18} />}       label="Avg Stress Index" value={avgStressAll.toFixed(1)}
          color={avgStressAll >= 75 ? "red" : avgStressAll >= 25 ? "amber" : "green"} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <Card title="Stress Distribution" icon={<Activity size={15} />}>
          {allSessions.length === 0 ? <NoData /> : (
            <>
              <ResponsiveContainer width="100%" height={200}>
                <PieChart>
                  <Pie data={stressDist} dataKey="value" cx="50%" cy="50%" outerRadius={75} innerRadius={40} paddingAngle={3}>
                    {stressDist.map((e, i) => <Cell key={i} fill={e.color} />)}
                  </Pie>
                  <Tooltip formatter={(v: number) => [v + " sessions"]} contentStyle={tt} />
                </PieChart>
              </ResponsiveContainer>
              <div className="flex justify-center gap-4 mt-2 flex-wrap">
                {stressDist.map(e => (
                  <div key={e.name} className="flex items-center gap-1.5 text-xs" style={{ color: theme.textSub }}>
                    <span className="w-2.5 h-2.5 rounded-full" style={{ background: e.color }} />
                    {e.name} ({e.value})
                  </div>
                ))}
              </div>
            </>
          )}
        </Card>

        <Card title="Sessions (14 days)" icon={<BarChart2 size={15} />} className="lg:col-span-2">
          {allSessions.length === 0 ? <NoData /> : (
            <ZoomBarChart
              labels={sessionsPerDay.map(d => d.date)}
              dataValues={sessionsPerDay.map(d => d.sessions)}
              color={C.accent}
              yLabel="Sessions"
              height={220}
            />
          )}
        </Card>
      </div>

      <Card title="Recent Sessions" icon={<Clock size={15} />}>
        {recent.length === 0 ? <NoData /> : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-xs" style={{ borderBottom: `1px solid ${theme.border}`, color: theme.textDim }}>
                  <Th>Date & Time</Th><Th>Participant</Th><Th>Samples</Th>
                  <Th align="right">Stress</Th><Th align="right">HR</Th>
                  <Th align="right">HRV</Th><Th align="right">GSR</Th>
                  <Th align="right">Temp</Th><Th align="right">Motion</Th>
                </tr>
              </thead>
              <tbody>
                {recent.map(s => {
                  const p = participants.find(x => x.id === s.participantId);
                  return (
                    <tr key={s.id} style={{ borderBottom: `1px solid ${theme.border}40` }}>
                      <Td>{fmtDate(s.startTime)} {fmtTime(s.startTime)}</Td>
                      <Td>{p?.name ?? "—"}</Td>
                      <Td>{s.snapshotCount || "—"}</Td>
                      <Td align="right"><StressBadge v={s.avgStress} /></Td>
                      <Td align="right" color={C.hr}>{fmt(s.avgHr, 0, "bpm")}</Td>
                      <Td align="right" color={C.hrv}>{fmt(s.avgHrv, 1, "ms")}</Td>
                      <Td align="right" color={C.gsr}>{fmt(s.avgGsr, 3, "µS")}</Td>
                      <Td align="right" color={C.temp}>{fmt(s.avgTemp, 1, "°C")}</Td>
                      <Td align="right" color={C.accel}>{fmt(s.avgAccelMag, 3, "g")}</Td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 2 — PARTICIPANTS
// ═════════════════════════════════════════════════════════════════════════════
function ParticipantsTab({ participants, onSelect }: {
  participants: (Participant & { sessionCount: number; avgStress: number | null })[];
  onSelect: (pid: string) => void;
}) {
  const { theme } = useContext(ThemeCtx);
  const [search, setSearch] = useState("");

  const filtered = useMemo(() =>
    participants.filter(p =>
      [p.name, p.studentId, p.course, p.email].some(f =>
        f.toLowerCase().includes(search.toLowerCase()),
      ),
    ),
  [participants, search]);

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard icon={<Users size={18} />}       label="Total Enrolled"  value={participants.length.toString()} color="green" />
        <StatCard icon={<CheckCircle2 size={18} />} label="Onboarding Done" value={participants.filter(p => p.onboardingComplete).length.toString()} color="blue" />
        <StatCard icon={<User size={18} />}        label="Male"            value={participants.filter(p => p.sex === "Male").length.toString()} color="purple" />
        <StatCard icon={<User size={18} />}        label="Female"          value={participants.filter(p => p.sex === "Female").length.toString()} color="amber" />
      </div>

      <div className="relative">
        <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2" style={{ color: theme.textDim }} />
        <input
          className="w-full rounded-control pl-9 pr-4 py-2.5 text-sm focus:outline-none"
          style={{ backgroundColor: theme.inputBg, border: `1px solid ${theme.border}`, color: theme.text }}
          aria-label="Search participants"
          placeholder="Search by name, student ID, course, email…"
          value={search}
          onChange={e => setSearch(e.target.value)}
        />
      </div>

      <Card title={`Participants (${filtered.length})`} icon={<Users size={15} />}>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-xs" style={{ borderBottom: `1px solid ${theme.border}`, color: theme.textDim }}>
                <Th>Name</Th><Th>Student ID</Th><Th>Course</Th><Th>Year</Th>
                <Th>Sex</Th><Th>Age</Th><Th align="right">Sessions</Th>
                <Th align="right">Avg Stress</Th><Th>Status</Th><Th>Action</Th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 && (
                <tr><td colSpan={10} className="py-8 text-center text-sm" style={{ color: theme.textDim }}>No participants found</td></tr>
              )}
              {filtered.map(p => (
                <tr key={p.id} style={{ borderBottom: `1px solid ${theme.border}40` }}>
                  <Td>
                    <div className="font-medium" style={{ color: theme.text }}>{p.name}</div>
                    <div className="text-[10px]" style={{ color: theme.textDim }}>{p.email}</div>
                  </Td>
                  <Td>{p.studentId}</Td>
                  <Td><span className="text-xs">{p.course}</span></Td>
                  <Td>{p.yearLevel}</Td>
                  <Td>{p.sex}</Td>
                  <Td>{p.age > 0 ? p.age : "—"}</Td>
                  <Td align="right">{p.sessionCount}</Td>
                  <Td align="right">
                    {p.avgStress !== null
                      ? <StressBadge v={p.avgStress} />
                      : <span className="text-xs" style={{ color: theme.textDim }}>—</span>
                    }
                  </Td>
                  <Td>
                    <span className="text-[10px] px-2 py-0.5 rounded-full"
                      style={p.onboardingComplete
                        ? { background: "#0758E818", color: "#0758E8" }
                        : { background: theme.border, color: theme.textDim }
                      }
                    >
                      {p.onboardingComplete ? "Active" : "Pending"}
                    </span>
                  </Td>
                  <Td>
                    <button onClick={() => onSelect(p.id)} className="text-xs hover:underline" style={{ color: "#0758E8" }}>
                      View sessions →
                    </button>
                  </Td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 3 — SESSION DATA (Chart.js with zoom)
// ═════════════════════════════════════════════════════════════════════════════
interface PerMinReading {
  timestamp: Date;
  label: string;
  avgHr: number | null;
  avgHrv: number | null;
  avgStress: number | null;
  avgGsr: number | null;
  avgTemp: number | null;
  avgAccelMag: number | null;
}

function SessionsTab({ participants, selectedPid, sessions, onSelect, baseline }: {
  participants: Participant[];
  selectedPid: string | null;
  sessions: Session[];
  onSelect: (pid: string) => void;
  baseline?: Baseline;
}) {
  const { theme } = useContext(ThemeCtx);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [perMin, setPerMin] = useState<PerMinReading[]>([]);
  const [loadingPerMin, setLoadingPerMin] = useState(false);

  // ── Fetch per-minute readings from readings/ subcollection ─────────────────
  useEffect(() => {
    if (!selectedPid || sessions.length === 0) { setPerMin([]); return; }
    setLoadingPerMin(true);
    Promise.all(
      sessions.map(session =>
        getDocs(query(
          collection(db, "users", selectedPid, "sessions", session.id, "readings"),
          orderBy("timestamp", "asc"),
        )).then(snap =>
          snap.docs.map(doc => {
            const d = doc.data();
            const ts = toDate(d.timestamp) ?? session.startTime;
            const v = (x: unknown) => {
              const n = num(x); return n > 0 ? n : null;
            };
            return {
              timestamp: ts,
              label: fmtDate(session.startTime) + " " + fmtTime(ts),
              avgHr:      v(d.avg_hr),
              avgHrv:     v(d.avg_hrv_rmssd ?? d.avg_hrv),
              avgStress:  v(d.avg_stress),
              avgGsr:     v(d.avg_gsr ?? d.gsr_us),
              avgTemp:    v(d.avg_temp ?? d.temp_skin),
              avgAccelMag: v(d.avg_accel_mag ?? d.avg_motion),
            } as PerMinReading;
          })
        ).catch(() => [] as PerMinReading[])
      )
    ).then(results => {
      const all = results.flat().sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
      setPerMin(all);
    }).finally(() => setLoadingPerMin(false));
  }, [selectedPid, sessions]);

  const sorted = useMemo(
    () => [...sessions].sort((a, b) => b.startTime.getTime() - a.startTime.getTime()),
    [sessions],
  );

  // Session-level averages (treat ≤ 0 as no data → null)
  const chartData = useMemo(() =>
    [...sessions]
      .sort((a, b) => a.startTime.getTime() - b.startTime.getTime())
      .map(s => ({
        label: fmtDate(s.startTime),
        stress: s.avgStress > 0 ? +s.avgStress.toFixed(1) : null,
        hr:     s.avgHr > 0     ? +s.avgHr.toFixed(1)     : null,
        hrv:    s.avgHrv > 0    ? +s.avgHrv.toFixed(1)    : null,
        gsr:    s.avgGsr > 0    ? +s.avgGsr.toFixed(3)    : null,
        temp:   s.avgTemp > 20  ? +s.avgTemp.toFixed(1)   : null,
        accel:  s.avgAccelMag > 0 ? +s.avgAccelMag.toFixed(3) : null,
      })),
  [sessions]);

  const sessLabels = chartData.map(d => d.label);
  const pmLabels   = perMin.map(r => r.label);
  const participant = participants.find(p => p.id === selectedPid);

  // Has any real data in session-level vs per-minute
  const hasSessionGsr  = chartData.some(d => d.gsr !== null);
  const hasSessionTemp = chartData.some(d => d.temp !== null);
  const hasSessionAccel = chartData.some(d => d.accel !== null);
  const hasPerMinGsr   = perMin.some(r => r.avgGsr !== null);
  const hasPerMinTemp  = perMin.some(r => r.avgTemp !== null);
  const hasPerMinAccel = perMin.some(r => r.avgAccelMag !== null);

  return (
    <div className="space-y-6">
      {/* Participant selector */}
      <div className="flex items-center gap-3 flex-wrap">
        <User size={15} style={{ color: theme.textDim }} />
        <select
          className="rounded-control px-4 py-2 text-sm focus:outline-none min-w-[260px]"
          style={{ backgroundColor: theme.inputBg, border: `1px solid ${theme.border}`, color: theme.text }}
          aria-label="Select participant"
          value={selectedPid ?? ""}
          onChange={e => onSelect(e.target.value)}
        >
          {participants.map(p => (
            <option key={p.id} value={p.id}>{p.name} ({p.studentId})</option>
          ))}
        </select>
        {participant && (
          <div className="flex gap-3 text-xs" style={{ color: theme.textDim }}>
            <span>{participant.course}</span>
            <span>·</span><span>{participant.yearLevel}</span>
            <span>·</span><span>{participant.sex}</span>
            {participant.age > 0 && <><span>·</span><span>{participant.age} yrs</span></>}
          </div>
        )}
        <p className="text-xs ml-auto" style={{ color: theme.textDim }}>
          Scroll to zoom · Drag to pan
        </p>
      </div>

      {/* ── Baseline signal status panel ────────────────────────────────── */}
      {sessions.length > 0 && (
        <SignalStatusPanel baseline={baseline} sessions={sessions} />
      )}

      {sessions.length === 0 ? (
        <Card title="No sessions yet"><NoData /></Card>
      ) : (
        <>
          {/* ── Per-session averages ─────────────────────────────────────── */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <Card title="Stress Index per Session" icon={<Activity size={15} />}>
              <ZoomLineChart
                labels={sessLabels}
                datasets={[{ label: "Stress Index", data: chartData.map(d => d.stress), color: C.stress }]}
                yMin={0} yMax={100}
                refLines={[
                  { value: 75, color: C.high, label: "High" },
                  { value: 25, color: C.mod,  label: "Mod" },
                ]}
              />
            </Card>

            <Card title="HR & HRV per Session" icon={<HeartPulse size={15} />}>
              <ZoomLineChart
                labels={sessLabels}
                datasets={[
                  { label: "HR (bpm)", data: chartData.map(d => d.hr), color: C.hr },
                  { label: "HRV RMSSD (ms)", data: chartData.map(d => d.hrv), color: C.hrv },
                ]}
              />
            </Card>

            <Card title="GSR / EDA per Session" icon={<Zap size={15} />}>
              {hasSessionGsr ? (
                <ZoomLineChart
                  labels={sessLabels}
                  datasets={[{ label: "GSR (µS)", data: chartData.map(d => d.gsr), color: C.gsr }]}
                  yLabel="µS"
                />
              ) : hasPerMinGsr ? (
                <ZoomLineChart
                  labels={pmLabels}
                  datasets={[{ label: "GSR (µS) — per minute", data: perMin.map(r => r.avgGsr), color: C.gsr }]}
                  yLabel="µS"
                />
              ) : (
                <NoData />
              )}
            </Card>

            <Card title="Skin Temperature per Session" icon={<Thermometer size={15} />}>
              {hasSessionTemp ? (
                <ZoomLineChart
                  labels={sessLabels}
                  datasets={[{ label: "Skin Temp (°C)", data: chartData.map(d => d.temp), color: C.temp }]}
                  yLabel="°C"
                />
              ) : hasPerMinTemp ? (
                <ZoomLineChart
                  labels={pmLabels}
                  datasets={[{ label: "Skin Temp (°C) — per minute", data: perMin.map(r => r.avgTemp), color: C.temp }]}
                  yLabel="°C"
                />
              ) : (
                <NoData />
              )}
            </Card>

            <Card title="Motion (Accel. Magnitude)" icon={<Activity size={15} />} className="lg:col-span-2">
              {hasSessionAccel ? (
                <ZoomLineChart
                  labels={sessLabels}
                  datasets={[{ label: "Accel. Magnitude (g)", data: chartData.map(d => d.accel), color: C.accel }]}
                  yLabel="g"
                />
              ) : hasPerMinAccel ? (
                <ZoomLineChart
                  labels={pmLabels}
                  datasets={[{ label: "Accel. Magnitude (g) — per minute", data: perMin.map(r => r.avgAccelMag), color: C.accel }]}
                  yLabel="g"
                />
              ) : (
                <NoData />
              )}
            </Card>
          </div>

          {/* ── Per-minute breakdown ─────────────────────────────────────── */}
          {loadingPerMin && (
            <div className="text-xs flex items-center gap-2" style={{ color: theme.textDim }}>
              <div className="w-3 h-3 border border-[#0758E8] border-t-transparent rounded-full animate-spin" />
              Loading per-minute readings…
            </div>
          )}
          {perMin.length > 0 && (
            <Card title={`Per-Minute Sensor Data (${perMin.length} readings)`} icon={<Activity size={15} />}>
              <p className="text-xs mb-4" style={{ color: theme.textDim }}>
                Detailed per-minute averages from all sessions. Zoom in for granular view.
              </p>
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {hasPerMinGsr && (
                  <div>
                    <p className="text-xs font-medium mb-2" style={{ color: C.gsr }}>GSR / EDA (µS)</p>
                    <ZoomLineChart labels={pmLabels} datasets={[{ label: "GSR (µS)", data: perMin.map(r => r.avgGsr), color: C.gsr }]} height={180} yLabel="µS" />
                  </div>
                )}
                {hasPerMinTemp && (
                  <div>
                    <p className="text-xs font-medium mb-2" style={{ color: C.temp }}>Skin Temperature (°C)</p>
                    <ZoomLineChart labels={pmLabels} datasets={[{ label: "Skin Temp (°C)", data: perMin.map(r => r.avgTemp), color: C.temp }]} height={180} yLabel="°C" />
                  </div>
                )}
                {hasPerMinAccel && (
                  <div className="lg:col-span-2">
                    <p className="text-xs font-medium mb-2" style={{ color: C.accel }}>Motion / Accelerometer (g)</p>
                    <ZoomLineChart labels={pmLabels} datasets={[{ label: "Accel. (g)", data: perMin.map(r => r.avgAccelMag), color: C.accel }]} height={180} yLabel="g" />
                  </div>
                )}
              </div>
            </Card>
          )}


          {/* Session log */}
          <Card title={`Session Log (${sorted.length})`} icon={<ClipboardList size={15} />}>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-xs" style={{ borderBottom: `1px solid ${theme.border}`, color: theme.textDim }}>
                    <Th>#</Th><Th>Date & Time</Th><Th>Duration</Th><Th>Samples</Th>
                    <Th align="right">Stress</Th><Th align="right">HR</Th>
                    <Th align="right">HRV</Th><Th align="right">GSR</Th>
                    <Th align="right">Temp</Th><Th align="right">Motion</Th>
                    <Th>Tags</Th><Th />
                  </tr>
                </thead>
                <tbody>
                  {sorted.map((s, i) => (
                    <React.Fragment key={s.id}>
                      <tr
                        className="cursor-pointer"
                        style={{ borderBottom: `1px solid ${theme.border}40` }}
                        onClick={() => setExpandedId(expandedId === s.id ? null : s.id)}
                      >
                        <Td>{sorted.length - i}</Td>
                        <Td>{fmtDate(s.startTime)} {fmtTime(s.startTime)}</Td>
                        <Td>{fmtDuration(s.startTime, s.endTime)}</Td>
                        <Td>{s.snapshotCount || "—"}</Td>
                        <Td align="right"><StressBadge v={s.avgStress} /></Td>
                        <Td align="right" color={C.hr}>{fmt(s.avgHr, 1, "bpm")}</Td>
                        <Td align="right" color={C.hrv}>{fmt(s.avgHrv, 1, "ms")}</Td>
                        <Td align="right" color={C.gsr}>{fmt(s.avgGsr, 3, "µS")}</Td>
                        <Td align="right" color={C.temp}>{fmt(s.avgTemp, 1, "°C")}</Td>
                        <Td align="right" color={C.accel}>{fmt(s.avgAccelMag, 3, "g")}</Td>
                        <Td>
                          <div className="flex flex-wrap gap-1">
                            {s.tags.map(t => (
                              <span key={t} className="text-[10px] px-1.5 py-0.5 rounded" style={{ background: "#0758E818", color: "#0758E8" }}>{t}</span>
                            ))}
                          </div>
                        </Td>
                        <Td>
                          {expandedId === s.id
                            ? <ChevronUp size={14} style={{ color: theme.textDim }} />
                            : <ChevronDown size={14} style={{ color: theme.textDim }} />}
                        </Td>
                      </tr>
                      {expandedId === s.id && (
                        <tr style={{ backgroundColor: theme.inputBg }}>
                          <td colSpan={12} className="px-6 py-4">
                            <SessionDetail session={s} />
                          </td>
                        </tr>
                      )}
                    </React.Fragment>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>
        </>
      )}
    </div>
  );
}

// ── Signal Status Panel — compares latest session averages to calibration ──────
function SignalStatusPanel({ baseline, sessions }: {
  baseline?: Baseline;
  sessions: Session[];
}) {
  const { theme } = useContext(ThemeCtx);

  const latest = useMemo(
    () => [...sessions].sort((a, b) => b.startTime.getTime() - a.startTime.getTime())[0],
    [sessions],
  );

  // Returns { delta, pct, direction, severity } for one signal
  const compare = (current: number, mean: number, std: number) => {
    if (current <= 0 || mean <= 0) return null;
    const delta = current - mean;
    const pct = mean !== 0 ? (delta / mean) * 100 : 0;
    const zScore = std > 0 ? Math.abs(delta) / std : 0;
    const direction: "up" | "down" | "flat" =
      Math.abs(pct) < 3 ? "flat" : delta > 0 ? "up" : "down";
    const severity: "normal" | "mild" | "significant" =
      zScore < 1 ? "normal" : zScore < 2 ? "mild" : "significant";
    return { delta, pct, direction, severity };
  };

  const signals = baseline ? [
    {
      key: "hr", label: "Heart Rate", unit: "bpm", color: C.hr,
      icon: <HeartPulse size={16} />,
      current: latest.avgHr, mean: baseline.hrMean, std: baseline.hrStd,
      higherMeaning: "elevated HR may indicate stress",
    },
    {
      key: "hrv", label: "HRV RMSSD", unit: "ms", color: C.hrv,
      icon: <Brain size={16} />,
      current: latest.avgHrv, mean: baseline.hrvMean, std: baseline.hrvStd,
      higherMeaning: "higher HRV indicates relaxation",
    },
    {
      key: "gsr", label: "GSR / EDA", unit: "µS", color: C.gsr,
      icon: <Zap size={16} />,
      current: latest.avgGsr, mean: baseline.gsrMean, std: baseline.gsrStd,
      higherMeaning: "elevated GSR may indicate arousal",
    },
    {
      key: "temp", label: "Skin Temp", unit: "°C", color: C.temp,
      icon: <Thermometer size={16} />,
      current: latest.avgTemp, mean: baseline.tempMean, std: baseline.tempStd,
      higherMeaning: "slight variation is normal",
    },
    {
      key: "accel", label: "Motion", unit: "g", color: C.accel,
      icon: <Activity size={16} />,
      current: latest.avgAccelMag, mean: baseline.accelMean, std: baseline.accelStd,
      higherMeaning: "higher motion means more movement",
    },
  ] : [];

  const severityStyle = (sev: "normal" | "mild" | "significant", dir: "up" | "down" | "flat") => {
    if (sev === "normal" || dir === "flat") return { color: "#0758E8", bg: "#0758E818" };
    if (sev === "mild") return { color: "#646D7A", bg: "#646D7A1F" };
    return { color: "#0546BA", bg: "#0758E82E" };
  };

  return (
    <Card
      title="Signal Status vs. Calibration Baseline"
      icon={<Activity size={15} />}
    >
      {!baseline ? (
        <div className="flex items-center gap-2 text-sm py-2" style={{ color: theme.textDim }}>
          <AlertCircle size={15} />
          No calibration baseline recorded for this participant yet.
        </div>
      ) : (
        <>
          <p className="text-xs mb-4" style={{ color: theme.textDim }}>
            Comparing latest session ({fmtDate(latest.startTime)}) averages against
            resting baseline ({baseline.sampleCount > 0 ? `${baseline.sampleCount} samples` : ""}
            {baseline.calibratedAt ? ` · calibrated ${fmtDate(baseline.calibratedAt)}` : ""}).
          </p>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
            {signals.map(sig => {
              const result = compare(sig.current, sig.mean, sig.std);
              const style = result
                ? severityStyle(result.severity, result.direction)
                : { color: theme.textDim, bg: theme.inputBg };

              return (
                <div
                  key={sig.key}
                  className="rounded-control p-4 flex flex-col gap-2"
                  style={{ background: theme.inputBg, border: `1px solid ${theme.border}` }}
                >
                  {/* Header */}
                  <div className="flex items-center gap-1.5">
                    <span style={{ color: sig.color }}>{sig.icon}</span>
                    <span className="text-xs font-medium" style={{ color: theme.text }}>{sig.label}</span>
                  </div>

                  {/* Current value */}
                  <div>
                    <p className="text-[10px]" style={{ color: theme.textDim }}>Current (latest session)</p>
                    <p className="text-lg font-bold" style={{ color: sig.color }}>
                      {sig.current > 0 ? sig.current.toFixed(sig.unit === "µS" ? 3 : sig.unit === "g" ? 3 : 1) : "—"}
                      <span className="text-xs font-normal ml-1" style={{ color: theme.textDim }}>{sig.unit}</span>
                    </p>
                  </div>

                  {/* Baseline */}
                  <div>
                    <p className="text-[10px]" style={{ color: theme.textDim }}>Baseline (resting)</p>
                    <p className="text-sm" style={{ color: theme.textSub }}>
                      {sig.mean > 0 ? sig.mean.toFixed(sig.unit === "µS" ? 3 : sig.unit === "g" ? 3 : 1) : "—"}
                      <span className="text-xs ml-1" style={{ color: theme.textDim }}>± {sig.std > 0 ? sig.std.toFixed(1) : "—"} {sig.unit}</span>
                    </p>
                  </div>

                  {/* Delta badge */}
                  {result ? (
                    <div
                      className="flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold w-fit"
                      style={{ color: style.color, background: style.bg }}
                    >
                      {result.direction === "up"
                        ? <TrendingUp size={12} />
                        : result.direction === "down"
                          ? <TrendingDown size={12} />
                          : <Minus size={12} />}
                      {result.direction === "flat" ? "Normal" : (
                        <>{result.direction === "up" ? "↑" : "↓"} {Math.abs(result.pct).toFixed(1)}%</>
                      )}
                    </div>
                  ) : (
                    <div className="text-[10px]" style={{ color: theme.textDim }}>No data</div>
                  )}

                  {/* Severity label */}
                  {result && result.direction !== "flat" && (
                    <p className="text-[10px]" style={{ color: style.color }}>
                      {result.severity === "normal" ? "Within normal range"
                        : result.severity === "mild" ? "Mildly outside baseline"
                        : "Significantly outside baseline"}
                    </p>
                  )}
                </div>
              );
            })}
          </div>
        </>
      )}
    </Card>
  );
}

function SessionDetail({ session: s }: { session: Session }) {
  const { theme } = useContext(ThemeCtx);
  const fields = [
    { label: "Average Stress Index",    value: s.avgStress.toFixed(2),                      unit: "/ 100",     color: stressColor(s.avgStress) },
    { label: "Stress Category",         value: stressLabel(s.avgStress),                     unit: "",          color: stressColor(s.avgStress) },
    { label: "Heart Rate (avg)",        value: fmt(s.avgHr, 1, "", "No data"),               unit: "bpm",       color: C.hr },
    { label: "HRV RMSSD (avg)",         value: fmt(s.avgHrv, 1, "", "No data"),              unit: "ms",        color: C.hrv },
    { label: "GSR / EDA (avg)",         value: fmt(s.avgGsr, 4, "", "No data"),              unit: "µS",        color: C.gsr },
    { label: "Skin Temperature (avg)",  value: fmt(s.avgTemp, 2, "", "No data"),             unit: "°C",        color: C.temp },
    { label: "Accel. Magnitude (avg)",  value: fmt(s.avgAccelMag, 4, "", "No data"),         unit: "g",         color: C.accel },
    { label: "Total Samples",           value: s.snapshotCount > 0 ? s.snapshotCount.toString() : "—", unit: "snapshots", color: theme.textSub },
  ];
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
      {fields.map(f => (
        <div key={f.label} className="rounded-control p-3" style={{ background: theme.card, border: `1px solid ${theme.border}` }}>
          <p className="text-[10px] mb-1" style={{ color: theme.textDim }}>{f.label}</p>
          <p className="text-base font-bold" style={{ color: f.color }}>
            {f.value} <span className="text-xs font-normal" style={{ color: theme.textDim }}>{f.unit}</span>
          </p>
        </div>
      ))}
      {s.notes && (
        <div className="col-span-2 md:col-span-4 rounded-control p-3" style={{ background: theme.card, border: `1px solid ${theme.border}` }}>
          <p className="text-[10px] mb-1" style={{ color: theme.textDim }}>Notes</p>
          <p className="text-sm" style={{ color: theme.textSub }}>{s.notes}</p>
        </div>
      )}
    </div>
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 4 — ANALYTICS
// ═════════════════════════════════════════════════════════════════════════════
function AnalyticsTab({ participants, allSessions, sessionMap }: {
  participants: (Participant & { sessionCount: number; avgStress: number | null })[];
  allSessions: Session[];
  sessionMap: Record<string, Session[]>;
}) {
  const { theme } = useContext(ThemeCtx);

  const stressPerParticipant = useMemo(() =>
    participants
      .filter(p => (sessionMap[p.id]?.length ?? 0) > 0)
      .map(p => ({
        name: p.studentId !== "—" ? p.studentId : p.name.split(" ")[0],
        stress: +(p.avgStress ?? 0).toFixed(1),
        sessions: p.sessionCount,
      }))
      .sort((a, b) => b.stress - a.stress),
  [participants, sessionMap]);

  const sensorAvgs = useMemo(() => {
    if (!allSessions.length) return null;
    const n = allSessions.length;
    return {
      hr:    allSessions.reduce((a, s) => a + s.avgHr, 0) / n,
      hrv:   allSessions.reduce((a, s) => a + s.avgHrv, 0) / n,
      gsr:   allSessions.reduce((a, s) => a + s.avgGsr, 0) / n,
      temp:  allSessions.reduce((a, s) => a + s.avgTemp, 0) / n,
      accel: allSessions.reduce((a, s) => a + s.avgAccelMag, 0) / n,
    };
  }, [allSessions]);

  const stressTimeline = useMemo(() =>
    [...allSessions]
      .sort((a, b) => a.startTime.getTime() - b.startTime.getTime())
      .map(s => ({
        date: fmtDate(s.startTime),
        stress: +s.avgStress.toFixed(1),
        hr: +s.avgHr.toFixed(0),
        hrv: +s.avgHrv.toFixed(1),
      })),
  [allSessions]);

  const byCourse = useMemo(() => {
    const map: Record<string, number> = {};
    participants.forEach(p => { map[p.course] = (map[p.course] ?? 0) + 1; });
    return Object.entries(map).map(([k, v]) => ({ name: k === "—" ? "Unknown" : k, value: v }));
  }, [participants]);

  const byYear = useMemo(() => {
    const map: Record<string, number> = {};
    participants.forEach(p => { map[p.yearLevel] = (map[p.yearLevel] ?? 0) + 1; });
    return Object.entries(map).sort().map(([k, v]) => ({ name: k === "—" ? "Unknown" : k, value: v }));
  }, [participants]);

  const COLORS = ["#0758E8", "#6E9BF0", "#6D5BD0", "#C98A1B", "#5B6678", "#646D7A", "#0546BA"];
  const tt: React.CSSProperties = { backgroundColor: theme.tooltipBg, border: `1px solid ${theme.tooltipBorder}`, borderRadius: 10, fontSize: 12, color: theme.text };

  return (
    <div className="space-y-6">
      {sensorAvgs && (
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
          <StatCard icon={<HeartPulse size={18} />}  label="Avg HR (all)"     value={sensorAvgs.hr.toFixed(0) + " bpm"} color="red" />
          <StatCard icon={<Brain size={18} />}        label="Avg HRV RMSSD"   value={sensorAvgs.hrv.toFixed(1) + " ms"} color="purple" />
          <StatCard icon={<Zap size={18} />}          label="Avg GSR (EDA)"   value={sensorAvgs.gsr.toFixed(3) + " µS"} color="amber" />
          <StatCard icon={<Thermometer size={18} />}  label="Avg Skin Temp"   value={sensorAvgs.temp.toFixed(1) + " °C"} color="cyan" />
          <StatCard icon={<Activity size={18} />}     label="Avg Motion"      value={sensorAvgs.accel.toFixed(3) + " g"} color="green" />
        </div>
      )}

      <Card title="Average Stress Index per Participant" icon={<Activity size={15} />}>
        {stressPerParticipant.length === 0 ? <NoData /> : (
          <ZoomBarChart
            labels={stressPerParticipant.map(d => d.name)}
            dataValues={stressPerParticipant.map(d => d.stress)}
            color={C.stress}
            yLabel="Stress Index"
            height={260}
          />
        )}
      </Card>

      <Card title="Stress Index — All Participants Over Time" icon={<Activity size={15} />}>
        {stressTimeline.length === 0 ? <NoData /> : (
          <ZoomLineChart
            labels={stressTimeline.map(d => d.date)}
            datasets={[
              { label: "Stress Index", data: stressTimeline.map(d => d.stress), color: C.stress },
              { label: "HR (bpm)",     data: stressTimeline.map(d => d.hr),     color: C.hr },
            ]}
            yMin={0}
            refLines={[
              { value: 75, color: C.high, label: "High" },
              { value: 25, color: C.mod, label: "Mod" },
            ]}
            height={260}
          />
        )}
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card title="Participants by Course" icon={<Users size={15} />}>
          {byCourse.length === 0 ? <NoData /> : (
            <ResponsiveContainer width="100%" height={220}>
              <PieChart>
                <Pie data={byCourse} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={80} innerRadius={40} paddingAngle={3}>
                  {byCourse.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
                </Pie>
                <Tooltip contentStyle={tt} />
                <Legend wrapperStyle={{ fontSize: 11, color: theme.textSub }} />
              </PieChart>
            </ResponsiveContainer>
          )}
        </Card>

        <Card title="Participants by Year Level" icon={<BarChart2 size={15} />}>
          {byYear.length === 0 ? <NoData /> : (
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={byYear} margin={{ top: 4, right: 8, left: -20, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={theme.gridColor} vertical={false} />
                <XAxis dataKey="name" stroke={theme.textDim} fontSize={10} tickLine={false} axisLine={false} />
                <YAxis stroke={theme.textDim} fontSize={10} tickLine={false} axisLine={false} allowDecimals={false} />
                <Tooltip contentStyle={tt} cursor={{ fill: "rgba(0,0,0,0.04)" }} />
                <Bar dataKey="value" fill={C.accent} radius={[4, 4, 0, 0]} maxBarSize={48} name="Participants" />
              </BarChart>
            </ResponsiveContainer>
          )}
        </Card>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 5 — EXPORT
// ═════════════════════════════════════════════════════════════════════════════
function ExportTab({ participants, allSessions }: {
  participants: (Participant & { sessionCount: number; avgStress: number | null })[];
  allSessions: Session[];
}) {
  const { theme } = useContext(ThemeCtx);

  const exportParticipants = useCallback(() => {
    downloadCSV("physiopano_participants.csv",
      ["Name", "Student ID", "Course", "Year Level", "Sex", "Age", "Email",
       "Sessions", "Avg Stress Index", "Onboarding Complete"],
      participants.map(p => [
        p.name, p.studentId, p.course, p.yearLevel, p.sex,
        p.age > 0 ? String(p.age) : "",
        p.email, String(p.sessionCount),
        p.avgStress !== null ? p.avgStress.toFixed(2) : "",
        p.onboardingComplete ? "Yes" : "No",
      ]),
    );
  }, [participants]);

  const exportSessions = useCallback(() => {
    const pid2name: Record<string, string> = {};
    participants.forEach(p => { pid2name[p.id] = p.name; });
    downloadCSV("physiopano_sessions.csv",
      ["Participant Name", "Student ID", "Session Date", "Session Time",
       "Duration (s)", "Samples", "Avg Stress Index", "Stress Category",
       "Avg HR (bpm)", "Avg HRV RMSSD (ms)", "Avg GSR (µS)",
       "Avg Skin Temp (°C)", "Avg Accel Mag (g)", "Tags", "Notes"],
      allSessions.map(s => {
        const p = participants.find(x => x.id === s.participantId);
        const dur = s.endTime
          ? String(Math.round((s.endTime.getTime() - s.startTime.getTime()) / 1000)) : "";
        return [
          p?.name ?? "", p?.studentId ?? "",
          fmtDate(s.startTime), fmtTime(s.startTime), dur,
          String(s.snapshotCount),
          s.avgStress.toFixed(2), stressLabel(s.avgStress),
          s.avgHr > 0 ? s.avgHr.toFixed(2) : "",
          s.avgHrv > 0 ? s.avgHrv.toFixed(2) : "",
          s.avgGsr > 0 ? s.avgGsr.toFixed(4) : "",
          s.avgTemp > 0 ? s.avgTemp.toFixed(2) : "",
          s.avgAccelMag > 0 ? s.avgAccelMag.toFixed(4) : "",
          s.tags.join("; "), s.notes,
        ];
      }),
    );
  }, [participants, allSessions]);

  const btns = [
    { label: "Export Participants CSV", desc: `${participants.length} participants — demographics, averages`, icon: <Users size={20} />, onClick: exportParticipants },
    { label: "Export All Sessions CSV", desc: `${allSessions.length} sessions — all sensor averages + metadata`, icon: <ClipboardList size={20} />, onClick: exportSessions },
  ];

  return (
    <div className="research-export">
      {btns.map(btn => (
        <button
          key={btn.label}
          onClick={btn.onClick}
          className="export-option"
          style={{ background: theme.card, border: `1px solid ${theme.border}` }}
        >
          <div className="p-3 rounded-control shrink-0" style={{ background: "#0758E818", color: "#0758E8" }}>{btn.icon}</div>
          <div className="flex-1">
            <p className="font-semibold" style={{ color: theme.text }}>{btn.label}</p>
            <p className="text-xs mt-0.5" style={{ color: theme.textDim }}>{btn.desc}</p>
          </div>
          <Download size={16} style={{ color: theme.textDim }} />
        </button>
      ))}

      <div className="export-reference research-card">
        <h2>CSV column reference</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-1 text-xs">
          {[
            ["avg_stress_index", "0–100 weighted stress score"],
            ["avg_hr_bpm",       "Mean heart rate (BPM)"],
            ["avg_hrv_rmssd_ms", "Mean HRV (RMSSD, ms)"],
            ["avg_gsr_uS",       "Mean galvanic skin response (µS)"],
            ["avg_skin_temp_C",  "Mean skin temperature (°C)"],
            ["avg_accel_mag_g",  "Mean accelerometer magnitude (g)"],
            ["snapshot_count",   "Number of 1-Hz data points"],
            ["stress_category",  "Low / Moderate / High"],
          ].map(([col, desc]) => (
            <div key={col} className="flex gap-2">
              <code style={{ color: "#0758E8" }} className="shrink-0">{col}</code>
              <span style={{ color: theme.textDim }}>— {desc}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// SHARED UI COMPONENTS
// ═════════════════════════════════════════════════════════════════════════════
const colorMap: Record<string, { text: string; bg: string }> = {
  green:  { text: "#0758E8", bg: "#0758E818" },
  blue:   { text: "#6E9BF0", bg: "#6E9BF018" },
  purple: { text: "#6D5BD0", bg: "#6D5BD018" },
  red:    { text: "#5B6678", bg: "#5B66781F" },
  amber:  { text: "#C98A1B", bg: "#C98A1B18" },
  cyan:   { text: "#5B6678", bg: "#5B667818" },
};

function StatCard({ icon, label, value, color = "green" }: {
  icon: React.ReactNode; label: string; value: string; color?: string;
}) {
  const { theme } = useContext(ThemeCtx);
  const c = colorMap[color] ?? colorMap.green;
  return (
    <div className="research-stat">
      <span className="research-stat-icon" style={{ background: c.bg, color: theme.textSub }}>{icon}</span>
      <span>{label}</span><strong>{value}</strong>
    </div>
  );
}

function Card({ title, icon, children, className = "" }: {
  title: string; icon?: React.ReactNode; children: React.ReactNode; className?: string;
}) {
  const { theme } = useContext(ThemeCtx);
  return (
    <div className={`research-card ${className}`} style={{ background: theme.card, border: `1px solid ${theme.border}` }}>
      <h2 className="text-sm font-semibold mb-4 flex items-center gap-2" style={{ color: theme.text }}>
        {icon && <span style={{ color: "#0758E8" }}>{icon}</span>}
        {title}
      </h2>
      {children}
    </div>
  );
}

function Th({ children, align = "left" }: { children?: React.ReactNode; align?: "left" | "right" }) {
  return <th className={`py-2.5 px-2 font-medium ${align === "right" ? "text-right" : "text-left"}`}>{children}</th>;
}

function Td({ children, align, color }: { children?: React.ReactNode; align?: "right"; color?: string }) {
  const { theme } = useContext(ThemeCtx);
  return (
    <td
      className={`py-2.5 px-2 ${align === "right" ? "text-right" : ""}`}
      style={{ color: color ?? theme.textSub }}
    >
      {children}
    </td>
  );
}

function StressBadge({ v }: { v: number }) {
  const c = stressColor(v);
  return (
    <span className="text-xs font-semibold px-2 py-0.5 rounded-full" style={{ color: c, background: c + "18" }}>
      {v.toFixed(1)} — {stressLabel(v)}
    </span>
  );
}

function NoData() {
  const { theme } = useContext(ThemeCtx);
  return (
    <div className="flex items-center justify-center h-32 text-sm" style={{ color: theme.textDim }}>
      <Inbox size={16} className="mr-2" /> No data available
    </div>
  );
}
