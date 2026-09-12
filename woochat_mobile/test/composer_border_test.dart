import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_composer.dart';
import 'package:woochat_mobile/src/theme/app_theme.dart';

/// The app theme outlines and fills every field by default, so the composer
/// has to opt out explicitly or a second box appears inside the pill.
void main() {
  Future<void> pumpThemed(WidgetTester tester, {bool windowOpen = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: MessageComposer(
            onSend: (_) async => true,
            windowOpen: windowOpen,
            onTemplates: () {},
            onVoiceNote: (_) async => true,
            onRecorderProblem: (_) {},
            onAttach: (_) {},
            onSchedule: (_) {},
            onBlocked: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the message field opts out of the theme fill and outline',
      (tester) async {
    await pumpThemed(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    final decoration = field.decoration!;

    expect(decoration.filled, isFalse);
    expect(decoration.border, InputBorder.none);
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);
    // The field is disabled mid-send, which would otherwise fall back to the
    // theme's OutlineInputBorder.
    expect(decoration.disabledBorder, InputBorder.none);
  });

  testWidgets('the theme really would outline a bare field', (tester) async {
    // Guards the assumption above: if the theme stops outlining fields, the
    // opt-outs are no longer load-bearing and this test says so.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: TextField()),
      ),
    );
    await tester.pump();

    final theme = Theme.of(
      tester.element(find.byType(TextField)),
    ).inputDecorationTheme;

    expect(theme.filled, isTrue);
    expect(theme.border, isA<OutlineInputBorder>());
  });

  group('bar alignment', () {
    testWidgets('every control sits on the same centre line as the field',
        (tester) async {
      await pumpThemed(tester);

      final field = tester.getRect(find.byType(TextField));
      for (final icon in <IconData>[
        Icons.add,
        Icons.emoji_emotions_outlined,
        Icons.schedule,
      ]) {
        final rect = tester.getRect(find.byIcon(icon));
        // The + used to be 34px, the others 38, the field 46 — all bottom
        // aligned, so each landed at a different height.
        expect(
          rect.center.dy,
          closeTo(field.center.dy, 1),
          reason: '$icon is off the field\'s centre line',
        );
      }
    });

    testWidgets('the placeholder text sits on the icons\' centre line',
        (tester) async {
      await pumpThemed(tester);

      // The glyphs, not the field box: the box was already centred while the
      // text inside it rode a few pixels low.
      //
      // The field is padded 2px heavier at the bottom, calibrated against a
      // screenshot in the real Inter font, where glyphs sit low in the line
      // box. The test font has no such bias, so here the line box lands 2px
      // ABOVE the icons — that offset is the calibration, and this pins it.
      final hint = tester.getRect(find.text('Type a message'));
      final emoji = tester.getRect(find.byIcon(Icons.emoji_emotions_outlined));

      expect(hint.center.dy, closeTo(emoji.center.dy - 2, 1));
    });

    testWidgets('a single line is exactly the row height', (tester) async {
      await pumpThemed(tester);

      // The field pads itself to the row height, which is what makes
      // "bottom aligned" and "centred" coincide for one line of text.
      final field = tester.getRect(find.byType(TextField));
      expect(field.height, closeTo(kComposerRowHeight, 1));
    });

    testWidgets('icons follow the last line once the field grows',
        (tester) async {
      await pumpThemed(tester);

      await tester.enterText(
        find.byType(TextField),
        'line one\nline two\nline three',
      );
      await tester.pump();

      final field = tester.getRect(find.byType(TextField));
      final emoji = tester.getRect(find.byIcon(Icons.emoji_emotions_outlined));

      // Not centred on a tall field — level with its LAST line, as WhatsApp
      // does. That line's centre is half a row height above the bottom.
      expect(emoji.center.dy, greaterThan(field.center.dy));
      expect(
        emoji.center.dy,
        closeTo(field.bottom - kComposerRowHeight / 2, 2),
      );
    });
  });
}
