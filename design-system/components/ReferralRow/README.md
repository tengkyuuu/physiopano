# ReferralRow

A row in the care-navigator console's queue. Only referrals the person consented to share appear; people are pseudonymous until they choose otherwise.

- Columns: ID (`reading`), pseudonymous person, why (the validated score and the signal summary that prompted the check-in), station chip, hand-off status.
- Hand-off status uses line form: solid = live/accepted, dashed = pending acceptance, half-height end tick = stale (no update past the station's follow-up window). The window comes from the station's SLA.
- Urgent escalations (from CrisisBar) carry the only red: a `crisis` chip with "Urgent · human now", a faint crisis-tinted row, and sort to the top until a human marks them handled.
- A licensed navigator makes every decision: accept, re-route to another station, or close with an outcome. The AI never changes a row's station.

Consumer provides: referral record, consent scope, SLA for the station.
