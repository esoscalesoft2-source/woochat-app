import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_bubble.dart';
import 'package:woochat_mobile/src/models/message.dart';

Message scheduled({
  String content = 'Follow up tomorrow',
  DateTime? at,
  String? errorCode,
  String? errorMessage,
  String status = MessageStatus.scheduled,
}) =>
    Message(
      id: 'm1',
      chatId: 'c1',
      userId: 'u1',
      direction: MessageDirection.outbound,
      content: content,
      status: status,
      scheduledAt: at ?? DateTime(2026, 9, 16, 9, 30),
      createdAt: DateTime(2026, 9, 15, 12, 0),
      sendErrorCode: errorCode,
      sendErrorMessage: errorMessage,
    );

void main() {
  Future<int> pump(WidgetTester tester, Message message) async {
    var cancels = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              MessageBubble(
                message: message,
                onCancelScheduled: message.isScheduled
                    ? () => cancels++
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
    return cancels;
  }

  group('Message model', () {
    test('reads the scheduling columns', () {
      final row = Message.fromMap(<String, dynamic>{
        'id': 'm1',
        'chat_id': 'c1',
        'direction': 'outbound',
        'status': 'scheduled',
        'content': 'Hi Vijay, your order is on the way.',
        'scheduled_at': '2026-09-16T04:00:00Z',
        'template_name': 'order_update',
        'template_language': 'en_US',
        'template_params': <dynamic>['Vijay', '#5678'],
        'send_error_code': 'META_131049',
      });

      expect(row.isScheduled, isTrue);
      expect(row.scheduledAt?.toUtc(), DateTime.utc(2026, 9, 16, 4));
      expect(row.templateName, 'order_update');
      expect(row.templateLanguage, 'en_US');
      expect(row.templateParams, <String>['Vijay', '#5678']);
      expect(row.isHeldByMarketingCap, isTrue);
    });

    test('a retry note is only read off a still-queued row', () {
      expect(
        scheduled(errorMessage: 'Network blip, retrying (2/3)').retryNote,
        'Network blip, retrying (2/3)',
      );
      // Not a retry note.
      expect(scheduled(errorMessage: 'Something else').retryNote, isNull);
      // Already sent: nothing to say.
      expect(
        scheduled(
          status: MessageStatus.sent,
          errorMessage: 'retrying (2/3)',
        ).retryNote,
        isNull,
      );
    });

    test('the marketing hold only counts while it is still queued', () {
      expect(
        scheduled(status: MessageStatus.sent, errorCode: 'META_131049')
            .isHeldByMarketingCap,
        isFalse,
      );
    });
  });

  group('scheduled bubble', () {
    testWidgets('stamps when it WILL go, with a clock instead of ticks',
        (tester) async {
      await pump(tester, scheduled());

      // scheduled_at, not created_at (which is 15 Sep).
      expect(find.text('16 Sep, 9:30 AM'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsNothing);
    });

    testWidgets('offers Cancel scheduled', (tester) async {
      var cancels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                MessageBubble(
                  message: scheduled(),
                  onCancelScheduled: () => cancels++,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Cancel scheduled'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('cancel-scheduled')));
      expect(cancels, 1);
    });

    testWidgets('a marketing hold says why and renames the action',
        (tester) async {
      await pump(tester, scheduled(errorCode: 'META_131049'));

      expect(
        find.textContaining("Held back by WhatsApp (customer's marketing"),
        findsOneWidget,
      );
      expect(find.textContaining('retries automatically at 16 Sep, 9:30 AM'),
          findsOneWidget);
      expect(find.text('Cancel auto resend'), findsOneWidget);
      expect(find.text('Cancel scheduled'), findsNothing);
    });

    testWidgets('a retry in progress shows the sender note', (tester) async {
      await pump(
        tester,
        scheduled(errorMessage: 'Temporary Meta error, retrying (2/3)'),
      );

      expect(find.textContaining('retrying (2/3)'), findsOneWidget);
      expect(find.text('Cancel scheduled'), findsOneWidget);
    });

    testWidgets('once sent it is an ordinary bubble again', (tester) async {
      await pump(tester, scheduled(status: MessageStatus.sent));

      expect(find.text('Cancel scheduled'), findsNothing);
      expect(find.byKey(const ValueKey<String>('scheduled-note')), findsNothing);
      // Back to created_at and a delivery tick.
      expect(find.byIcon(Icons.done), findsOneWidget);
    });

    testWidgets('the day-long stamp keeps clear of the text', (tester) async {
      // Wide enough that a two-letter message and the stamp share a line.
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pump(tester, scheduled(content: 'hi'));

      final body = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().startsWith('hi'),
      );
      final paragraph = tester.renderObject<RenderParagraph>(body);
      final wordsEnd = tester.getTopLeft(body).dx +
          paragraph
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 2),
              )
              .last
              .right;
      final stamp = tester.getRect(find.text('16 Sep, 9:30 AM'));

      // Same line, and a real gap — 8px read as the date running into the
      // words once the stamp carried a day.
      expect(stamp.top, lessThan(tester.getRect(body).bottom));
      expect(stamp.left - wordsEnd, greaterThanOrEqualTo(14));
    });
  });
}
