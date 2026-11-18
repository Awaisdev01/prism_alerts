// Copyright 2026 Awais Rehman. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'intent.dart';

/// Result of a schedule reconciliation pass.
class ReconcileReport {
  ReconcileReport({
    required this.rescheduled,
    required this.missed,
    required this.timezoneChanged,
    required this.offsetChanged,
  });

  final int rescheduled;
  final int missed;
  final bool timezoneChanged;
  final bool offsetChanged;

  @override
  String toString() =>
      'ReconcileReport(rescheduled: $rescheduled, missed: $missed, '
      'tzChanged: $timezoneChanged, offsetChanged: $offsetChanged)';
}

/// Reliable local reminders on top of `flutter_local_notifications`.
///
/// The OS only remembers a UTC instant. PrismAlerts remembers what the
/// user *meant* — "08:00 daily" — persists it locally, and rebuilds the
/// OS schedule whenever the world moves:
///
/// - timezone changed (user flew somewhere)
/// - UTC offset changed (DST shifted)
/// - after app resume (catches anything the OS dropped)
///
/// It also reports reminders whose fire time passed while the app was
/// dead, so your UI can show "you missed X" instead of silence.
class PrismAlerts {
  PrismAlerts._();

  static final PrismAlerts instance = PrismAlerts._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _prefsKey = 'prism_alerts.intents.v1';
  static const _lastTzKey = 'prism_alerts.last_tz';
  static const _lastOffsetKey = 'prism_alerts.last_offset_ms';

  List<ReminderIntent> _intents = const [];
  bool _initialized = false;
  tz.Location? _location;

  /// Initializes the plugin and loads persisted intents.
  Future<void> initialize({
    String androidChannelId = 'prism_alerts',
    String androidChannelName = 'Reminders',
  }) async {
    if (_initialized) {
      return;
    }
    tzdata.initializeTimeZones();
    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: const DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
    await _loadIntents();
    _initialized = true;
  }

  /// Sets the timezone from the device (call after [initialize]).
  Future<void> syncDeviceTimezone() async {
    // The device's zone is provided by callers via `flutter_timezone`;
    // kept optional so pure-Dart tests can inject locations directly.
    _location ??= tz.local;
  }

  /// Overrides the location used for schedule math (tests, desktop).
  void debugSetLocation(tz.Location location) {
    _location = location;
  }

  tz.Location get _loc => _location ?? tz.local;

  Future<void> _loadIntents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) {
      _intents = const [];
      return;
    }
    final list = (jsonDecode(raw) as List<Object?>)
        .whereType<Map<String, Object?>>()
        .map(ReminderIntent.fromJson)
        .toList();
    _intents = List.unmodifiable(list);
  }

  Future<void> _saveIntents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_intents.map((i) => i.toJson()).toList()),
    );
  }

  /// All persisted reminders.
  List<ReminderIntent> get intents => _intents;

  ReminderIntent? byId(String id) {
    for (final i in _intents) {
      if (i.id == id) {
        return i;
      }
    }
    return null;
  }

  /// Adds or replaces a reminder, then schedules its next occurrence.
  Future<void> upsert(ReminderIntent intent) async {
    final list = _intents.where((i) => i.id != intent.id).toList()
      ..add(intent)
      ..sort((a, b) => a.id.compareTo(b.id));
    _intents = List.unmodifiable(list);
    await _saveIntents();
    await _scheduleOne(intent, tz.TZDateTime.now(_loc), reportMissed: false);
  }

  /// Removes a reminder and cancels its platform notification.
  Future<void> remove(String id) async {
    final notificationId = _notificationId(id);
    _intents = List.unmodifiable(_intents.where((i) => i.id != id));
    await _saveIntents();
    await _plugin.cancel(id: notificationId);
  }

  int _notificationId(String id) {
    // Stable 31-bit hash across sessions.
    var hash = 0;
    for (final rune in id.runes) {
      hash = (hash * 31 + rune) & 0x7FFFFFFF;
    }
    return hash;
  }

  /// The core reconciliation pass — call on every app resume.
  ///
  /// Detects timezone/offset drift, cancels every platform-side schedule,
  /// and rebuilds all of them from persisted intents. Reminders whose
  /// latest slot passed while the app was dead are reported as [missed]
  /// so the UI can surface them.
  Future<ReconcileReport> reconcile() async {
    assert(_initialized, 'call initialize() first');
    final prefs = await SharedPreferences.getInstance();
    final now = tz.TZDateTime.now(_loc);

    final lastTz = prefs.getString(_lastTzKey);
    final lastOffset = prefs.getInt(_lastOffsetKey);
    final currentTz = _loc.name;
    final currentOffset = now.timeZoneOffset.inMilliseconds;
    final tzChanged = lastTz != null && lastTz != currentTz;
    final offsetChanged = lastOffset != null && lastOffset != currentOffset;

    await prefs.setString(_lastTzKey, currentTz);
    await prefs.setInt(_lastOffsetKey, currentOffset);

    var rescheduled = 0;
    var missed = 0;

    await _plugin.cancelAll();
    for (final intent in _intents) {
      final report = await _scheduleOne(intent, now, reportMissed: true);
      rescheduled++;
      missed += report ? 1 : 0;
    }

    return ReconcileReport(
      rescheduled: rescheduled,
      missed: missed,
      timezoneChanged: tzChanged,
      offsetChanged: offsetChanged,
    );
  }

  /// Schedules the next slot for one intent. Returns true when the slot
  /// that should have covered [now] already passed (a miss).
  Future<bool> _scheduleOne(
    ReminderIntent intent,
    tz.TZDateTime now, {
    required bool reportMissed,
  }) async {
    final next = intent.nextFire(now);
    final missed = reportMissed && next.isBefore(now);
    final when = missed ? tz.TZDateTime.now(_loc) : next;

    final androidDetails = AndroidNotificationDetails(
      'prism_alerts',
      'Reminders',
      importance: Importance.max,
      priority: Priority.high,
    );
    final iosDetails = const DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      id: _notificationId(intent.id),
      title: intent.title,
      body: intent.body,
      scheduledDate: when,
      notificationDetails:
          NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: intent.payload,
    );
    return missed;
  }

  /// Cancels every platform-side notification (kept intents on disk).
  Future<void> cancelAllPlatform() => _plugin.cancelAll();
}

/// Convenience: true when running on a platform with local notification
/// support.
bool get platformSupportsLocalNotifications =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
