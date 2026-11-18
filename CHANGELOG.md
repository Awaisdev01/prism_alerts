## 0.1.0

- ReminderIntent: local wall-clock time + recurrence (never/daily/weekly/interval), JSON persistence.
- PrismAlerts.reconcile(): rebuilds the OS schedule on every resume; detects timezone and UTC-offset drift; reports missed notifications.
- DST-correct recurrence math (wall-clock stepping, not 24h absolute adds) — verified against Europe/Berlin spring-forward.
- Built on flutter_local_notifications 23.
