// Copyright 2026 Awais Rehman. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:prism_alerts/src/intent.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  group('ReminderIntent.nextFire', () {
    test('one-shot today in the future fires today', () {
      final loc = tz.getLocation('UTC');
      final now = tz.TZDateTime(loc, 2026, 6, 1, 7);
      final intent = ReminderIntent(id: 'a', title: 'T', localHour: 9, localMinute: 0);
      final next = intent.nextFire(now);
      expect(next.year, 2026);
      expect(next.month, 6);
      expect(next.day, 1);
      expect(next.hour, 9);
    });

    test('one-shot in the past returns the past slot (miss reported)', () {
      final loc = tz.getLocation('UTC');
      final now = tz.TZDateTime(loc, 2026, 6, 1, 10);
      final intent = ReminderIntent(id: 'a', title: 'T', localHour: 9, localMinute: 0);
      final next = intent.nextFire(now);
      expect(next.hour, 9);
      expect(next.isBefore(now), isTrue);
    });

    test('daily rolls to tomorrow when today passed', () {
      final loc = tz.getLocation('UTC');
      final now = tz.TZDateTime(loc, 2026, 6, 1, 10);
      final intent = ReminderIntent(
        id: 'a',
        title: 'T',
        localHour: 8,
        localMinute: 0,
        recurrence: RecurrenceSpec.daily(),
      );
      final next = intent.nextFire(now);
      expect(next.day, 2);
      expect(next.hour, 8);
    });

    test('weekly picks the next matching weekday', () {
      final loc = tz.getLocation('UTC');
      // 2026-06-01 is a Monday.
      final now = tz.TZDateTime(loc, 2026, 6, 1, 10);
      final intent = ReminderIntent(
        id: 'a',
        title: 'T',
        localHour: 8,
        localMinute: 0,
        recurrence: RecurrenceSpec.weekly({1, 3, 5}), // Mon, Wed, Fri
      );
      final next = intent.nextFire(now);
      // Monday 08:00 passed → next is Wednesday 2026-06-03.
      expect(next.weekday, DateTime.wednesday);
      expect(next.day, 3);
    });

    test('interval respects the step', () {
      final loc = tz.getLocation('UTC');
      final start = DateTime(2026, 6, 1);
      final now = tz.TZDateTime(loc, 2026, 6, 4, 10);
      final intent = ReminderIntent(
        id: 'a',
        title: 'T',
        localHour: 8,
        localMinute: 0,
        recurrence: RecurrenceSpec.every(3),
        startDate: start,
      );
      // Anchored Jun 1 08:00, every 3 days: Jun 1, 4, 7… Jun 4 08:00 passed
      // (now is 10:00) → next Jun 7.
      final next = intent.nextFire(now);
      expect(next.day, 7);
      expect(next.hour, 8);
    });

    test('DST spring-forward: daily stays at local 08:00', () {
      final loc = tz.getLocation('Europe/Berlin');
      // DST starts 2026-03-29 02:00 → 03:00 in Berlin.
      final before = tz.TZDateTime(loc, 2026, 3, 28, 12);
      final intent = ReminderIntent(
        id: 'a',
        title: 'T',
        localHour: 8,
        localMinute: 0,
        recurrence: RecurrenceSpec.daily(),
      );
      final next = intent.nextFire(before);
      expect(next.day, 29);
      // Wall clock stays 08:00 even though the UTC offset changed.
      expect(next.hour, 8);
    });

    test('JSON round-trip preserves intent', () {
      final intent = ReminderIntent(
        id: 'med-1',
        title: 'Meds',
        localHour: 8,
        localMinute: 30,
        payload: 'x',
        recurrence: RecurrenceSpec.weekly({1, 4}),
      );
      final restored = ReminderIntent.fromJson(intent.toJson());
      expect(restored.id, 'med-1');
      expect(restored.localHour, 8);
      expect(restored.localMinute, 30);
      expect(restored.recurrence.weekdays, [1, 4]);
    });
  });
}
