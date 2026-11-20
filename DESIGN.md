---
name: PHYSIOPAÑO Wayfinding
description: You are here. Here's the next stop.
colors:
  limestone-ground: "#EEF0EC"
  enamel-surface: "#FBFBF8"
  sunk-well: "#E3E7E2"
  petrol-panel: "#0E2A2B"
  on-panel: "#F3F6F2"
  ink: "#10201F"
  ink-muted: "#4A5A58"
  hairline: "#C9D0CC"
  focus-blue: "#1F6FB2"
  route-teal: "#0F7A68"
  route-blue: "#1F6FB2"
  route-gold: "#B07D0F"
  route-violet: "#5D4BA6"
  route-slate: "#34495E"
  crisis-red: "#C63B2B"
typography:
  sign:
    fontFamily: "Overpass, Noto Kufi Arabic, system-ui, sans-serif"
    fontSize: "64px"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "-0.03em"
  display:
    fontFamily: "Overpass, Noto Kufi Arabic, system-ui, sans-serif"
    fontSize: "44px"
    fontWeight: 800
    lineHeight: 1.05
    letterSpacing: "-0.02em"
  heading:
    fontFamily: "Overpass, Noto Kufi Arabic, system-ui, sans-serif"
    fontSize: "32px"
    fontWeight: 800
    lineHeight: 1.125
    letterSpacing: "-0.01em"
  title:
    fontFamily: "Overpass, Noto Kufi Arabic, system-ui, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.25
  lead:
    fontFamily: "Overpass, Noto Kufi Arabic, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.4
  body:
    fontFamily: "Overpass, Noto Kufi Arabic, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
  small:
    fontFamily: "Overpass, Noto Kufi Arabic, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.43
  caption:
    fontFamily: "Overpass, Noto Kufi Arabic, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.33
    letterSpacing: "0.06em"
  reading:
    fontFamily: "Overpass Mono, ui-monospace, monospace"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.25
  body-ar:
    fontFamily: "Noto Kufi Arabic, Overpass, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.65
rounded:
  control: "6px"
  panel: "12px"
  sheet: "20px"
  pill: "999px"
spacing:
  s1: "4px"
  s2: "8px"
  s3: "12px"
  s4: "16px"
  s5: "24px"
  s6: "32px"
  s7: "48px"
  s8: "64px"
components:
  button-primary:
    backgroundColor: "{colors.route-teal}"
    textColor: "{colors.enamel-surface}"
    rounded: "{rounded.control}"
    padding: "0 24px"
    height: "48px"
  button-secondary:
    backgroundColor: "{colors.limestone-ground}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0 24px"
    height: "48px"
  button-crisis:
    backgroundColor: "{colors.crisis-red}"
    textColor: "{colors.enamel-surface}"
    rounded: "{rounded.control}"
    padding: "0 24px"
    height: "48px"
  sign-panel:
    backgroundColor: "{colors.petrol-panel}"
    textColor: "{colors.on-panel}"
    rounded: "{rounded.panel}"
    padding: "24px"
  station-dot:
    rounded: "{rounded.pill}"
    size: "44px"
  check-in-option:
    backgroundColor: "{colors.limestone-ground}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    height: "48px"
---

# Design System: PHYSIOPAÑO Wayfinding

Source of truth for values: `design-system/tokens.json` (mirrored to `tokens.css`, `tailwind.preset.js`, `physiopano_tokens.dart`). Dark values live there; this file records the light theme and the rules.

## Overview

Support is a route, not a verdict. The system borrows the grammar of Gulf bilingual wayfinding enamel: limestone ground, white enamel panels, one petrol sign per screen, and five transit-line colours that *are* the stepped support ladder. Every screen answers where am I and where can I go next. It refuses the wellness-app default of a ring gauge on soft cards and any population "stress level". The Flutter app (glanced at between tasks) and the React care-navigator console (worked at a desk) share every token.

## Colors

Restrained ground, committed meaning: neutrals carry the surface; colour appears only where it means a station, your lane, an action or a crisis.

### Primary
- **Route Teal** (`route-teal`): your own lane, the primary action, and Station 1 Self-help. One hue, because the route starts with you.

### Secondary
- **Route Blue / Gold / Violet / Slate**: Stations 2 Community and peer, 3 Primary care, 4 Tele-mental health, 5 Specialist. Gold takes `ink` text, never white.

### Tertiary
- **Crisis Red** (`crisis-red`): reserved for urgent-risk UI only.

