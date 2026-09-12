import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chats/chat_filter_state.dart';
import 'package:woochat_mobile/src/features/chats/widgets/more_filters_sheet.dart';
import 'package:woochat_mobile/src/models/chat.dart';
import 'package:woochat_mobile/src/models/chat_filters.dart';

Chat chat(
  String id, {
  bool archived = false,
  String? adHeadline,
  String owner = 'tenant',
}) =>
    Chat(
      id: id,
      userId: owner,
      contactName: id,
      isArchived: archived,
      lastAdHeadline: adHeadline,
    );

const data = ChatFilterData(
  labels: <Label>[
    Label(id: 'l1', name: 'Hot Lead', color: '#ff0000'),
    Label(id: 'l2', name: 'hot lead'),
  ],
  labelIdsByChat: <String, List<String>>{
    'a': <String>['l1'],
    'b': <String>['l2'],
  },
  categories: <Category>[Category(id: 'c1', name: 'Retail')],
  categoryIdsByChat: <String, List<String>>{
    'a': <String>['c1'],
  },
  products: <Product>[Product(id: 'p1', title: 'Fitness Camp')],
  productIdByAdHeadline: <String, String>{'Camp Ad': 'p1'},
  automations: <Automation>[Automation(id: 'auto-1', name: 'Welcome flow')],
  adSourcedChatIds: <String>{'a'},
  funnelFailed: <String>{'b'},
  noteTags: <String>['billing'],
);

void main() {
  final chats = <Chat>[
    chat('a', adHeadline: 'Camp Ad'),
    chat('b'),
    chat('z', archived: true),
  ];

  Future<ChatFilterState?> open(
    WidgetTester tester, {
    ChatFilterState state = ChatFilterState.initial,
    List<Chat>? scoped,
  }) async {
    ChatFilterState? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showMoreFiltersSheet(
                  context,
                  scopedChats: scoped ?? chats,
                  data: data,
                  state: state,
                  signedInUserId: 'tenant',
                  signedInLabel: 'Me',
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
    return result;
  }

  testWidgets('lists all eight filters', (tester) async {
    await open(tester);

    expect(tester.takeException(), isNull);
    for (final label in <String>[
      'Archived',
      'Funnel failed',
      'Labels',
      'Categories',
      'Products',
      'Lead source',
      'Auto Reply',
      'Notes',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
    }
  });

  testWidgets('counts come from the loaded chat list', (tester) async {
    await open(tester);

    // One archived chat, one chat in the funnel-failed set.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Archived'),
          matching: find.byType(ListTile),
        ),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Funnel failed'),
          matching: find.byType(ListTile),
        ),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a duplicated label name is collapsed to one entry',
      (tester) async {
    await open(tester);

    await tester.tap(find.text('Labels'));
    await tester.pumpAndSettle();

    // 'Hot Lead' and 'hot lead' are the same label to a user.
    expect(find.text('Hot Lead'), findsOneWidget);
    expect(find.text('hot lead'), findsNothing);
    expect(find.text('UnAssigned'), findsOneWidget);
  });

  testWidgets('selecting Archived returns the archived state', (tester) async {
    ChatFilterState? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await showMoreFiltersSheet(
                  context,
                  scopedChats: chats,
                  data: data,
                  state: ChatFilterState.initial.selectLabel('l1'),
                  signedInUserId: 'tenant',
                  signedInLabel: 'Me',
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

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.tab, ContactTab.archived);
    // Archived clears the label filter.
    expect(captured!.labelId, isNull);
  });

  testWidgets('Lead source offers the Meta Ads / Organic split',
      (tester) async {
    await open(tester);

    await tester.tap(find.text('Lead source'));
    await tester.pumpAndSettle();

    expect(find.text('Meta Ads'), findsOneWidget);
    expect(find.text('Organic'), findsOneWidget);
  });

  testWidgets('Notes exposes a keyword field and the tag list', (tester) async {
    await open(tester);

    await tester.scrollUntilVisible(find.text('Notes'), 200);
    await tester.ensureVisible(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Search notes and tags'));
    await tester.pumpAndSettle();
    expect(find.text('Search notes and tags'), findsOneWidget);
    expect(find.text('billing'), findsOneWidget);
  });

  // The Users pill was removed from the header, so this sheet is now the only
  // way to filter by owner.
  testWidgets('Team user lists every owner in the loaded chats',
      (tester) async {
    await open(
      tester,
      scoped: <Chat>[
        chat('a'),
        chat('b'),
        chat('c', owner: 'mate-01234567'),
      ],
    );

    await tester.scrollUntilVisible(find.text('Team user'), 200);
    await tester.ensureVisible(find.text('Team user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team user'));
    await tester.pumpAndSettle();

    expect(find.text('All users'), findsOneWidget);
    // The signed-in owner shows the label passed in, not the raw id.
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('User mate-012'), findsOneWidget);
  });

  testWidgets('picking a team user returns that owner', (tester) async {
    final chats = <Chat>[chat('a'), chat('c', owner: 'mate-01234567')];
    ChatFilterState? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await showMoreFiltersSheet(
                  context,
                  scopedChats: chats,
                  data: data,
                  state: ChatFilterState.initial,
                  signedInUserId: 'tenant',
                  signedInLabel: 'Me',
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

    await tester.scrollUntilVisible(find.text('Team user'), 200);
    await tester.ensureVisible(find.text('Team user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team user'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('User mate-012'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('User mate-012'));
    await tester.pumpAndSettle();

    expect(captured?.ownerId, 'mate-01234567');
  });

  testWidgets('Clear all appears only once something is narrowed',
      (tester) async {
    await open(tester);
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('Clear all is offered when a filter is active', (tester) async {
    await open(tester, state: ChatFilterState.initial.selectLabel('l1'));
    expect(find.text('Clear all'), findsOneWidget);
  });
}
