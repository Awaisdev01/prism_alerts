// Copyright 2026 Awais Rehman. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Prism Alerts — reliable local reminders for Flutter.
///
/// `flutter_local_notifications` hands the OS a single UTC instant; the
/// user's "08:00 every day" meaning is lost, so reminders break silently
/// when the user travels, when DST shifts, or after a reboot.
///
/// PrismAlerts persists the *intent* (local wall-clock + recurrence),
/// rebuilds the OS schedule on every resume, and reports reminders that
/// fired into silence while the app was dead.
library;

export 'src/alerts.dart';
export 'src/intent.dart';
