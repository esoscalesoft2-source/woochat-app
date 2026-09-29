import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/templates_repository.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_composer.dart';
import 'package:woochat_mobile/src/features/chat/widgets/schedule_message_sheet.dart';
import 'package:woochat_mobile/src/theme/app_theme.dart';

void main() {
  group('Schedule message sheet', () {
    /// Opens the sheet the way the app does — from the composer's clock icon,
    /// under the real theme. Both matter: the app-wide filled button style is
    /// full width, which is an infinite width inside the sheet's button Row.
    // A recent inbound keeps the 24-hour window open, so the dialog offers
    // the free-form path; without it every time needs a template.
    final recentInbound = DateTime.now().subtract(const Duration(hours: 1));
    const templates = <MessageTemplate>[
      MessageTemplate(
        id: 't1',
        name: 'order_update',
        language: 'en_US',
        body: 'Hi {{1}}, your order {{2}} is on the way.',
      ),
    ];

    Future<void> openFromComposer(
      WidgetTester tester, {
      String draft = 'Hello',
      Size size = const Size(390, 844),
      DateTime? lastInboundAt,
      bool inboundGiven = true,
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
                  onSchedule: (_, _, _) async => true,
                  lastInboundAt:
                      inboundGiven ? (lastInboundAt ?? recentInbound) : null,
                  loadTemplates: () async => templates,
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
      // The chat box's text comes over into the sheet's own box, where it
      // can still be changed.
      expect(find.text('Message'), findsOneWidget);
      final box = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('schedule-message')),
      );
      expect(box.controller?.text, 'Hello');
    });

    testWidgets('with the window closed, a template is required', (tester) async {
      await openFromComposer(tester, inboundGiven: false);

      expect(
        find.textContaining('outside the 24-hour window'),
        findsOneWidget,
      );
      // Schedule is off until a template and its params are filled.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Schedule'),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey<String>('schedule-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('order_update').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('schedule-param-1')),
        'Vijay',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('schedule-param-2')),
        '#5678',
      );
      await tester.pump();

      // Preview renders the filled body.
      expect(
        find.textContaining('Hi Vijay, your order #5678 is on the way.'),
        findsOneWidget,
      );
      final ready = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Schedule'),
      );
      expect(ready.onPressed, isNotNull);
    });

    testWidgets('an empty draft leaves Schedule disabled', (tester) async {
      await openFromComposer(tester, draft: '');

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Schedule'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Type the message to schedule'), findsOneWidget);
    });

    testWidgets('a message typed in the sheet is what gets queued',
        (tester) async {
      // Nothing in the chat box: the whole message is written here.
      ScheduledSend? queued;
      var draftSeen = '';
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const Expanded(child: SizedBox()),
                MessageComposer(
                  onSend: (_) async => true,
                  windowOpen: true,
                  onTemplates: () {},
                  onAttach: (_) {},
                  onSchedule: (send, draft, _) async {
                    queued = send;
                    draftSeen = draft;
                    return true;
                  },
                  lastInboundAt: recentInbound,
                  loadTemplates: () async => templates,
                  onBlocked: () {},
                  onVoiceNote: (_) async => true,
                  onRecorderProblem: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('schedule-message')),
        '  Kalai vanakkam  ',
      );
      await tester.pump();

      final ready = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Schedule'),
      );
      expect(ready.onPressed, isNotNull, reason: 'typing here should arm it');

      await tester.tap(find.widgetWithText(FilledButton, 'Schedule'));
      await tester.pumpAndSettle();

      expect(queued?.isTemplate, isFalse);
      expect(queued?.body, 'Kalai vanakkam');
      expect(draftSeen, 'Kalai vanakkam');
    });

    testWidgets('editing the carried-over text queues the edit, not the draft',
        (tester) async {
      ScheduledSend? queued;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const Expanded(child: SizedBox()),
                MessageComposer(
                  onSend: (_) async => true,
                  windowOpen: true,
                  onTemplates: () {},
                  onAttach: (_) {},
                  onSchedule: (send, _, _) async {
                    queued = send;
                    return true;
                  },
                  lastInboundAt: recentInbound,
                  loadTemplates: () async => templates,
                  onBlocked: () {},
                  onVoiceNote: (_) async => true,
                  onRecorderProblem: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('schedule-message')),
        'Hello again',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Schedule'));
      await tester.pumpAndSettle();

      expect(queued?.body, 'Hello again');
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
