// Copyright 2026 Awais Rehman. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:timezone/timezone.dart' as tz;

/// How a reminder repeats.
enum Recurrence {
  /// Fires once.
  never,

  /// Fires every day at the reminder's local time.
  daily,

  /// Fires every [RecurrenceSpec.weekdays] at the reminder's local time.
  weekly,

  /// Fires every [RecurrenceSpec.intervalDays] days at the reminder's local
  /// time.
  interval,
}

/// Local-wall-clock recurrence for a reminder.
///
/// The OS stores a single UTC instant; this spec stores what the user
/// *meant* ("08:00 every day") so the schedule can be rebuilt after a
/// timezone change, a DST shift, or a reboot.
class RecurrenceSpec {
  const RecurrenceSpec({
    required this.recurrence,
    this.weekdays = const <int>[],
    this.intervalDays = 1,
  });

  factory RecurrenceSpec.daily() =>
      const RecurrenceSpec(recurrence: Recurrence.daily);

  factory RecurrenceSpec.weekly(Set<int> weekdays) => RecurrenceSpec(
        recurrence: Recurrence.weekly,
        weekdays: weekdays.toList()..sort(),
      );

  factory RecurrenceSpec.every(int days) => RecurrenceSpec(
        recurrence: Recurrence.interval,
        intervalDays: days,
      );

  final Recurrence recurrence;

  /// ISO weekdays (1 = Monday … 7 = Sunday) for [Recurrence.weekly].
  final List<int> weekdays;

  final int intervalDays;

  Map<String, Object?> toJson() => <String, Object?>{
        'recurrence': recurrence.index,
        'weekdays': weekdays,
        'intervalDays': intervalDays,
      };

  static RecurrenceSpec fromJson(Map<String, Object?> json) {
    final wd = (json['weekdays'] as List<Object?>? ?? const [])
        .whereType<int>()
        .toList();
    return RecurrenceSpec(
      recurrence: Recurrence.values[json['recurrence']! as int],
      weekdays: wd,
      intervalDays: json['intervalDays'] as int? ?? 1,
    );
  }
}

/// A reminder the user meant — local time, recurrence, and payload.
class ReminderIntent {
  const ReminderIntent({
    required this.id,
    required this.title,
    required this.localHour,
    required this.localMinute,
    this.body,
    this.recurrence = const RecurrenceSpec(recurrence: Recurrence.never),
    this.payload,
    this.startDate,
  });

  /// Stable id — also used as the platform notification id (mod 2^31).
  final String id;

  final String title;
  final String? body;

  /// The wall-clock hour the user meant, in the *device's* local time.
  final int localHour;
  final int localMinute;

  final RecurrenceSpec recurrence;

  /// Opaque payload handed back through the notification response.
  final String? payload;

  /// First date the reminder applies to (defaults to today).
  final DateTime? startDate;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'body': body,
        'localHour': localHour,
        'localMinute': localMinute,
        'recurrence': recurrence.toJson(),
        'payload': payload,
        'startDate': startDate?.toIso8601String(),
      };

  static ReminderIntent fromJson(Map<String, Object?> json) =>
      ReminderIntent(
        id: json['id']! as String,
        title: json['title']! as String,
        body: json['body'] as String?,
        localHour: json['localHour']! as int,
        localMinute: json['localMinute']! as int,
        recurrence:
            RecurrenceSpec.fromJson(json['recurrence']! as Map<String, Object?>),
        payload: json['payload'] as String?,
        startDate: json['startDate'] == null
            ? null
            : DateTime.parse(json['startDate']! as String),
      );

  /// Computes the next [tz.TZDateTime] this reminder should fire at or
  /// after [now], in [now]'s timezone — the *rebuilt* schedule.
  tz.TZDateTime nextFire(tz.TZDateTime now) {
    tz.TZDateTime slot(int y, int m, int d) =>
        tz.TZDateTime(now.location, y, m, d, localHour, localMinute);

    var day = slot(now.year, now.month, now.day);
    // Wall-clock date adder: TZDateTime.add advances absolute time and
    // drifts across DST; this keeps the local wall clock at the intent's
    // time-of-day.
    tz.TZDateTime nextDay(tz.TZDateTime d) =>
        tz.TZDateTime(now.location, d.year, d.month, d.day + 1, localHour,
            localMinute);
    if (startDate != null) {
      final start = slot(startDate!.year, startDate!.month, startDate!.day);
      if (day.isBefore(start)) {
        day = start;
      }
    }

    switch (recurrence.recurrence) {
      case Recurrence.never:
        // One-shot: return its slot even if in the past so the scheduler
        // can report a *missed* notification instead of dropping it.
        return day;

      case Recurrence.daily:
        while (day.isBefore(now)) {
          day = nextDay(day);
        }
        return day;

      case Recurrence.weekly:
        final target = recurrence.weekdays;
        var probe = day;
        for (var i = 0; i < 8; i++) {
          final weekday = probe.weekday; // 1 = Mon … 7 = Sun
          if (!probe.isBefore(now) && target.contains(weekday)) {
            return probe;
          }
          probe = nextDay(probe);
        }
        throw StateError('unreachable: weekly scan exceeded 8 days');

      case Recurrence.interval:
        final startSlot = startDate == null
            ? slot(now.year, now.month, now.day)
            : slot(startDate!.year, startDate!.month, startDate!.day);
        var probe = startSlot;
        while (probe.isBefore(now)) {
          // Step N wall-clock days: walk one day at a time so DST never
          // shifts the time-of-day.
          for (var i = 0; i < recurrence.intervalDays; i++) {
            probe = nextDay(probe);
          }
        }
        return probe;
    }
  }
}
