import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/chat_assignment_repository.dart';
import 'package:woochat_mobile/src/features/chat/widgets/assign_chat_sheet.dart';

void main() {
  group('Assign chat sheet', () {
    const members = <TeamMember>[
      TeamMember(userId: 'u1', name: 'priyalaxmi kangeyam'),
      TeamMember(userId: 'u2', name: 'Asha'),
    ];

    Future<List<String?>> open(
      WidgetTester tester, {
      String? assignedTo,
      List<TeamMember> people = members,
      bool writeSucceeds = true,
    }) async {
      final writes = <String?>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAssignChatSheet(
                  context,
                  members: people,
                  assignedTo: assignedTo,
                  onAssign: (userId) async {
                    writes.add(userId);
                    return writeSucceeds;
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
      return writes;
    }

    testWidgets('offers Unassigned plus every team member', (tester) async {
      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Unassigned'), findsOneWidget);
      expect(find.text('priyalaxmi kangeyam'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      // Nothing assigned yet, so Unassigned carries the tick.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('ticks whoever the chat is assigned to', (tester) async {
      await open(tester, assignedTo: 'u2');

      final ticked = find.ancestor(
        of: find.text('Asha'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: ticked, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });

    testWidgets('picking someone writes that id and closes', (tester) async {
      final writes = await open(tester);

      await tester.tap(find.text('priyalaxmi kangeyam'));
      await tester.pumpAndSettle();

      expect(writes, <String?>['u1']);
      expect(find.text('Assigned to'), findsNothing);
    });

    testWidgets('picking Unassigned clears it', (tester) async {
      final writes = await open(tester, assignedTo: 'u1');

      await tester.tap(find.text('Unassigned'));
      await tester.pumpAndSettle();

      expect(writes, <String?>[null]);
    });

    testWidgets('a failed write keeps the sheet open', (tester) async {
      await open(tester, writeSucceeds: false);

      await tester.tap(find.text('Asha'));
      await tester.pumpAndSettle();

      // Nothing changed on the server, so the choice must not look made.
      expect(find.text('Assigned to'), findsOneWidget);
    });

    testWidgets('says so when there is nobody else to assign to',
        (tester) async {
      await open(tester, people: const <TeamMember>[]);

      expect(
        find.textContaining('No other team members are visible'),
        findsOneWidget,
      );
    });
  });
}
