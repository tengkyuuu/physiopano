# BaselineLane

The hero of Home: one signal over the last 14 days, drawn against the person's **own** baseline band, ending at the You-are-here marker.

- Band: `brand` at 14% between −1σ and +1σ of the person's rolling 14-day baseline; dotted `brand` centre line labelled "your usual".
- Series: 3px `ink` line. Line form carries state (solid live, dashed pending, half-height tick for a day with no data).
- Deviation markers on a fixed size ramp: |z| < 1 → 8px, 1–2 → 14px, > 2 → 20px. Never coloured by severity.
- Today: the You-are-here marker (`brand` disc, `surface` ring, `on-brand` centre). It slides to its new position in 220ms when a reading lands.
- Above the chart: `title` with the signal name and today's `reading`, a `lead` sentence that says what changed in plain words, and a `body` note in `ink-muted` that says what it does not mean.

Consumer provides: signal name, unit, 14 daily values (null for no data), baseline mean/sd, the lead and note copy.

Don't: show a population "stress level"; colour the line red/amber/green; show more than one signal per lane (stack lanes instead).