### Neutral
- **Limestone Ground**, **Enamel Surface**, **Sunk Well**, **Petrol Panel**, **Ink**, **Ink Muted**, **Hairline**.

### Named Rules
- **The Station Rule.** A route colour never appears without its station number and pictogram.
- **The Reserved Red Rule.** Only CrisisBar, the emergency-call action and console escalation rows use `crisis-red`. No warning, error styling or decoration borrows it.
- **The One Sign Rule.** One `petrol-panel` sign per screen.
- **No Traffic Lights.** There is no red/amber/green stress scale anywhere.

## Typography

Overpass, descended from highway-signage lettering, for everything; Noto Kufi Arabic for Arabic (set 1px larger, looser leading); Overpass Mono only for sensor readings, z-scores and IDs, with tabular figures.

### Hierarchy
`sign` 64/800 (one per screen max) → `display` 44/800 → `heading` 32/800 → `title` 24/700 → `lead` 20/600 (the one sentence that explains a result) → `body` 16 → `small` 14 → `caption` 12/600 uppercase +0.06em.

### Named Rules
- **No Kickers.** A `caption` never sits above a heading as an eyebrow; captions label stations and columns.
- **Mono Means Measurement.** Overpass Mono is never decorative.

## Layout

4-point spacing `s1`–`s8`. Phone gutter `s4`; console panel padding `s5`; `s6` above section headings, less below. Touch targets ≥ `s7` (48px). The StationStrip runs horizontally when 5 × 64px fits, vertically otherwise; under `dir="rtl"` everything mirrors and the route flows right to left.

## Elevation & Depth

Flat enamel. Panels sit on the ground with a 1px `hairline`. `shadow-raised` only for a panel floating over the lane; `shadow-overlay` for sheets and drawers. No glass, no glow, no gradients.

### Named Rules
- **Line Form Carries State.** 3px lines: solid = live, dashed 6/4 = pending (referral awaiting acceptance; baseline forming), half height = stale (wristband off, old sync). Used in charts, the lane, the strip and console rows.
- **Size Carries Deviation.** Distance from the person's own baseline is a fixed marker ramp in `ink`: |z| < 1 → 8px, 1–2 → 14px, > 2 → 20px.

## Shapes

`control` 6px (the corner of an enamel plate) on buttons, inputs, chips; `panel` 12px on panels; `sheet` 20px top corners of bottom sheets; `pill` only for station dots and the You-are-here marker.

## Components

### Buttons
Primary (`route-teal`), secondary (1.5px `ink` outline), crisis (`crisis-red`, phone icon, CrisisBar only). Disabled drops colour and says why in its label. Labels name the action.

### Chips
Station chip = station dot + number + name. Urgent chip = `crisis-red` fill, "Urgent · human now".

### Cards / Containers
`enamel-surface` panel, 1px `hairline`, `panel` radius, padding `s5`. Never nested. SignPanel is the only `petrol-panel` container.

### Inputs / Fields
Check-in options are full-width 48px rows on `limestone-ground`, 1.5px `hairline` border turning `ink` when chosen; radio in `route-teal`. Consent switches are 52×32 with a 2px `ink` outline off, `route-teal` fill on.

### Navigation
Bottom navigation in the app on `enamel-surface`, active item tinted `route-teal` at 14%. Console uses a left rail on `enamel-surface`.

### BaselineLane (signature)
One signal over 14 days against the person's own ±1σ band (`route-teal` at 14%), dotted "your usual" line, 3px `ink` series, deviation markers on the size ramp, ending at the You-are-here marker (`route-teal` disc, surface ring). The marker slides to a new reading in 220ms `cubic-bezier(0.16,1,0.3,1)`; it jumps under reduced motion. This is the system's one authored motion.

### StationStrip (signature)
Five 44px station dots on a 3px route; travelled part solid, the rest dashed; "You are here" and "Suggested next stop" as captions; the suggestion gets a 3px `ink` ring.

## Do's and Don'ts

### Do:
- Do say what a result means and what it does not mean.
- Do compare only to the person's own usual.
- Do show every share as a literal sentence with recipient and expiry.
- Do give every focusable element a 3px solid `focus-blue` ring, 2px offset.
- Do ship every string in English and Arabic.

### Don't:
- Don't show a stress score, gauge or ring.
- Don't use red for anything but crisis.
- Don't let physiology alone trigger crisis UI.
- Don't use gradients, glass, emoji or stock photos of meditating people.
- Don't put a route colour on screen without its number and pictogram.
