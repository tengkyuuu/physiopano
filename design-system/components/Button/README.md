# Button

Buttons name the action they take, in sentence case, and come in three variants.

- **primary** (`brand` fill, `on-brand` text): the one next step on a screen. One per screen.
- **secondary** (1.5px `ink` outline, transparent): dismiss, later, back.
- **crisis** (`crisis` fill, `on-crisis` text, `phone` icon): only inside CrisisBar and the console escalation drawer.
- **disabled** drops all colour to `surface-sunk` / `ink-muted` and says why in its label ("Baseline still forming"), never just greyed.

Consumer provides: label, variant, optional leading Lucide icon, onPress. Height 48px minimum (`space-7`), radius `radius-control`, padding `space-5`. Focus: 3px `focus` ring.

Don't: use two primary buttons side by side; use crisis for anything that isn't urgent-risk; write "Submit" or "OK".
