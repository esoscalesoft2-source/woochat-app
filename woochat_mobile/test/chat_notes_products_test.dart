import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/chat_tags_sheet.dart';
import 'package:woochat_mobile/src/features/chats/widgets/chat_notes_sheet.dart';
import 'package:woochat_mobile/src/features/chats/widgets/chat_row_menu.dart';
import 'package:woochat_mobile/src/models/chat.dart';
import 'package:woochat_mobile/src/models/chat_filters.dart';

void main() {
  group('row menu', () {
    testWidgets('offers Notes and Products after Labels and Categories',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showChatRowMenu(
                  context,
                  chat: const Chat(id: 'c1', userId: 'u1', contactName: 'Mahi'),
                  canMarkUnread: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Products'), findsOneWidget);
    });
  });

  group('Products chooser (single select)', () {
    const products = <TagOption>[
      TagOption(id: 'p1', name: 'gym 1.0'),
      TagOption(id: 'p2', name: 'gym 2.0'),
    ];

    Future<List<(String, bool)>> open(WidgetTester tester) async {
      final calls = <(String, bool)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showChatTagsSheet(
                  context,
                  title: 'Products',
                  emptyMessage: 'No products yet.',
                  singleSelect: true,
                  options: products,
                  selected: const <String>{'p1'},
                  onToggle: (id, on) async {
                    calls.add((id, on));
                    return true;
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return calls;
    }

    Finder tick(String name) => find.descendant(
          of: find.widgetWithText(ListTile, name),
          matching: find.byIcon(Icons.check),
        );

    testWidgets('picking another product moves the single tick',
        (tester) async {
      final calls = await open(tester);
      expect(tick('gym 1.0'), findsOneWidget);

      await tester.tap(find.text('gym 2.0'));
      await tester.pumpAndSettle();

      expect(calls, <(String, bool)>[('p2', true)]);
      expect(tick('gym 2.0'), findsOneWidget);
      expect(tick('gym 1.0'), findsNothing);
    });

    testWidgets('tapping the ticked product clears it', (tester) async {
      final calls = await open(tester);

      await tester.tap(find.text('gym 1.0'));
      await tester.pumpAndSettle();

      expect(calls, <(String, bool)>[('p1', false)]);
      expect(tick('gym 1.0'), findsNothing);
    });
  });

  group('Notes sheet', () {
    final library = <Note>[
      Note(
        id: 'n1',
        text: 'Wants XL',
        tags: const <String>['size'],
        createdAt: DateTime(2026, 9, 10),
      ),
      Note(
        id: 'n2',
        text: 'Returned parcel',
        tags: const <String>['return'],
        createdAt: DateTime(2026, 9, 9),
      ),
    ];

    Future<({List<(String, bool)> toggles, Future<ChatNotesResult?> result})>
        open(
      WidgetTester tester, {
      String? contactId = 'ct1',
      Future<Note?> Function()? onCreate,
    }) async {
      final toggles = <(String, bool)>[];
      Future<ChatNotesResult?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showChatNotesSheet(
                    context,
                    chatName: 'Mahi',
                    contactId: contactId,
                    library: library,
                    attached: <Note>[library[1]],
                    onToggle: (note, attach) async {
                      toggles.add((note.id, attach));
                      return true;
                    },
                    onCreate: onCreate ?? () async => null,
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
      return (toggles: toggles, result: result!);
    }

    testWidgets('lists the library with the attached ones ticked',
        (tester) async {
      await open(tester);

      expect(find.text('Wants XL'), findsOneWidget);
      expect(find.text('Returned parcel'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    });

    testWidgets('tapping attaches or detaches and reports the final set',
        (tester) async {
      final opened = await open(tester);

      await tester.tap(find.text('Wants XL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Returned parcel'));
      await tester.pumpAndSettle();

      expect(opened.toggles, <(String, bool)>[('n1', true), ('n2', false)]);

      // Closing hands back what is attached now.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      final result = await opened.result;
      expect(result?.attached.map((n) => n.id), <String>['n1']);
    });

    testWidgets('search narrows by text and tag', (tester) async {
      await open(tester);

      await tester.enterText(
        find.byKey(const ValueKey<String>('notes-search')),
        'return',
      );
      await tester.pumpAndSettle();

      expect(find.text('Returned parcel'), findsOneWidget);
      expect(find.text('Wants XL'), findsNothing);
    });

    testWidgets('a number with no contact record is told what to do',
        (tester) async {
      await open(tester, contactId: null);

      expect(find.textContaining('Save this number as a Contact'),
          findsOneWidget);
      expect(find.text('Wants XL'), findsNothing);
      // Writing a note is still offered.
      expect(find.text('New note…'), findsOneWidget);
    });

    testWidgets('a new note goes to the top, attached', (tester) async {
      final opened = await open(
        tester,
        onCreate: () async => Note(
          id: 'n3',
          text: 'Call back Monday',
          createdAt: DateTime(2026, 9, 14),
        ),
      );

      await tester.tap(find.text('New note…'));
      await tester.pumpAndSettle();

      expect(find.text('Call back Monday'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      final result = await opened.result;
      expect(result?.created?.id, 'n3');
      expect(result?.attached.map((n) => n.id), <String>['n3', 'n2']);
    });
  });

  group('New note editor', () {
    Future<Future<(String, List<String>)?>> open(WidgetTester tester) async {
      Future<(String, List<String>)?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showNewNoteSheet(
                    context,
                    suggestedTags: const <String>['return', 'size'],
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

    testWidgets('save is disabled until there is text, and parses tags',
        (tester) async {
      final result = await open(tester);

      FilledButton save() => tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save note'),
          );
      expect(save().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey<String>('note-text')),
        '  Call back Monday ',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('note-tags')),
        'follow up, , urgent,follow up',
      );
      await tester.pump();
      expect(save().onPressed, isNotNull);

      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      final saved = await result;
      expect(saved?.$1, 'Call back Monday');
      expect(saved?.$2, <String>['follow up', 'urgent']);
    });

    testWidgets('a suggested tag chip fills the tags field', (tester) async {
      await open(tester);

      await tester.tap(find.text('return'));
      await tester.pump();
      await tester.tap(find.text('size'));
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('note-tags')),
      );
      expect(field.controller?.text, 'return, size');
    });
  });

  group('ChatFilterData helpers', () {
    test('withCollectionProduct sets and clears one customer', () {
      const data = ChatFilterData(
        collectionProductIdByPhone: <String, String>{'91a': 'p1'},
      );
      expect(
        data.withCollectionProduct('91b', 'p2').collectionProductIdByPhone,
        <String, String>{'91a': 'p1', '91b': 'p2'},
      );
      expect(
        data.withCollectionProduct('91a', null).collectionProductIdByPhone,
        isEmpty,
      );
    });

    test('withNote puts the new note first without duplicating', () {
      const old = Note(id: 'n1', text: 'a');
      const data = ChatFilterData(notes: <Note>[old]);
      const fresh = Note(id: 'n2', text: 'b');

      expect(data.withNote(fresh).notes.map((n) => n.id), <String>['n2', 'n1']);
      expect(
        data.withNote(old).notes.map((n) => n.id),
        <String>['n1'],
      );
    });
  });
}
