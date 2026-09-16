import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/shortcuts_repository.dart';
import 'package:woochat_mobile/src/data/attachment_picker.dart';
import 'package:woochat_mobile/src/features/chat/widgets/attach_menu.dart';
import 'package:woochat_mobile/src/features/chat/widgets/create_quick_reply_sheet.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_composer.dart';
import 'package:woochat_mobile/src/features/chat/widgets/quick_replies_panel.dart';
import 'package:woochat_mobile/src/theme/app_theme.dart';

void main() {
  group('Create quick reply sheet', () {
    /// What the sheet handed to `save`, so a test can assert on it.
    final saved = <({String title, String message, List<QuickReplyMedia> media})>[];

    setUp(saved.clear);

    Future<void> open(
      WidgetTester tester, {
      bool fails = false,
      Future<QuickReplyMedia?> Function(String kind)? addMedia,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCreateQuickReplySheet(
                  context,
                  addMedia: addMedia,
                  save: (title, message, media) async {
                    if (fails) {
                      throw const ShortcutException(
                        'Could not save the quick reply: duplicate key',
                      );
                    }
                    saved.add((title: title, message: message, media: media));
                    return QuickReply(
                      id: 'n',
                      title: title,
                      message: message,
                      media: media,
                    );
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

    Finder titleField() => find.byType(TextFormField).first;
    Finder messageField() => find.byType(TextFormField).last;

    testWidgets('slides up with a shortcut and a message field', (tester) async {
      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('New quick reply'), findsOneWidget);
      expect(find.text('Shortcut'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Save quick reply'), findsOneWidget);
      // Without an uploader wired in there is nothing to attach.
      expect(find.text('Media (optional)'), findsNothing);
    });

    testWidgets('saves the shortcut without its typed slash', (tester) async {
      await open(tester);

      await tester.enterText(titleField(), '/welcome');
      await tester.enterText(messageField(), 'Hi there!');
      await tester.tap(find.text('Save quick reply'));
      await tester.pumpAndSettle();

      expect(saved.single.title, 'welcome');
      expect(saved.single.message, 'Hi there!');
      expect(saved.single.media, isEmpty);
      expect(find.text('New quick reply'), findsNothing);
    });

    testWidgets('a shortcut with spaces is refused', (tester) async {
      await open(tester);

      await tester.enterText(titleField(), 'hello there');
      await tester.enterText(messageField(), 'Hi');
      await tester.tap(find.text('Save quick reply'));
      await tester.pumpAndSettle();

      expect(find.text('Letters, numbers, _ and - only — no spaces'),
          findsOneWidget);
      expect(saved, isEmpty);
    });

    testWidgets('a failed save keeps the sheet open with the reason',
        (tester) async {
      await open(tester, fails: true);

      await tester.enterText(titleField(), 'welcome');
      await tester.enterText(messageField(), 'Hi');
      await tester.tap(find.text('Save quick reply'));
      await tester.pumpAndSettle();

      expect(find.textContaining('duplicate key'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('Create quick reply sheet with media', () {
    final saved = <({String title, String message, List<QuickReplyMedia> media})>[];

    setUp(saved.clear);

    Future<void> open(
      WidgetTester tester, {
      required Future<QuickReplyMedia?> Function(String kind) addMedia,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCreateQuickReplySheet(
                  context,
                  addMedia: addMedia,
                  save: (title, message, media) async {
                    saved.add((title: title, message: message, media: media));
                    return QuickReply(
                      id: 'n',
                      title: title,
                      message: message,
                      media: media,
                    );
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

    /// Scrolls the target into view before tapping it — the media form is
    /// taller than the test viewport, and a tap on an off-screen widget
    /// silently hits whatever is actually there.
    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<QuickReplyMedia?> picks(String kind) async => QuickReplyMedia(
          url: 'https://spx.aurotec.in/$kind.bin',
          type: kind,
          name: '$kind.bin',
        );

    testWidgets('shows the same three buttons and caps as the web form',
        (tester) async {
      await open(tester, addMedia: picks);

      expect(find.text('Media (optional)'), findsOneWidget);
      expect(find.text('Message (optional if media is set)'), findsOneWidget);
      expect(find.text('Add images'), findsOneWidget);
      expect(find.text('Add audio'), findsOneWidget);
      expect(find.text('Add video'), findsOneWidget);
      expect(
        find.text('Images \u2264 2MB · audio \u2264 1MB · video \u2264 5MB'),
        findsOneWidget,
      );
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('a media-only reply saves without any message',
        (tester) async {
      await open(tester, addMedia: picks);

      await tester.enterText(find.byType(TextFormField).first, 'vinay');
      await tap(tester, find.text('Add images'));

      expect(find.text('image.bin'), findsOneWidget);

      await tap(tester, find.text('Create'));

      expect(saved.single.message, isEmpty);
      expect(saved.single.media.single.type, 'image');
      expect(saved.single.media.single.url,
          'https://spx.aurotec.in/image.bin');
    });

    testWidgets('neither a message nor media is refused', (tester) async {
      await open(tester, addMedia: picks);

      await tester.enterText(find.byType(TextFormField).first, 'empty');
      await tap(tester, find.text('Create'));

      expect(find.text('Add a message and/or media.'), findsOneWidget);
      expect(saved, isEmpty);
    });

    testWidgets('an attached file can be taken back off', (tester) async {
      await open(tester, addMedia: picks);

      await tap(tester, find.text('Add audio'));
      expect(find.text('audio.bin'), findsOneWidget);

      await tap(tester, find.byTooltip('Remove audio.bin'));
      expect(find.text('audio.bin'), findsNothing);
    });

    testWidgets('a rejected file reports why and attaches nothing',
        (tester) async {
      await open(
        tester,
        addMedia: (kind) async => throw const AttachmentPickerException(
          '"clip.mp4" is too large — the limit for video is 5MB.',
        ),
      );

      await tap(tester, find.text('Add video'));

      expect(find.textContaining('too large'), findsOneWidget);
      expect(find.text('clip.mp4'), findsNothing);
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
              onSchedule: (_, _, _) async => true,
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

    /// + menu → Quick Replies, which opens the saved list.
    Future<void> openList(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quick Replies'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the saved replies with a + for a new one',
        (tester) async {
      await pump(tester, windowOpen: true, create: () async => null);
      await openList(tester);

      expect(find.text('Quick replies'), findsOneWidget);
      expect(find.text('/thanks'), findsOneWidget);
      expect(find.text('Thank you!'), findsOneWidget);
      expect(find.byTooltip('New quick reply'), findsOneWidget);
    });

    testWidgets('picking one puts it in the message box', (tester) async {
      await pump(tester, windowOpen: true, create: () async => null);
      await openList(tester);

      await tester.tap(find.text('/thanks'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Thank you!',
      );
    });

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

      await openList(tester);
      // Saving a reply sends nothing, so the closed window must not refuse it.
      await tester.tap(find.byTooltip('New quick reply'));
      await tester.pumpAndSettle();

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

      await openList(tester);
      await tester.tap(find.byTooltip('New quick reply'));
      await tester.pumpAndSettle();

      // Saving hands the new reply straight back, so it is already in the box.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'We open at 6.',
      );

      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();

      expect(find.byType(QuickRepliesPanel), findsOneWidget);
      expect(find.text('/hours'), findsOneWidget);
      expect(find.text('/thanks'), findsOneWidget);
    });
  });
}
