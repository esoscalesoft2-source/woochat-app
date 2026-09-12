import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/contact_info_sheet.dart';
import 'package:woochat_mobile/src/models/chat.dart';

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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showContactInfoSheet(
                context,
                chat: chat,
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
    testWidgets('shows the name and number', (tester) async {
      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Asha'), findsOneWidget);
      // Once under the avatar, once as the Copy number value.
      expect(find.text('+91 98765 43210'), findsNWidgets(2));
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
      expect(find.text('None'), findsOneWidget);
    });

    testWidgets('tapping Copy number reports it', (tester) async {
      final copies = <int>[];
      await open(tester, copies: copies);

      await tester.tap(find.text('Copy number'));
      await tester.pumpAndSettle();

      expect(copies.length, 1);
    });
  });
}
