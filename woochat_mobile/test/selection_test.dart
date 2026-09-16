import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chats/widgets/chat_list_tile.dart';
import 'package:woochat_mobile/src/features/chats/widgets/selection_bar.dart';
import 'package:woochat_mobile/src/models/chat.dart';

void main() {
  group('SelectionBar', () {
    Future<List<SelectionAction>> pump(
      WidgetTester tester, {
      int count = 2,
      int total = 5,
      bool allPinned = false,
      bool allArchived = false,
      bool anyUnread = false,
      bool busy = false,
      VoidCallback? onExit,
      VoidCallback? onSelectAll,
    }) async {
      final actions = <SelectionAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionBar(
              count: count,
              total: total,
              allPinned: allPinned,
              allArchived: allArchived,
              anyUnread: anyUnread,
              busy: busy,
              onExit: onExit ?? () {},
              onSelectAll: onSelectAll ?? () {},
              onAction: actions.add,
            ),
          ),
        ),
      );
      return actions;
    }

    testWidgets('shows the count and offers Select all', (tester) async {
      var selectAll = 0;
      await pump(tester, onSelectAll: () => selectAll++);

      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('All (5)'));
      expect(selectAll, 1);
    });

    testWidgets('once everything is picked the button clears instead',
        (tester) async {
      await pump(tester, count: 5, total: 5);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('the buttons flip to the opposite of the current state',
        (tester) async {
      await pump(tester, allPinned: true, allArchived: true, anyUnread: true);

      expect(find.byTooltip('Unpin'), findsOneWidget);
      expect(find.byTooltip('Unarchive'), findsOneWidget);
      expect(find.byTooltip('Mark as read'), findsOneWidget);
    });

    testWidgets('every action reports itself', (tester) async {
      final actions = await pump(tester, count: 1);

      await tester.tap(find.byTooltip('Pin'));
      await tester.tap(find.byTooltip('Archive'));
      await tester.tap(find.byTooltip('Mark as unread'));
      await tester.tap(find.byTooltip('Assign to'));
      await tester.tap(find.byTooltip('More'));

      expect(actions, SelectionAction.values);
    });

    testWidgets('More is only for a single chat', (tester) async {
      await pump(tester, count: 2);
      final more = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.more_vert),
          matching: find.byType(IconButton),
        ),
      );
      expect(more.onPressed, isNull);
    });

    testWidgets('a bulk write in flight disables everything but shows why',
        (tester) async {
      await pump(tester, busy: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Pin'), findsNothing);
    });

    testWidgets('✕ leaves select mode', (tester) async {
      var exits = 0;
      await pump(tester, onExit: () => exits++);
      await tester.tap(find.byTooltip('Cancel selection'));
      expect(exits, 1);
    });
  });

  group('ChatListTile in select mode', () {
    const chat = Chat(
      id: 'c1',
      userId: 'u1',
      contactName: 'Mahi',
      lastMessage: 'hi',
    );

    Widget host({required bool selecting, required bool selected}) =>
        MaterialApp(
          home: Scaffold(
            body: ChatListTile(
              chat: chat,
              subtitleStamp: '',
              selecting: selecting,
              selected: selected,
              onTap: () {},
            ),
          ),
        );

    testWidgets('a picked row wears the green tick', (tester) async {
      await tester.pumpWidget(host(selecting: true, selected: true));
      expect(find.byKey(const ValueKey<String>('selected-tick')), findsOneWidget);
    });

    testWidgets('an unpicked row in select mode shows nothing extra',
        (tester) async {
      await tester.pumpWidget(host(selecting: true, selected: false));
      expect(find.byKey(const ValueKey<String>('selected-tick')), findsNothing);
    });

    testWidgets('outside select mode there is never a tick', (tester) async {
      await tester.pumpWidget(host(selecting: false, selected: true));
      expect(find.byKey(const ValueKey<String>('selected-tick')), findsNothing);
    });
  });
}
