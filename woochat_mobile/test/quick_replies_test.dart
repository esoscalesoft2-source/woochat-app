import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/shortcuts_repository.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_composer.dart';
import 'package:woochat_mobile/src/features/chat/widgets/quick_replies_panel.dart';

const replies = <QuickReply>[
  QuickReply(
    id: '1',
    title: '10dayswelcomenote',
    message: 'Hi! Welcome to Vicky\'s TRX — 10 DAYS FEMALE SPECIAL CAMP',
  ),
  QuickReply(
    id: '2',
    title: '50dayswelcomenote',
    message: 'Hi! 50 DAYS 10 KG WEIGHT LOSS CHALLENGE',
  ),
  QuickReply(id: '3', title: '50step1', message: 'Separate camp training'),
  QuickReply(id: '4', title: 'thanks', message: 'Thank you for the 50 days!'),
];

void main() {
  group('quickReplyQuery', () {
    test('a bare slash opens the menu with an empty query', () {
      expect(quickReplyQuery('/'), '');
    });

    test('the token after the slash is the query', () {
      expect(quickReplyQuery('/50step'), '50step');
    });

    test('text that does not start with a slash never opens it', () {
      expect(quickReplyQuery('hello'), isNull);
      expect(quickReplyQuery('see https://x.com/y'), isNull);
      expect(quickReplyQuery(' /50'), isNull);
    });

    test('a space closes it, so a real message is never hijacked', () {
      expect(quickReplyQuery('/50 kg'), isNull);
      expect(quickReplyQuery('/50\n'), isNull);
    });
  });

  group('filterQuickReplies', () {
    test('an empty query offers everything', () {
      expect(filterQuickReplies(replies, '').length, 4);
    });

    test('a title match ranks above a body match', () {
      final found = filterQuickReplies(replies, '50');

      // '50days…' and '50step1' start with it; 'thanks' only mentions 50.
      expect(found.map((reply) => reply.title).toList(), <String>[
        '50dayswelcomenote',
        '50step1',
        'thanks',
      ]);
    });

    test('matching ignores case', () {
      expect(filterQuickReplies(replies, 'THANKS').single.title, 'thanks');
    });

    test('no match returns nothing rather than everything', () {
      expect(filterQuickReplies(replies, 'zzz'), isEmpty);
    });
  });

  group('QuickReply.fromMap', () {
    test('a title saved with a slash is stored without one', () {
      final reply = QuickReply.fromMap(<String, dynamic>{
        'id': 7,
        'title': '/welcome',
        'message': ' hello ',
      });

      expect(reply.title, 'welcome');
      expect(reply.message, 'hello');
      expect(reply.id, '7');
    });
  });

  group('the composer slash menu', () {
    /// [loads] counts the fetches so a test can prove it happens once.
    Future<void> pump(
      WidgetTester tester, {
      List<QuickReply> available = replies,
      List<int>? loads,
    }) async {
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
              loadQuickReplies: () async {
                loads?.add(1);
                return available;
              },
            ),
          ),
        ),
      );
    }

    testWidgets('typing / lists every quick reply', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('/10dayswelcomenote'), findsOneWidget);
      expect(find.text('/50dayswelcomenote'), findsOneWidget);
      expect(find.text('/50step1'), findsOneWidget);
      expect(find.text('/thanks'), findsOneWidget);
    });

    testWidgets('typing narrows the list', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), '/50step');
      await tester.pumpAndSettle();

      expect(find.text('/50step1'), findsOneWidget);
      expect(find.text('/10dayswelcomenote'), findsNothing);
    });

    testWidgets('picking one replaces the slash with the message',
        (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), '/50step');
      await tester.pumpAndSettle();
      await tester.tap(find.text('/50step1'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'Separate camp training');
      // The menu closes once a reply is in the box.
      expect(find.text('/50step1'), findsNothing);
    });

    testWidgets('ordinary text never opens the menu', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'hello there');
      await tester.pumpAndSettle();

      expect(find.byType(QuickRepliesPanel), findsNothing);
    });

    testWidgets('a space after the token closes the menu again',
        (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), '/50');
      await tester.pumpAndSettle();
      expect(find.byType(QuickRepliesPanel), findsOneWidget);

      await tester.enterText(find.byType(TextField), '/50 kg lost');
      await tester.pumpAndSettle();
      expect(find.byType(QuickRepliesPanel), findsNothing);
    });

    testWidgets('the replies are fetched once, not on every keystroke',
        (tester) async {
      final loads = <int>[];
      await pump(tester, loads: loads);

      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '/50');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '/50s');
      await tester.pumpAndSettle();

      expect(loads.length, 1);
      expect(find.text('/50step1'), findsOneWidget);
    });

    testWidgets('an empty shortcuts table says so', (tester) async {
      await pump(tester, available: const <QuickReply>[]);

      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();

      expect(find.text('No quick reply matches that.'), findsOneWidget);
    });
  });
}
