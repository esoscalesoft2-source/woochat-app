import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/schedule_rules.dart';

void main() {
  final now = DateTime(2026, 9, 15, 12, 0);
  final anHourAgo = now.subtract(const Duration(hours: 1));
  final twoDaysAgo = now.subtract(const Duration(days: 2));

  group('isWindowOpen', () {
    test('open while the customer wrote in within 24 hours', () {
      expect(ScheduleRules.isWindowOpen(anHourAgo, now: now), isTrue);
      expect(
        ScheduleRules.isWindowOpen(
          now.subtract(const Duration(hours: 23, minutes: 59)),
          now: now,
        ),
        isTrue,
      );
    });

    test('closed past 24 hours, and when they never wrote', () {
      expect(ScheduleRules.isWindowOpen(twoDaysAgo, now: now), isFalse);
      expect(
        ScheduleRules.isWindowOpen(
          now.subtract(const Duration(hours: 24, minutes: 1)),
          now: now,
        ),
        isFalse,
      );
      expect(ScheduleRules.isWindowOpen(null, now: now), isFalse);
    });
  });

  group('withinWindow — may this send be free-form?', () {
    test('open window, soon: yes', () {
      expect(
        ScheduleRules.withinWindow(
          anHourAgo,
          now.add(const Duration(hours: 2)),
          now: now,
        ),
        isTrue,
      );
    });

    test('open window but more than 24h out: no — it closes before then', () {
      expect(
        ScheduleRules.withinWindow(
          anHourAgo,
          now.add(const Duration(hours: 25)),
          now: now,
        ),
        isFalse,
      );
      // Exactly 24h out is still allowed.
      expect(
        ScheduleRules.withinWindow(
          anHourAgo,
          now.add(const Duration(hours: 24)),
          now: now,
        ),
        isTrue,
      );
    });

    test('closed window: no, whatever the time', () {
      for (final at in <DateTime>[
        now.add(const Duration(minutes: 10)),
        now.add(const Duration(days: 3)),
      ]) {
        expect(ScheduleRules.withinWindow(twoDaysAgo, at, now: now), isFalse);
        expect(ScheduleRules.withinWindow(null, at, now: now), isFalse);
      }
    });
  });

  test('windowExpiresAt is the inbound plus 24 hours', () {
    expect(
      ScheduleRules.windowExpiresAt(anHourAgo),
      anHourAgo.add(const Duration(hours: 24)),
    );
    expect(ScheduleRules.windowExpiresAt(null), isNull);
  });
}
