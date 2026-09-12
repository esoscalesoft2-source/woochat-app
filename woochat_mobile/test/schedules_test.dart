import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/schedules_repository.dart';
import 'package:woochat_mobile/src/features/chats/widgets/schedules_chip.dart';
import 'package:woochat_mobile/src/theme/wa_colors.dart';

void main() {
  group('ScheduledChatIds', () {
    const ids = ScheduledChatIds(
      all: <String>{'a', 'b', 'c'},
      pending: <String>{'a'},
      failed: <String>{'b', 'c'},
      failedActive: <String>{'b'},
      failedCount: 2,
    );

    test('each bucket maps to its own id set', () {
      expect(ids.bucket(ScheduleBucket.all), <String>{'a', 'b', 'c'});
      expect(ids.bucket(ScheduleBucket.failed), <String>{'b', 'c'});
      expect(ids.bucket(ScheduleBucket.failedActive), <String>{'b'});
    });

    test('hasPending drives the chip pulse', () {
      expect(ids.hasPending, isTrue);
      expect(ScheduledChatIds.empty.hasPending, isFalse);
      expect(ScheduledChatIds.empty.failedCount, 0);
    });
  });

  group('SchedulesChip', () {
    Future<void> pump(
      WidgetTester tester, {
      required ScheduleBucket? bucket,
      required bool hasPending,
      VoidCallback? onTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SchedulesChip(
                bucket: bucket,
                hasPending: hasPending,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    BoxDecoration decorationOf(WidgetTester tester) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(SchedulesChip),
              matching: find.byType(Container),
            )
            .first,
      );
      return container.decoration! as BoxDecoration;
    }

    testWidgets('off state is grey with no ring when nothing is pending',
        (tester) async {
      await pump(tester, bucket: null, hasPending: false);

      expect(tester.takeException(), isNull);
      expect(find.text('Schedules'), findsOneWidget);
      final decoration = decorationOf(tester);
      expect(decoration.color, Wa.chipInactiveBackground);
      expect(decoration.border, isNull);
    });

    testWidgets('pulses a ring while off with pending sends', (tester) async {
      await pump(tester, bucket: null, hasPending: true);
      await tester.pump(const Duration(milliseconds: 300));

      expect(decorationOf(tester).border, isNotNull);

      // The pulse is an animation, so let it settle rather than leaving a
      // pending timer behind.
      await pump(tester, bucket: null, hasPending: false);
    });

    testWidgets('active on all scheduled turns accent green', (tester) async {
      await pump(tester, bucket: ScheduleBucket.all, hasPending: true);

      expect(decorationOf(tester).color, Wa.chipActiveBackground);
      // Active chips never pulse.
      expect(decorationOf(tester).border, isNull);
      expect(find.text('Schedules'), findsOneWidget);
    });

    testWidgets('failure buckets turn red and rename the chip', (tester) async {
      await pump(tester, bucket: ScheduleBucket.failed, hasPending: false);
      expect(decorationOf(tester).color, Wa.scheduleFailed);
      expect(find.text('Schedules - Failed'), findsOneWidget);

      await pump(tester, bucket: ScheduleBucket.failedActive, hasPending: false);
      expect(decorationOf(tester).color, Wa.scheduleFailed);
      expect(find.text('Schedules - Failed'), findsOneWidget);
    });

    testWidgets('tapping fires the cycle callback', (tester) async {
      var taps = 0;
      await pump(
        tester,
        bucket: null,
        hasPending: false,
        onTap: () => taps++,
      );

      await tester.tap(find.byType(SchedulesChip));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
