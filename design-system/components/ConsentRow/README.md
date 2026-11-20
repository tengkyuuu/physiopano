# ConsentRow

The only way any data leaves the phone. One row per data stream × recipient.

- Row: what (`body` bold), who and until when (`small`, `ink-muted`), and a switch. The sentence is literal: "Your primary-care clinic, until 30 Nov".
- Switch: 52×32, 2px `ink` outline when off; `brand` fill with `on-brand` knob when on. It is a real `role="switch"` with an `aria-label` naming the stream.
- Revoking is one tap and takes effect immediately; the console sees "Consent withdrawn" on the referral.
- Employer is a permanent locked-off row (lock icon + words), so the guarantee is visible, not buried in a policy.
- Every share has an expiry; default 30 days.

Consumer provides: stream, recipient, expiry, state, locked flag.
