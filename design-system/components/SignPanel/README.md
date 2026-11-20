# SignPanel

The petrol sign that opens a screen and tells the person where they are.

- One per screen, at the top. `panel` fill, `on-panel` text, `radius-panel`, padding `space-5`.
- Title in `display` (app Home may use `sign`). One supporting `body` line in plain words.
- Optional state line beneath, drawn with the line-form vocabulary: solid = wristband live, dashed = baseline forming (first 14 days), half-height = stale.
- The logo mark sits at 48px on the left only on Home and the console header.

Consumer provides: title, subtitle, optional state (live | forming | stale) with its sentence.

Don't: stack two sign panels; put buttons inside; use it as a generic card.
