import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/chat_tags_sheet.dart';

void main() {
  group('Chat tags sheet', () {
    const options = <TagOption>[
      TagOption(id: 'l1', name: 'Hot Lead', color: '#ff0000'),
      TagOption(id: 'l2', name: 'Follow up'),
    ];

    Future<List<(String, bool)>> open(
      WidgetTester tester, {
      Set<String> selected = const <String>{},
      List<TagOption> items = options,
      bool writeSucceeds = true,
    }) async {
      final writes = <(String, bool)>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showChatTagsSheet(
                  context,
                  title: 'Labels',
                  emptyMessage: 'No labels exist in this workspace yet.',
                  options: items,
                  selected: selected,
                  onToggle: (id, applied) async {
                    writes.add((id, applied));
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

    testWidgets('lists every label with the applied ones ticked',
        (tester) async {
      await open(tester, selected: <String>{'l1'});

      expect(tester.takeException(), isNull);
      expect(find.text('Hot Lead'), findsOneWidget);
      expect(find.text('Follow up'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('tapping an unticked label applies it', (tester) async {
      final writes = await open(tester);

      await tester.tap(find.text('Hot Lead'));
      await tester.pumpAndSettle();

      expect(writes, <(String, bool)>[('l1', true)]);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('tapping a ticked label removes it', (tester) async {
      final writes = await open(tester, selected: <String>{'l1'});

      await tester.tap(find.text('Hot Lead'));
      await tester.pumpAndSettle();

      expect(writes, <(String, bool)>[('l1', false)]);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('a write that fails leaves the tick where it was',
        (tester) async {
      await open(tester, writeSucceeds: false);

      await tester.tap(find.text('Hot Lead'));
      await tester.pumpAndSettle();

      // The row was never created, so the sheet must not claim it was.
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('an empty workspace says so instead of showing a blank sheet',
        (tester) async {
      await open(tester, items: const <TagOption>[]);

      expect(
        find.text('No labels exist in this workspace yet.'),
        findsOneWidget,
      );
    });
  });
}
