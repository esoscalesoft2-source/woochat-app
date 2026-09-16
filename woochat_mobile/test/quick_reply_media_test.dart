import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/shortcuts_repository.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_composer.dart';
import 'package:woochat_mobile/src/features/chat/widgets/shortcut_media_tray.dart';

void main() {
  const withMedia = QuickReply(
    id: 's1',
    title: 'acidwash_set1',
    message: '',
    media: <QuickReplyMedia>[
      QuickReplyMedia(url: 'https://x.test/1.jpg', type: 'image', name: '1.jpg'),
      QuickReplyMedia(url: 'https://x.test/2.jpg', type: 'image', name: '2.jpg'),
    ],
  );
  const textOnly = QuickReply(
    id: 's2',
    title: 'address',
    message: 'Acn office, west street',
  );

  group('QuickReply media', () {
    test('reads media_urls, newest shape first', () {
      final reply = QuickReply.fromMap(<String, dynamic>{
        'id': 1,
        'title': '/set1',
        'message': null,
        'media_urls': <Map<String, dynamic>>[
          <String, dynamic>{
            'url': 'https://x.test/a.jpg',
            'type': 'image',
            'name': 'a.jpg',
          },
          // Neither a bad type nor a missing url is a file.
          <String, dynamic>{'url': 'https://x.test/b', 'type': 'nonsense'},
          <String, dynamic>{'type': 'image'},
        ],
      });

      expect(reply.title, 'set1');
      expect(reply.message, isEmpty);
      expect(reply.media.single.url, 'https://x.test/a.jpg');
    });

    test('falls back to the legacy single-media columns', () {
      final reply = QuickReply.fromMap(<String, dynamic>{
        'id': 2,
        'title': 'old',
        'message': 'hi',
        'media_urls': <dynamic>[],
        'media_url': 'https://x.test/old%20clip.mp4',
        'media_type': 'video',
      });

      expect(reply.media.single.type, 'video');
      // The name is read back out of the URL, unescaped.
      expect(reply.media.single.name, 'old clip.mp4');
    });

    test('labels a media-only reply the way the web list does', () {
      expect(withMedia.preview, '📎 2 media (media only)');
      expect(withMedia.mediaLabel, '📎 2 media');
      expect(textOnly.preview, 'Acn office, west street');
      expect(textOnly.hasMedia, isFalse);
    });
  });

  group('Shortcut media tray', () {
    Future<void> pump(
      WidgetTester tester, {
      required List<QuickReplyMedia> media,
      bool hasCaption = false,
      VoidCallback? onClear,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ShortcutMediaTray(
                media: media,
                hasCaption: hasCaption,
                onClear: onClear ?? () {},
              ),
            ),
          ),
        );

    testWidgets('shows nothing at all when empty', (tester) async {
      await pump(tester, media: const <QuickReplyMedia>[]);
      expect(find.text('Shortcut media'), findsNothing);
    });

    testWidgets('names every staged file and counts them', (tester) async {
      await pump(tester, media: withMedia.media);

      expect(find.text('Shortcut media (2)'), findsOneWidget);
      expect(find.text('1.jpg'), findsOneWidget);
      expect(find.text('2.jpg'), findsOneWidget);
    });

    testWidgets('says the typed message follows the files', (tester) async {
      await pump(tester, media: withMedia.media, hasCaption: true);
      expect(
        find.text('Shortcut media (2) · message sent after'),
        findsOneWidget,
      );
    });

    testWidgets('the ✕ clears the staging', (tester) async {
      var cleared = 0;
      await pump(
        tester,
        media: withMedia.media,
        onClear: () => cleared++,
      );

      await tester.tap(find.byTooltip('Remove shortcut media'));
      expect(cleared, 1);
    });
  });

  group('composer staging', () {
    late List<(List<QuickReplyMedia>, String)> bundles;
    late List<String> texts;

    Future<void> pump(WidgetTester tester, {bool wireMedia = true}) async {
      bundles = <(List<QuickReplyMedia>, String)>[];
      texts = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              onSend: (text) async {
                texts.add(text);
                return true;
              },
              onSendShortcutMedia: wireMedia
                  ? (media, caption) async {
                      bundles.add((media, caption));
                      return true;
                    }
                  : null,
              windowOpen: true,
              onTemplates: () {},
              onAttach: (_) {},
              onSchedule: (_, _, _) async => true,
              onBlocked: () {},
              onVoiceNote: (_) async => true,
              onRecorderProblem: (_) {},
              loadQuickReplies: () async => <QuickReply>[withMedia, textOnly],
            ),
          ),
        ),
      );
    }

    Future<void> pick(WidgetTester tester, String title) async {
      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      await tester.tap(find.text('/$title'));
      await tester.pumpAndSettle();
    }

    testWidgets('picking a media reply stages it instead of sending',
        (tester) async {
      await pump(tester);
      await pick(tester, 'acidwash_set1');

      expect(find.text('Shortcut media (2)'), findsOneWidget);
      expect(bundles, isEmpty);
      // Nothing typed, but there is something to send, so the mic gives way.
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('Send sends the files with whatever text is in the box',
        (tester) async {
      await pump(tester);
      await pick(tester, 'acidwash_set1');

      await tester.enterText(find.byType(TextField), 'Sizes available');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(bundles.single.$1.length, 2);
      expect(bundles.single.$2, 'Sizes available');
      // The bundle carries the text; it is not sent twice.
      expect(texts, isEmpty);
      expect(find.text('Shortcut media (2)'), findsNothing);
    });

    testWidgets('an erased message sends the files alone', (tester) async {
      await pump(tester);
      await pick(tester, 'acidwash_set1');

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(bundles.single.$2, isEmpty);
    });

    testWidgets('a text-only reply still goes through the plain send',
        (tester) async {
      await pump(tester);
      await pick(tester, 'address');

      expect(find.text('Shortcut media'), findsNothing);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(texts, <String>['Acn office, west street']);
      expect(bundles, isEmpty);
    });

    testWidgets('without a media sender nothing is staged', (tester) async {
      await pump(tester, wireMedia: false);
      await pick(tester, 'acidwash_set1');

      expect(find.text('Shortcut media (2)'), findsNothing);
    });
  });
}
