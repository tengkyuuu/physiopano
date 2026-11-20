PHYSIOPAÑO helps a person notice when they drift from **their own** baseline and shows the next gentle stop on a route to support. The whole system is built on one idea: **support is a route, not a verdict.** Every screen answers two questions a wayfinding sign answers: *where am I?* and *where can I go next?*

The same tokens drive the Flutter companion app (young and working adults, glanced at between tasks) and the React care-navigator console (licensed clinicians at a desk, triaging consented referrals).

## Content fundamentals

- **Speak like a calm person, not a device.** "Your heart-rate variability has been lower than your usual for 3 days." Never "Stress level: HIGH".
- **Always say what a result means and does not mean.** Every result ends with a `body` line that starts "This is not a diagnosis." or names the limit.
- **Compare to *your* usual, never to other people.** Use "your usual", "your baseline", "lower than your normal". Never "above average".
- **Name the next stop, not the problem.** Buttons name the action: "Do a 2-minute check-in", "See support near you", "Talk to someone now".
- **Second person, sentence case, no emoji, no exclamation marks.** Station names are Title Case only on the station strip.
- **Bilingual by default.** Every user-facing string ships in English and Arabic. Arabic uses `body-ar` / `heading-ar`, and layouts mirror under `dir="rtl"`; the route still flows from station 1 to 5 in reading direction.
- **Consent copy is literal.** "Shared with: Dr. Amna (primary care) until 30 Nov. Stop sharing." Never "Data settings".

## Visual foundations

**The world.** Gulf bilingual wayfinding enamel: limestone `ground`, white enamel `surface` panels, one petrol `panel` sign per screen, and five route colours that are the stepped support ladder. Flat colour only: no gradients, no glass, no glow.

**Colour.**
- `ground` behind everything; `surface` for panels; `surface-sunk` for wells and the lane bed.
- One `panel` per screen carries the screen title or the You-are-here header, text in `on-panel`.
- `brand` = your own lane + the primary action. It is the same hue as `route-1` because the route starts with you.
- `route-1` … `route-5` belong to the support ladder only: 1 Self-help, 2 Community and peer, 3 Primary care, 4 Tele-mental health, 5 Specialist. **A route colour never appears without its station number and pictogram.** Text on route fills uses `on-route`; on `route-3` use `on-route-3`.
- `crisis` is reserved. Only the crisis bar, the emergency-call action and console escalation rows may use it. Nothing decorative is ever red, and no warning state borrows it.
- Text: `ink` on `ground`/`surface`; `ink-muted` for secondary. Both pass 4.5:1 in both themes.

**State is line form, not hue.** Lines are `stroke-route` wide. Solid = live. Dashed (`stroke-pending-dash`) = pending (referral sent, awaiting acceptance; baseline still forming in the first 14 days). Half height (`stroke-stale-height`) = stale (wristband off, sync older than 6 h). This holds in charts, the lane, the station strip and console rows.

**Deviation is size, not colour.** Distance from your baseline uses a fixed marker ramp: within (|z| < 1) 8px, notable (1–2) 14px, marked (> 2) 20px, all in `ink`. There is no red/amber/green stress scale anywhere.

**Type.** Overpass, a typeface descended from highway signage lettering, for everything (`--font-sans`); Noto Kufi Arabic for Arabic; Overpass Mono (`--font-data`) **only** for sensor readings, z-scores and IDs. Scale: `sign` 64 (one per screen max), `display` 44, `heading` 32, `title` 24, `lead` 20, `body` 16, `small` 14, `caption` 12 uppercase tracked. Never put a `caption` above a heading as a kicker.

**Spacing.** 4-point steps `space-1`…`space-8`. Phone gutter `space-4`; console panel padding `space-5`; `space-6` above every section heading, less below. Touch targets are at least `space-7` (48px).

**Shape.** `radius-control` 6px on buttons, inputs and chips (the corner of an enamel plate); `radius-panel` 12px on panels; `radius-sheet` 20px for bottom sheets; `radius-pill` only for station dots and the You-are-here marker.

**Depth.** Panels sit flat with a `line` hairline. `shadow-raised` only for a panel floating over the lane; `shadow-overlay` for sheets and drawers.

**Focus.** Every focusable element gets a 3px solid `focus` ring with 2px offset. It holds at least 3:1 on `ground` and `surface` in both themes.

**Motion.** One authored moment: when a new reading lands, the You-are-here marker slides along the lane (220ms, `cubic-bezier(0.16, 1, 0.3, 1)`). Sheets rise in 220ms. Nothing pulses, nothing loops. Under `prefers-reduced-motion` the marker jumps.

**Imagery.** No stock photos of meditating people. The lane, the route and the pictograms are the imagery.

## Iconography

- Lucide (outline, 2px stroke, round caps) in both the app (`lucide_icons` for Flutter) and the console (`lucide-react`, already installed). 24px in the app, 20px in the console.
- Station pictograms (drawn on station dots, `on-route` stroke): 1 Self-help `leaf`, 2 Community `users`, 3 Primary care `stethoscope`, 4 Tele-mental health `video`, 5 Specialist `hospital`. Crisis uses `phone` on `crisis`.
- No emoji, no unicode glyphs as icons.

## Logo

The mark (Logos, `physiopano-mark.svg`) is a petrol sign plate holding a P drawn as a route: the stem is your lane, the bowl is the loop back to your baseline, and the teal station on the bowl is *you are here*. Inks: `panel` plate, `on-panel` route, `brand` station. Minimum size 24px. Clear space = the stem width on all sides. The wordmark is PHYSIOPAÑO set in Overpass 800, tracking -0.01em, always with the tilde.

## Components

- **SignPanel** opens every screen. **BaselineLane** is the hero on Home. **StationStrip** shows the support ladder wherever support is suggested. **CheckIn** runs PHQ-4 / PSS-4 items. **ConsentRow** is the only way data is shared. **CrisisBar** is pinned whenever a check-in answer indicates risk. **ReferralRow** is the console's queue row. **Button** has primary, secondary and crisis variants.
