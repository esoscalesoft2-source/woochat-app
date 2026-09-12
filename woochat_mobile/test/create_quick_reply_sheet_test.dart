import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/shortcuts_repository.dart';
import 'package:woochat_mobile/src/features/chat/widgets/attach_menu.dart';
import 'package:woochat_mobile/src/features/chat/widgets/create_quick_reply_sheet.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_composer.dart';
import 'package:woochat_mobile/src/features/chat/widgets/quick_replies_panel.dart';
import 'package:woochat_mobile/src/theme/app_theme.dart';

void main() {
  group('Create quick reply sheet', () {
    Future<List<(String, String)>> open(
      WidgetTester tester, {
      bool fails = false,
    }) async {
      final saved = <(String, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCreateQuickReplySheet(
                  context,
                  save: (title, message) async {
                    if (fails) {
                      throw const ShortcutException(
                        'Could not save the quick reply: duplicate key',
                      );
                    }
                    saved.add((title, message));
                    return QuickReply(id: 'n', title: title, message: message);
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
      return saved;
    }

    testWidgets('slides up with a shortcut and a message field', (tester) async {
      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('New quick reply'), findsOneWidget);
      expect(find.text('Shortcut'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Save quick reply'), findsOneWidget);
    });

    testWidgets('saves the shortcut without its typed slash', (tester) async {
      final saved = await open(tester);

      await tester.enterText(find.byType(TextFormField).first, '/welcome');
      await tester.enterText(find.byType(TextFormField).last, 'Hi there!');
      await tester.tap(find.text('Save quick reply'));
      await tester.pumpAndSettle();

      expect(saved, <(String, String)>[('welcome', 'Hi there!')]);
      expect(find.text('New quick reply'), findsNothing);
    });

    testWidgets('a shortcut with spaces is refused', (tester) async {
      final saved = await open(tester);

      await tester.enterText(find.byType(TextFormField).first, 'hello there');
      await tester.enterText(find.byType(TextFormField).last, 'Hi');
      await tester.tap(find.text('Save quick reply'));
      await tester.pumpAndSettle();

      expect(find.text('Letters, numbers, _ and - only — no spaces'),
          findsOneWidget);
      expect(saved, isEmpty);
    });

    testWidgets('a failed save keeps the sheet open with the reason',
        (tester) async {
      await open(tester, fails: true);

      await tester.enterText(find.byType(TextFormField).first, 'welcome');
      await tester.enterText(find.byType(TextFormField).last, 'Hi');
      await tester.tap(find.text('Save quick reply'));
      await tester.pumpAndSettle();

      expect(find.textContaining('duplicate key'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('composer + Quick Replies', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool windowOpen,
      required Future<QuickReply?> Function() create,
      List<AttachOption>? attached,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              onSend: (_) async => true,
              windowOpen: windowOpen,
              onTemplates: () {},
              onAttach: (option) => attached?.add(option),
              onSchedule: (_) {},
              onBlocked: () {},
              onVoiceNote: (_) async => true,
              onRecorderProblem: (_) {},
              loadQuickReplies: () async => const <QuickReply>[
                QuickReply(id: '1', title: 'thanks', message: 'Thank you!'),
              ],
              onCreateQuickReply: create,
            ),
          ),
        ),
      );
    }

    testWidgets('works even while the 24-hour window is closed',
        (tester) async {
      var opened = 0;
      await pump(
        tester,
        windowOpen: false,
        create: () async {
          opened++;
          return null;
        },
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quick Replies'));
      await tester.pumpAndSettle();

      // Saving a reply sends nothing, so the closed window must not refuse it.
      expect(opened, 1);
    });

    testWidgets('a newly saved reply appears in the / menu at once',
        (tester) async {
      await pump(
        tester,
        windowOpen: true,
        create: () async =>
            const QuickReply(id: '2', title: 'hours', message: 'We open at 6.'),
      );

      // Load the list first, so the new reply has to be merged in.
      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      expect(find.text('/thanks'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quick Replies'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();

      expect(find.byType(QuickRepliesPanel), findsOneWidget);
      expect(find.text('/hours'), findsOneWidget);
      expect(find.text('/thanks'), findsOneWidget);
    });
  });
}
