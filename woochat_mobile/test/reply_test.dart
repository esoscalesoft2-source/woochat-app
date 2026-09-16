import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_composer.dart';
import 'package:woochat_mobile/src/features/chat/widgets/reply_strip.dart';
import 'package:woochat_mobile/src/models/message.dart';

Message msg(String content, {bool outbound = true}) => Message(
      id: 'm1',
      chatId: 'c1',
      userId: 'u1',
      direction: outbound ? 'outbound' : 'inbound',
      content: content,
    );

void main() {
  group('ReplyStrip', () {
    Future<int> pump(WidgetTester tester, Message message, {String name = 'You'}) async {
      var cancels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplyStrip(
              message: message,
              authorName: name,
              onCancel: () => cancels++,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Cancel reply'));
      return cancels;
    }

    testWidgets('quotes a text message under its author', (tester) async {
      final cancels = await pump(tester, msg('Black tshirt aa illa white?'), name: 'Mahi');

      expect(find.text('Mahi'), findsOneWidget);
      expect(find.text('Black tshirt aa illa white?'), findsOneWidget);
      expect(cancels, 1);
    });

    testWidgets('a bare photo reads as "Photo"', (tester) async {
      await pump(
        tester,
        msg(Message.attachmentMarker(
          type: 'image',
          name: 'a.jpg',
          url: 'https://x.test/a.jpg',
        )),
      );

      expect(find.text('Photo'), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('a captioned photo quotes the caption', (tester) async {
      await pump(
        tester,
        msg(Message.attachmentMarker(
          type: 'image',
          name: 'a.jpg',
          url: 'https://x.test/a.jpg',
          caption: 'Size chart',
        )),
      );

      expect(find.text('Size chart'), findsOneWidget);
      expect(find.text('Photo'), findsNothing);
    });

    testWidgets('audio and documents name themselves', (tester) async {
      await pump(
        tester,
        msg(Message.attachmentMarker(type: 'audio', name: 'v.ogg', url: 'u')),
      );
      expect(find.text('Audio'), findsOneWidget);

      await pump(
        tester,
        msg(Message.attachmentMarker(type: 'document', name: 'invoice.pdf', url: 'u')),
      );
      expect(find.text('invoice.pdf'), findsOneWidget);
    });
  });

  group('ReplyStrip warning', () {
    testWidgets('says so when WhatsApp cannot show the quote', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplyStrip(
              message: msg('hello'),
              authorName: 'You',
              warning: 'This message never reached WhatsApp, so the customer '
                  'will see your reply without the quote.',
              onCancel: () {},
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('reply-warning')), findsOneWidget);
      expect(find.textContaining('never reached WhatsApp'), findsOneWidget);
    });

    testWidgets('no warning for a delivered message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplyStrip(message: msg('hello'), authorName: 'You', onCancel: () {}),
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('reply-warning')), findsNothing);
    });
  });

  group('composer while replying', () {
    testWidgets('shows the strip and can drop it', (tester) async {
      var cancelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              onSend: (_) async => true,
              replyingTo: msg('hi', outbound: false),
              replyingToName: 'Mahi',
              onCancelReply: () => cancelled++,
              windowOpen: true,
              onTemplates: () {},
              onAttach: (_) {},
              onSchedule: (_, _, _) async => true,
              onBlocked: () {},
              onVoiceNote: (_) async => true,
              onRecorderProblem: (_) {},
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey<String>('reply-strip')), findsOneWidget);
      expect(find.text('Mahi'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel reply'));
      expect(cancelled, 1);
    });

    testWidgets('no reply, no strip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              onSend: (_) async => true,
              windowOpen: true,
              onTemplates: () {},
              onAttach: (_) {},
              onSchedule: (_, _, _) async => true,
              onBlocked: () {},
              onVoiceNote: (_) async => true,
              onRecorderProblem: (_) {},
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('reply-strip')), findsNothing);
    });
  });
}
