/// Crisis and support contacts shown by CrisisBar.
///
/// VERIFY BEFORE ANY DEMO OR PILOT. Numbers below come from public sources
/// checked on 2026-11-18; hours and availability change.
///   - 998: UAE ambulance (emergency).
///   - 800 4673 (800-HOPE): UAE national mental support line, Arabic and
///     English, call or WhatsApp. Sources disagree on current hours.
///     https://www.thenationalnews.com/uae/health/coronavirus-uae-sets-up-free-national-helpline-to-support-mental-health-1.1021577
///   - Abu Dhabi: one 2026 source reports a Department of Health line,
///     800-SAKINA (800 725462), 24/7. Not yet confirmed from an official
///     page, so it is NOT shown in the app until a partner confirms it.
///     https://www.emirates247.com/uae-guide/uae-mental-health-helplines-2026-numbers-to-call-in-dubai-abu-dhabi-and-across-the-emirates/6178
library;

class SupportContact {
  final String label;
  final String display;
  final String dial;
  final String note;
  const SupportContact(this.label, this.display, this.dial, this.note);
}

class SupportContacts {
  static const emergency = SupportContact(
    'Ambulance',
    '998',
    '998',
    'If you are in immediate danger.',
  );

  static const supportLine = SupportContact(
    'National support line',
    '800 4673 (800-HOPE)',
    '8004673',
    'Free, in Arabic and English. You can also message it on WhatsApp.',
  );
}
