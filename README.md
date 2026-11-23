<h1 align="center">⏰ prism_alerts</h1>

<p align="center">
  <b>Local reminders that survive timezone changes, DST shifts and reboots.</b><br/>
  Because the OS only remembers a UTC instant — not what your user <i>meant</i>.
</p>

<p align="center">
  <a href="https://pub.dev/packages/prism_alerts"><img src="https://img.shields.io/pub/v/prism_alerts.svg?logo=dart&logoColor=white" alt="pub.dev"></a>
  <a href="https://github.com/Awaisdev01/prism_alerts/actions"><img src="https://img.shields.io/github/actions/workflow/status/Awaisdev01/prism_alerts/ci.yml?branch=main&label=CI" alt="CI"></a>
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT">
</p>

---

## The problem

`flutter_local_notifications.zonedSchedule()` converts your `TZDateTime` to a UTC moment and hands it to the OS. The OS keeps only that moment. The local time you meant is gone:

- ✈️ **User travels** — notification fires at the *old* local time
- 🕐 **DST shifts** (2×/year in most of Europe and the US) — every daily reminder drifts by an hour
- 🔁 **Reboot** — scheduled notifications can vanish (Android <12 receiver quirks)

## The fix

`prism_alerts` stores the *intent* (local hour, recurrence rule) and **reconciles** the schedule against reality whenever the world moves:

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
  // Surfaces what the user missed while the app was away.
}
```

## Features

- **Intent-based scheduling** — store "08:00 local, daily", not a UTC instant
- **`reconcile()`** — one call on app resume rebuilds everything that moved
- **Missed-notification surfacing** — the user's reminder isn't silently lost
- **Reboot resilient** — re-registers on device restart

## Install

```sh
dart pub add prism_alerts
```

## Part of the Prism ecosystem

| Package | Role |
|---|---|
| [`prism_kit`](https://github.com/Awaisdev01/prism_kit) | 51-component adaptive UI kit |
| [`prism_glass`](https://github.com/Awaisdev01/prism_glass) | Apple Liquid Glass for Flutter |
| [`prism_doctor`](https://github.com/Awaisdev01/prism_doctor) | Design-system auditor |
| **`prism_alerts`** | **this package** |

## License

MIT
