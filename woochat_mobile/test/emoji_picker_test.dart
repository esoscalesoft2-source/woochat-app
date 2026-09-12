import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as ep;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/emoji_picker.dart';

Future<void> pumpPicker(
  WidgetTester tester, {
  ValueChanged<String>? onPick,
}) async {
  tester.view.physicalSize = const Size(400, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EmojiPicker(onPick: onPick ?? (_) {}, height: 300),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('emoji data', () {
    test('carries the full set, not a hand-written handful', () {
      final total = ep.defaultEmojiSet.fold<int>(
        0,
        (sum, category) => sum + category.emoji.length,
      );

      // The list this replaced had roughly 230 entries.
      expect(total, greaterThan(1000));
      expect(ep.defaultEmojiSet.length, greaterThanOrEqualTo(8));
    });

    test('every emoji carries a name to search by', () {
      final unnamed = ep.defaultEmojiSet
          .expand((category) => category.emoji)
          .where((emoji) => emoji.name.trim().isEmpty);

      expect(unnamed, isEmpty);
    });
  });

  group('EmojiPicker', () {
    testWidgets('shows a search field with the skin-tone button beside it',
        (tester) async {
      await pumpPicker(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Search'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // The hand sits next to the field, as in WhatsApp.
      expect(find.text('✋'), findsOneWidget);
    });

    testWidgets('search filters across every category', (tester) async {
      await pumpPicker(tester);

      await tester.enterText(find.byType(TextField), 'zzzznotanemoji');
      await tester.pump();
      expect(find.text('No emoji match that search'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'cat');
      await tester.pump();
      expect(find.text('No emoji match that search'), findsNothing);
    });

    testWidgets('the category strip hides while searching', (tester) async {
      await pumpPicker(tester);
      expect(find.byIcon(Icons.pets), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'cat');
      await tester.pump();

      // Results span all categories, so a per-category tab would mislead.
      expect(find.byIcon(Icons.pets), findsNothing);
    });

    testWidgets('tapping an emoji reports it', (tester) async {
      final picked = <String>[];
      await pumpPicker(tester, onPick: picked.add);

      final first = ep.defaultEmojiSet
          .firstWhere((category) => category.emoji.isNotEmpty)
          .emoji
          .first;

      await tester.tap(find.text(first.emoji).first);
      await tester.pump();

      expect(picked, <String>[first.emoji]);
    });
  });
}
