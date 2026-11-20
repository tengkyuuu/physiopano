# CheckIn

One validated self-report item per screen (PHQ-4 for anxiety/low mood, PSS-4 for perceived stress), offered when the BaselineLane shows sustained deviation or on the weekly reflection.

- `surface` panel; progress as 4 outline dots (filled = answered), never a percentage bar.
- Question in `title`, `text-wrap: balance`. Options are full-width 48px rows, the instrument's exact wording, with a radio in `brand`.
- A `small` line names the instrument and where the answers go.
- Results screen: the score band in words, what it means and does not mean, then the StationStrip with a suggested stop.
- Any answer that indicates self-harm or suicide risk (PHQ-9 item 9 when used, or the safety question) ends the check-in and shows CrisisBar immediately.

Consumer provides: instrument id, item index, item text and response labels in EN/AR, selected value.

Don't: rephrase validated items; show a running score; gamify (streaks, points).
