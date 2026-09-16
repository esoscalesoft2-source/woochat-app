import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/forward_sheet.dart';
import 'package:woochat_mobile/src/models/chat.dart';
import 'package:woochat_mobile/src/models/message.dart';

void main() {
  final chats = <Chat>[
    for (var i = 1; i <= 7; i++)
      Chat(
        id: 'c$i',
        userId: 'u1',
        contactName: 'Chat $i',
        contactPhone: '9198765432$i$i',
      ),
  ];

  const forwarded = Message(
    id: 'm1',
    chatId: 'c1',
    userId: 'u1',
    direction: 'outbound',
    content: 'Size chart attached',
  );

  Future<Future<ForwardChoice?>> open(
    WidgetTester tester, {
    Chat? exclude,
  }) async {
    Future<ForwardChoice?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                result = showForwardSheet(
                  context,
                  message: forwarded,
                  loadChats: () async => chats,
                  nameOf: (chat) => 'Fi000${chat.id}-${chat.contactName}',
                  photoOf: (_) => null,
                  exclude: exclude,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result!;
  }

  testWidgets('lists chats by their directory name, minus the current one',
      (tester) async {
    await open(tester, exclude: chats.first);

    expect(find.text('Forward message to'), findsOneWidget);
    expect(find.text('Fi000c2-Chat 2'), findsOneWidget);
    expect(find.text('Fi000c1-Chat 1'), findsNothing);
    // Nothing picked yet, so no bottom bar at all.
    expect(find.byKey(const ValueKey<String>('forward-bar')), findsNothing);
  });

  testWidgets('search narrows by name or number', (tester) async {
    await open(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('forward-search')),
      'chat 3',
    );
    await tester.pumpAndSettle();
    expect(find.text('Fi000c3-Chat 3'), findsOneWidget);
    expect(find.text('Fi000c2-Chat 2'), findsNothing);

    // Digits only searches the number — c4 is …543244 — and spaces are fine.
    await tester.enterText(
      find.byKey(const ValueKey<String>('forward-search')),
      '32 44',
    );
    await tester.pumpAndSettle();
    expect(find.text('Fi000c4-Chat 4'), findsOneWidget);
    expect(find.text('Fi000c3-Chat 3'), findsNothing);
  });

  testWidgets(
      'ticking chats brings up the bar with the preview and names, '
      'and Send hands back the chats plus the extra message', (tester) async {
    final result = await open(tester);

    await tester.tap(find.text('Fi000c2-Chat 2'));
    await tester.tap(find.text('Fi000c3-Chat 3'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('forward-bar')), findsOneWidget);
    // What is being forwarded, previewed.
    expect(find.text('Size chart attached'), findsOneWidget);
    // Who it is going to, in the order picked.
    expect(find.text('Fi000c2-Chat 2, Fi000c3-Chat 3'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('forward-note')),
      '  Ithu paarunga  ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('forward-send')));
    await tester.pumpAndSettle();

    final choice = await result;
    expect(choice?.chats.map((c) => c.id), <String>['c2', 'c3']);
    expect(choice?.note, 'Ithu paarunga');
  });

  testWidgets('no extra message means an empty note', (tester) async {
    final result = await open(tester);

    await tester.tap(find.text('Fi000c2-Chat 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('forward-send')));
    await tester.pumpAndSettle();

    expect((await result)?.note, isEmpty);
  });

  testWidgets('a sixth chat is refused, like WhatsApp', (tester) async {
    await open(tester);

    for (var i = 1; i <= 6; i++) {
      // The bar along the bottom eats into the list once something is
      // picked, so later rows have to be scrolled to.
      await tester.ensureVisible(find.text('Fi000c$i-Chat $i'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fi000c$i-Chat $i'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Fi000c6-Chat 6'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('forward-recipients')),
        matching: find.textContaining('Chat 6'),
      ),
      findsNothing,
    );
    expect(find.textContaining('up to 5 chats'), findsOneWidget);
  });

  group('duplicate chat rows for one customer', () {
    Chat row(String id, String phone, {DateTime? at, String name = 'Gokila'}) =>
        Chat(
          id: id,
          userId: 'u1',
          contactName: name,
          contactPhone: phone,
          lastMessageAt: at,
        );

    test('the same number with and without 91 is one customer', () {
      expect(row('a', '6381318192').canonicalPhone, '916381318192');
      expect(row('b', '916381318192').canonicalPhone, '916381318192');
      expect(row('c', '+91 63813 18192').canonicalPhone, '916381318192');
      // Not Indian-shaped: left alone.
      expect(row('d', '441234567890').canonicalPhone, '441234567890');
    });

    test('onePerCustomer keeps the most recently active row', () {
      final kept = onePerCustomer(<Chat>[
        row('old', '916381318192', at: DateTime(2026, 9, 14)),
        row('newest', '6381318192', at: DateTime(2026, 9, 15, 12)),
        row('empty', '6381318192'),
        row('other', '919876543210', at: DateTime(2026, 9, 10)),
      ]);

      expect(kept.map((c) => c.id).toSet(), <String>{'newest', 'other'});
    });

    testWidgets('the picker offers a customer once and never the current one',
        (tester) async {
      final current = row('f66', '916381318192', at: DateTime(2026, 9, 15, 11));
      final all = <Chat>[
        current,
        row('461', '6381318192', at: DateTime(2026, 9, 15, 12), name: 'gokila'),
        row('40e', '916381318192', at: DateTime(2026, 9, 14)),
        row('a7b', '6381318192'),
        row('x1', '919876543210', at: DateTime(2026, 9, 1), name: 'Mahi'),
        row('x2', '919876543210', at: DateTime(2026, 9, 12), name: 'Mahi'),
      ];

      Future<ForwardChoice?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showForwardSheet(
                    context,
                    message: forwarded,
                    loadChats: () async => all,
                    nameOf: (chat) => '${chat.contactName}-${chat.id}',
                    photoOf: (_) => null,
                    exclude: current,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Every row for the customer on screen is gone — not just the exact
      // one — so the forward cannot land in a sibling row of the same chat.
      expect(find.textContaining('Gokila'), findsNothing);
      expect(find.textContaining('gokila'), findsNothing);
      // Mahi's two rows collapse to the most recent.
      expect(find.text('Mahi-x2'), findsOneWidget);
      expect(find.text('Mahi-x1'), findsNothing);

      await tester.tap(find.text('Mahi-x2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('forward-send')));
      await tester.pumpAndSettle();
      expect((await result)?.chats.single.id, 'x2');
    });
  });

  testWidgets('closing hands back nothing', (tester) async {
    final result = await open(tester);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });
}
