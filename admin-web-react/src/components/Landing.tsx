import {
  Activity,
  ArrowRight,
  ArrowUpRight,
  Check,
  Fingerprint,
  HandHeart,
  HeartPulse,
  Move,
  Thermometer,
} from 'lucide-react'
import { ConsoleBrand } from './ConsoleBrand'

const workflow = [
  ['Receive the request', 'A participant asks for support in the mobile app and chooses what to share.'],
  [
    'Review the hand-off',
    'A navigator reviews the request, checks consent, and takes responsibility for the next contact.',
  ],
  [
    'Record the follow-up',
    'The navigator records contact and the outcome so the team can see what happened.',
  ],
]
const sensors = [
  { icon: HeartPulse, name: 'Optical pulse', detail: 'Pulse measurements from the MAX30102.' },
  {
    icon: Fingerprint,
    name: 'Skin conductance',
    detail: 'Changes in the electrical conductance of the skin.',
  },
  { icon: Thermometer, name: 'Skin temperature', detail: 'Surface temperature measured at the wrist.' },
  { icon: Move, name: 'Motion', detail: 'Movement context for interpreting wearable readings.' },
]

export function Landing({ onLogin }: { onLogin?: () => void }) {
  return (
    <div className="desk-public" id="top">
      <header className="public-head">
        <a href="#top" aria-label="Physiopaño home">
          <ConsoleBrand />
        </a>
        <nav aria-label="About the console">
          <a href="#how">How it works</a>
          <a href="#sensors">Wearable</a>
          {onLogin && (
            <button className="desk-btn secondary" onClick={onLogin}>
              Sign in <ArrowUpRight size={16} />
            </button>
          )}
        </nav>
      </header>
      <main className="public-main">
        <section className="public-hero" id="features">
          <div>
            <p className="desk-kicker">
              <span className="ink-rule" />
              Navigator workspace
            </p>
            <h1>
              Care navigator
              <br />
              <em>console.</em>
            </h1>
            <p className="hero-intro">
              Review consented referrals, coordinate hand-offs, and follow each request through to its
              outcome.
            </p>
            <div className="hero-actions">
              {onLogin && (
                <button onClick={onLogin} className="desk-btn primary">
                  Sign in to console <ArrowRight size={17} />
                </button>
              )}
              <a className={onLogin ? "desk-btn secondary" : "desk-btn primary"} href="#/demo">
                Explore the demo
              </a>
            </div>
          </div>
          <div
            className="handoff-art"
            aria-label="Illustration of a referral progressing from request to follow-up"
            role="img"
          >
            <div className="art-grid" />
            <div className="art-paper-back" />
            <div className="art-paper">
              <div className="slip-meta">
                <HandHeart size={25} />
                <span>CARE NAVIGATION</span>
              </div>
              <div className="slip-title">
                Referral
                <br />
                hand-off
              </div>
              <ul className="slip-steps">
                <li>
                  <i>
                    <Check size={13} />
                  </i>
                  Request received
                </li>
                <li>
                  <i>
                    <Check size={13} />
                  </i>
                  Navigator assigned
                </li>
                <li>
                  <i />
                  Follow-up
                </li>
              </ul>
            </div>
            <span className="art-legend">
              <span />
              Workflow illustration
            </span>
          </div>
        </section>
        <section className="public-section" id="how">
          <div>
            <p className="desk-kicker">Care navigation</p>
            <h2>How it works</h2>
          </div>
          <ol className="workflow-list">
            {workflow.map(([name, detail], i) => (
              <li key={name}>
                <span className="workflow-num">0{i + 1}</span>
                <div>
                  <h3>{name}</h3>
                  <p>{detail}</p>
                </div>
              </li>
            ))}
          </ol>
        </section>
        <section className="public-section" id="sensors">
          <div>
            <p className="desk-kicker">From the wristband</p>
            <h2>Wearable signals</h2>
          </div>
          <div className="sensor-grid">
            {sensors.map(({ icon: Icon, name, detail }) => (
              <div key={name}>
                <Icon size={21} />
                <h3>{name}</h3>
                <p>{detail}</p>
              </div>
            ))}
          </div>
        </section>
        <section className="public-section" id="analytics">
          <div>
            <p className="desk-kicker">Reporting</p>
            <h2>After the hand-off</h2>
          </div>
          <div className="public-report">
            <Activity size={24} />
            <p>
              See time to first contact, referral outcomes, and group comparisons when enough people have
              shared results.
            </p>
            <a href="#/demo" className="text-link">
              Explore the demo <ArrowRight size={16} />
            </a>
          </div>
        </section>
      </main>
      <footer className="public-foot">
        <span>PHYSIOPAÑO · Care console</span>
        <a href="#top">Back to top ↑</a>
      </footer>
    </div>
  )
}
