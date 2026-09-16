import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/shortcuts_repository.dart';
import 'package:woochat_mobile/src/features/chat/widgets/quick_replies_sheet.dart';

void main() {
  const mine = QuickReply(
    id: 'r1',
    title: 'thanks',
    message: 'Thank you!',
    userId: 'me',
  );
  const theirs = QuickReply(
    id: 'r2',
    title: 'address',
    message: 'West street',
    userId: 'someone-else',
  );

  group('who may manage a reply', () {
    test('its owner may, and so may an admin', () {
      expect(
        mine.canBeManagedBy(authUserId: 'me', isAdmin: false),
        isTrue,
      );
      expect(
        theirs.canBeManagedBy(authUserId: 'me', isAdmin: true),
        isTrue,
      );
    });

    test('someone else\'s reply is not editable by a plain user', () {
      expect(
        theirs.canBeManagedBy(authUserId: 'me', isAdmin: false),
        isFalse,
      );
    });

    test('a reply with no recorded owner is left editable', () {
      const legacy = QuickReply(id: 'r3', title: 'x', message: 'y');
      expect(legacy.canBeManagedBy(authUserId: 'me', isAdmin: false), isTrue);
    });
  });

  group('Quick replies sheet management', () {
    late List<String> deleted;
    late List<String> edited;

    Future<void> open(
      WidgetTester tester, {
      List<QuickReply> replies = const <QuickReply>[mine, theirs],
      bool Function(QuickReply reply)? canManage,
      Future<void> Function(QuickReply reply)? delete,
      bool wireEdit = true,
    }) async {
      deleted = <String>[];
      edited = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showQuickRepliesSheet(
                  context,
                  load: () async => replies,
                  canManage: canManage,
                  edit: wireEdit
                      ? (reply) async {
                          edited.add(reply.id);
                          return QuickReply(
                            id: reply.id,
                            title: '${reply.title}_v2',
                            message: reply.message,
                            userId: reply.userId,
                          );
                        }
                      : null,
                  delete: delete ??
                      (reply) async {
                        deleted.add(reply.id);
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
    }

    testWidgets('every row carries an edit and a delete icon', (tester) async {
      await open(tester);

      expect(find.byTooltip('Edit /thanks'), findsOneWidget);
      expect(find.byTooltip('Delete /thanks'), findsOneWidget);
      expect(find.byTooltip('Edit /address'), findsOneWidget);
    });

    testWidgets('a reply the user may not manage shows no icons',
        (tester) async {
      await open(tester, canManage: (reply) => reply.id == 'r1');

      expect(find.byTooltip('Edit /thanks'), findsOneWidget);
      expect(find.byTooltip('Edit /address'), findsNothing);
      expect(find.byTooltip('Delete /address'), findsNothing);
    });

    testWidgets('delete asks first and does nothing when cancelled',
        (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Delete /thanks'));
      await tester.pumpAndSettle();

      expect(find.text('Delete /thanks?'), findsOneWidget);
      expect(
        find.textContaining('cannot be undone'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(deleted, isEmpty);
      expect(find.text('/thanks'), findsOneWidget);
    });

    testWidgets('confirming removes it from the list', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Delete /thanks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deleted, <String>['r1']);
      expect(find.text('/thanks'), findsNothing);
      expect(find.text('/address'), findsOneWidget);
    });

    testWidgets('a failed delete says why and keeps the row', (tester) async {
      await open(
        tester,
        delete: (reply) async => throw const ShortcutException(
          'Could not delete the quick reply: not allowed',
        ),
      );

      await tester.tap(find.byTooltip('Delete /thanks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not allowed'), findsOneWidget);
      expect(find.text('/thanks'), findsOneWidget);
    });

    testWidgets('an edit updates the row in place', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Edit /thanks'));
      await tester.pumpAndSettle();

      expect(edited, <String>['r1']);
      expect(find.text('/thanks_v2'), findsOneWidget);
      expect(find.text('/thanks'), findsNothing);
    });

    testWidgets('without an edit callback only delete is offered',
        (tester) async {
      await open(tester, wireEdit: false);

      expect(find.byTooltip('Edit /thanks'), findsNothing);
      expect(find.byTooltip('Delete /thanks'), findsOneWidget);
    });
  });
}
