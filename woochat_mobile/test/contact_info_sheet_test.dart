import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/contact_info_sheet.dart';
import 'package:woochat_mobile/src/models/chat.dart';
import 'package:woochat_mobile/src/data/summaries_repository.dart';
import 'package:woochat_mobile/src/models/chat_filters.dart';

void main() {
  final chat = Chat(
    id: 'c1',
    userId: 'u1',
    contactName: 'Asha',
    contactPhone: '+91 98765 43210',
    lastMessageAt: DateTime(2026, 9, 8, 15, 28),
  );

  Future<void> open(
    WidgetTester tester, {
    String? assignedName,
    List<String> labels = const <String>['Hot Lead'],
    List<String> categories = const <String>[],
    List<int>? copies,
    Chat? chatOverride,
    String? contactName,
    String? productName,
    List<Note> notes = const <Note>[],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showContactInfoSheet(
                context,
                chat: chatOverride ?? chat,
                contactName: contactName,
                productName: productName,
                notes: notes,
                assignedName: assignedName,
                labels: labels,
                categories: categories,
                onCopyNumber: () => copies?.add(1),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('Contact info sheet', () {
    testWidgets('prefers the Contacts-page name over the chat name',
        (tester) async {
      await open(tester, contactName: 'Fi00008-Asha');

      expect(find.text('Fi00008-Asha'), findsOneWidget);
      expect(find.text('Asha'), findsNothing);
    });

    testWidgets('shows the ad the chat came from and the product',
        (tester) async {
      await open(
        tester,
        chatOverride: Chat(
          id: 'c1',
          userId: 'u1',
          contactName: 'Asha',
          contactPhone: '919876543210',
          lastAdHeadline: 'Thala & Thalapathy Fan T-Shirts',
        ),
        productName: 'gym2.0',
      );

      expect(find.text('Came from ad'), findsOneWidget);
      expect(find.text('Thala & Thalapathy Fan T-Shirts'), findsOneWidget);
      expect(find.text('Product'), findsOneWidget);
      expect(find.text('gym2.0'), findsOneWidget);
    });

    testWidgets('hides the ad and product rows when there is nothing',
        (tester) async {
      await open(tester);

      expect(find.text('Came from ad'), findsNothing);
      expect(find.text('Product'), findsNothing);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('None'), findsNWidgets(2)); // categories + notes
    });

    testWidgets('lists every note with its tags', (tester) async {
      await open(
        tester,
        notes: <Note>[
          Note(
            id: 'n2',
            text: 'Returned parcel',
            tags: const <String>['return'],
            createdAt: DateTime(2026, 9, 10, 10, 0),
          ),
          const Note(id: 'n1', text: 'Wants XL'),
        ],
      );

      expect(find.text('Returned parcel'), findsOneWidget);
      expect(find.text('Wants XL'), findsOneWidget);
      expect(find.textContaining('#return'), findsOneWidget);
    });

    testWidgets('shows the name and number', (tester) async {
      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Asha'), findsOneWidget);
      // Once under the avatar, once as the Copy number value — and without
      // the 91 the row is stored with.
      expect(find.text('9876543210'), findsNWidgets(2));
      expect(find.text('+91 98765 43210'), findsNothing);
    });

    testWidgets('spells out an empty assignment rather than hiding the row',
        (tester) async {
      await open(tester);

      expect(find.text('Assigned to'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
    });

    testWidgets('lists the labels and says None for empty categories',
        (tester) async {
      await open(tester, assignedName: 'priyalaxmi kangeyam');

      expect(find.text('priyalaxmi kangeyam'), findsOneWidget);
      expect(find.text('Hot Lead'), findsOneWidget);
      // Categories and Notes are both empty here.
      expect(find.text('None'), findsNWidgets(2));
    });

    testWidgets('tapping Copy number reports it', (tester) async {
      final copies = <int>[];
      await open(tester, copies: copies);

      await tester.tap(find.text('Copy number'));
      await tester.pumpAndSettle();

      expect(copies.length, 1);
    });
  });

  group('Summary section', () {
    final existing = <ChatSummary>[
      ChatSummary(
        id: 's1',
        text: 'Wants 2 track pants, XL, COD',
        dayNumber: 2,
        createdAt: DateTime(2026, 9, 15, 16, 20),
      ),
      const ChatSummary(id: 's2', text: 'Asked about gym tees'),
    ];

    Future<List<String>> open(
      WidgetTester tester, {
      List<ChatSummary>? summaries,
      bool canAdd = true,
    }) async {
      final added = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showContactInfoSheet(
                  context,
                  chat: chat,
                  assignedName: null,
                  labels: const <String>[],
                  categories: const <String>[],
                  onCopyNumber: () {},
                  loadSummaries: () async => summaries ?? existing,
                  addSummary: canAdd
                      ? (text) async {
                          added.add(text);
                          return ChatSummary(id: 'new', text: text);
                        }
                      : null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return added;
    }

    testWidgets('shows the summaries in full, newest first, on the page',
        (tester) async {
      await open(tester);

      expect(find.text('Summary'), findsOneWidget);
      await tester.ensureVisible(find.text('Asked about gym tees'));
      expect(find.text('Wants 2 track pants, XL, COD'), findsOneWidget);
      expect(find.text('Asked about gym tees'), findsOneWidget);
      expect(find.textContaining('Day 2'), findsOneWidget);
    });

    testWidgets('says Nothing yet when there are none', (tester) async {
      await open(tester, summaries: const <ChatSummary>[]);
      await tester.ensureVisible(find.text('Nothing yet.'));
      expect(find.text('Nothing yet.'), findsOneWidget);
    });

    testWidgets('Add writes a new summary and shows it first', (tester) async {
      final added = await open(tester);

      await tester.ensureVisible(find.byKey(const ValueKey<String>('summary-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('summary-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('summary-text')),
        'Confirmed order, paid',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(added, <String>['Confirmed order, paid']);
      expect(find.text('Confirmed order, paid'), findsOneWidget);
    });

    testWidgets('no Add without permission to write', (tester) async {
      await open(tester, canAdd: false);
      expect(find.byKey(const ValueKey<String>('summary-add')), findsNothing);
    });

    testWidgets('opens as a page with a back arrow, not a sheet',
        (tester) async {
      await open(tester);
      expect(find.text('Contact info'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
    });
  });
}
