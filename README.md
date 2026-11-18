# prism_alerts

[![pub package](https://img.shields.io/pub/v/prism_alerts.svg)](https://pub.dev/packages/prism_alerts)

**Reliable local reminders for Flutter.** The OS scheduler only remembers a
UTC instant — so when your user flies to another timezone, when DST shifts,
or after a reboot, "08:00 every day" silently fires at the wrong time (or
never). `prism_alerts` remembers what the user *meant* and rebuilds the
schedule whenever the world moves.

## The problem

`flutter_local_notifications.zonedSchedule()` converts your `TZDateTime` to
a UTC moment and hands it to the OS. The OS keeps only that moment. The
local time you meant is gone:

- ✈️ User travels: notification fires at the *old* local time
- 🕐 DST shifts (2×/year in most of Europe and the US): every daily reminder drifts by an hour
- 🔁 Reboot (Android <12 receiver quirks): scheduled notifications can vanish

## The fix

```dart
final alerts = PrismAlerts.instance;
await alerts.initialize();

await alerts.upsert(ReminderIntent(
  id: 'meds-morning',
  title: 'Morning meds',
  localHour: 8,
  localMinute: 0,
  recurrence: RecurrenceSpec.daily(),
));

// On every app resume:
final report = await alerts.reconcile();
if (report.timezoneChanged || report.offsetChanged) {
  // All schedules were rebuilt for the new local time.
}
if (report.missed > 0) {
  // Some slots passed while the app was dead — show them in-app.
}
```

## Features

- **Intent persistence** — local wall-clock + recurrence survives restarts
- **`reconcile()`** — one call on resume detects tz/offset drift, cancels
  and rebuilds every schedule
- **Missed-notification report** — surface "you missed X" instead of silence
- **DST-correct math** — wall-clock stepping (verified against
  Europe/Berlin spring-forward), not naive 24-hour adds
- **Recurrences** — once, daily, weekly (weekday set), every-N-days

## Part of the Prism ecosystem

`prism_kit` · `prism_glass` (Liquid Glass) · `prism_doctor` (design audit) ·
`prism_sketch` · `prism_guardrails` · `prism_alerts` (this package) ·
`urdu_toolkit`
