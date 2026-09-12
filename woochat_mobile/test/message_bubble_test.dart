import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_bubble.dart';
import 'package:woochat_mobile/src/models/message.dart';

Message message({
  required String body,
  bool outbound = true,
  String? status,
}) =>
    Message(
      id: 'm1',
      chatId: 'c1',
      userId: 'u1',
      direction:
          outbound ? MessageDirection.outbound : MessageDirection.inbound,
      content: body,
      status: status,
      createdAt: DateTime(2026, 9, 9, 15, 28),
    );

void main() {
  Future<Size> pump(
    WidgetTester tester,
    Message value, {
    Size screen = const Size(390, 844),
    bool tail = true,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Thread.background,
          body: MessageBubble(message: value, showTail: tail),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The bubble itself is the Container inside the Align, not the Align,
    // which fills the screen.
    return tester.getSize(
      find
          .descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Container),
          )
          .first,
    );
  }

  group('MessageBubble', () {
    testWidgets('shows the body and the timestamp', (tester) async {
      await pump(tester, message(body: 'Hlo'));

      expect(tester.takeException(), isNull);
      // The body shares a paragraph with the space reserved for the stamp,
      // so it is rich text.
      expect(find.textContaining('Hlo', findRichText: true), findsOneWidget);
      expect(find.textContaining('3:28', findRichText: true), findsOneWidget);
    });

    testWidgets('a short message stays on one line with the stamp beside it',
        (tester) async {
      final oneLine = await pump(tester, message(body: 'Hlo'));
      final twoLines = await pump(
        tester,
        message(body: 'Phone panna neega yedukave mattakuriga akka enna'),
      );

      // If the stamp took a row of its own, the short message would be as
      // tall as the wrapped one.
      expect(oneLine.height, lessThan(twoLines.height));
      // One 16px line, 13px of padding and the run gap — nothing more.
      expect(oneLine.height, lessThan(45));
    });

    testWidgets('the stamp never overlaps the text', (tester) async {
      // A message whose last line runs right up to where the stamp sits.
      await pump(
        tester,
        message(
          body: "Use 564073 Welcome to Vicky's TRX Family",
          status: MessageStatus.read,
        ),
      );

      final text = tester.getRect(find.byType(RichText).first);
      final stamp = tester.getRect(find.textContaining('3:28'));
      final ticks = tester.getRect(find.byIcon(Icons.done_all));

      // The stamp row must sit inside the space the text reserved for it,
      // never over the glyphs: its left edge is inside the paragraph's box
      // and the ticks end at its right edge.
      expect(stamp.left, greaterThan(text.left));
      expect(ticks.right, closeTo(text.right, 1));
      expect(stamp.right, lessThan(ticks.left));
    });

    testWidgets('a wide stamp reserves more room than a narrow one',
        (tester) async {
      final ticked = await pump(
        tester,
        message(body: 'Hlo', status: MessageStatus.read),
      );
      final plain = await pump(tester, message(body: 'Hlo', outbound: false));

      // Same text; the outbound bubble is wider by the ticks it also holds.
      // A fixed guess for the reservation could not know this.
      expect(ticked.width, greaterThan(plain.width));
    });

    testWidgets('never grows past 75% of the screen', (tester) async {
      final size = await pump(
        tester,
        message(
          body: 'Water: Not logged Workout: Not done Attendance: Not marked '
              'Keep it up! - Vickys TRX and then some more text again',
        ),
      );

      // getSize on the Container includes its 8px margin per side.
      expect(size.width, lessThanOrEqualTo(390 * 0.75 + 16));
    });

    testWidgets('a template message shows no template name', (tester) async {
      await pump(
        tester,
        Message(
          id: 'm2',
          chatId: 'c1',
          userId: 'u1',
          direction: MessageDirection.outbound,
          content: "Use 997296 Welcome to Vicky's TRX Family",
          templateName: 'welcome',
          createdAt: DateTime(2026, 9, 8, 9, 58),
        ),
      );

      expect(
        find.textContaining('Template', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Use 997296', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('an outbound message carries delivery ticks', (tester) async {
      await pump(
        tester,
        message(body: 'Hlo', status: MessageStatus.read),
      );

      expect(find.byIcon(Icons.done_all), findsOneWidget);
    });

    testWidgets('an inbound message carries none', (tester) async {
      await pump(tester, message(body: 'Illaiga', outbound: false));

      expect(find.byIcon(Icons.done_all), findsNothing);
      expect(find.byIcon(Icons.done), findsNothing);
    });

    testWidgets('the bubble is painted, tail and all', (tester) async {
      await pump(tester, message(body: 'Hlo'));

      // The shape is a CustomPaint rather than a BoxDecoration, because a
      // decoration cannot grow a tail.
      expect(
        find.descendant(
          of: find.byType(MessageBubble),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('an attachment keeps its stamp on the right, not the left',
        (tester) async {
      await pump(
        tester,
        message(
          body: '[attachment:audio|design%26sizechart.ogg'
              '|https%3A%2F%2Fx.test%2Fa.ogg]',
        ),
      );

      final bubble = tester.getRect(find.byType(MessageBubble));
      final stamp = tester.getRect(find.textContaining('3:28'));

      // With no caption to sit beside, the stamp used to hug the left edge.
      expect(stamp.center.dx, greaterThan(bubble.center.dx));
    });

    testWidgets('a bare picture fills the bubble and overlays its stamp',
        (tester) async {
      await pump(
        tester,
        message(
          body: '[attachment:image|shot.jpg|https%3A%2F%2Fx.test%2Fs.jpg]',
        ),
      );

      // The stamp is on the picture, in its own pill, not under it.
      expect(find.byType(Stack), findsWidgets);
      expect(find.textContaining('3:28'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a captioned picture keeps its frame', (tester) async {
      await pump(
        tester,
        message(
          body: '[attachment:image|shot.jpg|https%3A%2F%2Fx.test%2Fs.jpg]\n'
              'After 10day intha offers irrukuma mam',
        ),
      );

      expect(
        find.textContaining('After 10day', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bubble that opens a run sits lower than one tucked under it',
        (tester) async {
      final opening = await pump(tester, message(body: 'Hlo'));
      final tucked = await pump(tester, message(body: 'Hlo'), tail: false);

      // The run's first bubble takes the wider gap above it; the rest close up.
      expect(opening.height, greaterThan(tucked.height));
    });
  });
}
