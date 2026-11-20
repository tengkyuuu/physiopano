# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users
- **Primary:** young and working-age adults (roughly 18–40) in Abu Dhabi who opt in to wear the PHYSIOPAÑO wristband so they can notice changes in their own stress and wellbeing earlier than they would on their own. They use the companion app (Flutter, Android) in short glances during the day and a weekly reflection.
- **Secondary:** licensed care navigators and clinicians (primary care, tele-mental health, counselling) who use the web console to receive *consented* referrals, act on escalations, and track hand-off and follow-up. They are the final decision makers.

## Product Purpose
Help a person recognise change in their wellbeing over time and connect them to the least intensive safe and effective support, with humans in the loop for anything high-risk. Success = earlier recognition, completed hand-offs to trusted support, follow-up within the intended timeframe, and no harm from covert monitoring or data exposure.

Built for a hackathon on the challenge: "Earlier, Safer Mental-Wellbeing Support" (Abu Dhabi).

## Positioning
A wearable that compares you only to **your own baseline**, never to a population label. Physiological signals (HRV, electrodermal activity, skin temperature, motion) are treated as an opt-in *nudge to reflect*, confirmed by validated self-report (PHQ-4, PSS-4) before any support suggestion. The device never diagnoses; it opens a door to a person.

## Operating Context
- ESP32 wristband: MAX30102 (PPG/HR/HRV), Grove GSR v1.2 (EDA), MLX90614 (skin temp), MPU6050 (motion). Streams over BLE to the phone.
- Mobile app: Flutter, Firebase (Auth, Firestore, RTDB), local SQLite/Hive, Gemini via `google_generative_ai` for plain-language explanation only.
- Care console: React 19 + Vite + Tailwind 3, Firebase, Recharts/Chart.js (`admin-web-react/`). The legacy `Admin Page/index.html` is superseded.
- Usage scene: user glances at the app between tasks, sometimes while stressed; navigators triage a queue at a desk.

## Capabilities and Constraints
- **AI approach (confirmed):** personal-baseline deviation detection (14-day rolling baseline per user, z-scores), triggering validated check-ins (PHQ-4, PSS-4); LLM limited to explaining results and suggesting stepped support options. The WESAD-trained Random Forest is retired because it collapsed to "medium" on our sensors.
- Stepped support ladder: self-help → community/peer → primary care → tele-mental health → specialist. Crisis/suicide-related signals in self-report bypass the ladder to emergency guidance and a human.
- Consent is granular and revocable per data stream and per sharing target. Employers never receive identifiable data.
- Admin web becomes a **care navigator console**, not a research dashboard.
- Undecided: specific Abu Dhabi service directory entries and crisis line numbers must be verified before the demo; do not invent them.

## Brand Commitments
- Name: **PHYSIOPAÑO** (kept from the thesis). "Paño" = cloth/handkerchief — something worn close and gentle.
- Voice: calm, plain, non-clinical, never alarming; explains what a result means **and does not mean**.
- Technology never presented as a replacement for professional care.

## Evidence on Hand
- Thesis: sensor accuracy validation (Objective 1), calibration data in `Calibration/`, `validation/`.
- WESAD training artefacts in `Train WESAD/` (to be retired, kept as a "what we learned" slide).
- No user testimonials, clinical outcomes, or partner organisations exist yet — never fabricate them.

## Product Principles
1. Your baseline, not a population label.
2. Signal invites reflection; self-report confirms; a human decides.
3. Least intensive safe support first, fastest human path when risk appears.
4. Minimum data, granular consent, revocable anytime.
5. Measure hand-offs and harms, not just engagement.

## Accessibility & Inclusion
Arabic and English (RTL support), legible under stress (large type for state, no colour-only status), WCAG 2.2 AA on the console. Fairness monitoring across age, gender, nationality, language, geography.
