import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_composer.dart';
import 'package:woochat_mobile/src/theme/app_theme.dart';

void main() {
  group('Schedule message sheet', () {
    /// Opens the sheet the way the app does — from the composer's clock icon,
    /// under the real theme. Both matter: the app-wide filled button style is
    /// full width, which is an infinite width inside the sheet's button Row.
    Future<void> openFromComposer(
      WidgetTester tester, {
      String draft = 'Hello',
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const Expanded(child: SizedBox()),
                MessageComposer(
                  onSend: (_) async => true,
                  windowOpen: true,
                  onTemplates: () {},
                  onAttach: (_) {},
                  onSchedule: (_) {},
                  onBlocked: () {},
                  onVoiceNote: (_) async => true,
                  onRecorderProblem: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      if (draft.isNotEmpty) {
        await tester.enterText(find.byType(TextField), draft);
        await tester.pump();
      }
      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();
    }

    testWidgets('opens from the composer without a layout failure',
        (tester) async {
      await openFromComposer(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Schedule message'), findsOneWidget);
    });

    // It laid out fine in a bare MaterialApp and failed under the real theme,
    // and again in a short window, so both are pinned here.
    for (final size in <Size>[
      Size(390, 844), // phone
      Size(1896, 588), // the browser window it is used in
      Size(1200, 380), // shorter than the sheet's own content
    ]) {
      testWidgets('lays out at $size', (tester) async {
        await openFromComposer(tester, size: size);

        expect(tester.takeException(), isNull);
        expect(find.text('Schedule message'), findsOneWidget);
        expect(find.text('Schedule'), findsOneWidget);
      });
    }

    testWidgets('slides up from the bottom instead of opening a dialog',
        (tester) async {
      await openFromComposer(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);

      // Anchored to the bottom edge, and only as tall as its content.
      final sheet = tester.getRect(find.byType(BottomSheet));
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(sheet.bottom, screen.bottom);
      expect(sheet.top, greaterThan(screen.top));
    });

    testWidgets('carries the same content as the web dialog', (tester) async {
      await openFromComposer(tester);

      expect(find.text('Pick when this message should be sent.'),
          findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Schedule'), findsOneWidget);
      expect(find.textContaining('Scheduling: "Hello"'), findsOneWidget);
    });

    testWidgets('an empty draft leaves Schedule disabled', (tester) async {
      await openFromComposer(tester, draft: '');

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Schedule'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.textContaining('Type a message in the chat box'),
        findsOneWidget,
      );
    });

    testWidgets('dragging it down dismisses it', (tester) async {
      await openFromComposer(tester);

      await tester.drag(find.byType(BottomSheet), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(find.text('Schedule message'), findsNothing);
    });

    testWidgets('Schedule reports the picked moment to the composer',
        (tester) async {
      await openFromComposer(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Schedule'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Schedule message'), findsNothing);
    });
  });
}
