# StationStrip

The stepped support ladder as a transit line: 1 Self-help → 2 Community & peer → 3 Primary care → 4 Tele-mental health → 5 Specialist.

- Each station is a 44px `radius-pill` dot in its `route-N` colour with its Lucide pictogram in `on-route` (`on-route-3` on station 3), its number and its name. Never colour alone.
- The travelled part of the line is solid `ink`; the rest is dashed (pending). "You are here" and "Suggested next stop" are `caption` tags under the station; the suggested station also gets a 3px `ink` ring.
- The suggestion comes from the triage rules, not the AI. Tapping a station opens its sheet: what it is, eligibility, cost, wait, how hand-off works, and what gets shared (with ConsentRow).
- Phone: the strip runs vertically when it can't fit 5 × 64px. RTL: flows right to left.
- Crisis is never a station. Urgent risk skips the strip and shows CrisisBar.

Consumer provides: current station, suggested station, per-station availability.
