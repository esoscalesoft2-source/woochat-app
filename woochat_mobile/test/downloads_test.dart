import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/data/downloads_repository.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_bubble.dart';
import 'package:woochat_mobile/src/models/message.dart';

void main() {
  const attachment = MessageAttachment(
    type: 'document',
    name: 'Price list.xlsx',
    url: 'https://x.test/storage/v1/object/public/b/o/price-list.xlsx',
  );

  group('DownloadsRepository', () {
    late Directory dir;
    late SharedPreferencesWithCache prefs;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      prefs = await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );
      dir = Directory.systemTemp.createTempSync('woochat-downloads');
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    DownloadsRepository repo({int status = 200}) => DownloadsRepository(
          client: MockClient((request) async {
            expect(request.url.toString(), attachment.url);
            return http.Response.bytes(<int>[1, 2, 3], status);
          }),
          prefs: () async => prefs,
          directory: () async => dir,
        );

    test('saves the bytes under their hash and remembers the URL', () async {
      final r = repo();
      expect(await r.localPathFor(attachment.url), isNull);

      final path = await r.download(attachment);

      // Named by what it is, with the extension the phone opens it by.
      expect(
        path,
        '${dir.path}/${DownloadsRepository.contentName(<int>[1, 2, 3], attachment)}',
      );
      expect(path, endsWith('.xlsx'));
      expect(File(path).readAsBytesSync(), <int>[1, 2, 3]);
      expect(await r.localPathFor(attachment.url), path);
      expect(await r.downloadedUrls(), <String>{attachment.url});
    });

    test('the same bytes under a second URL are saved once', () async {
      // Two messages, two storage objects, one poster.
      const twin = MessageAttachment(
        type: 'document',
        name: 'Price list (copy).xlsx',
        url: 'https://x.test/storage/v1/object/public/b/o/price-list-2.xlsx',
      );
      final r = DownloadsRepository(
        client: MockClient((_) async => http.Response.bytes(<int>[1, 2, 3], 200)),
        prefs: () async => prefs,
        directory: () async => dir,
      );

      final first = await r.download(attachment);
      final second = await r.download(twin);

      expect(second, first, reason: 'one file on disk');
      expect(dir.listSync().whereType<File>(), hasLength(1));
      // Both URLs know where their copy is.
      expect(await r.downloadedUrls(), <String>{attachment.url, twin.url});
      expect(await r.localPathFor(twin.url), first);
    });

    test('different bytes under the same name are two files', () async {
      var call = 0;
      final r = DownloadsRepository(
        client: MockClient((_) async =>
            http.Response.bytes(<int>[++call], 200)),
        prefs: () async => prefs,
        directory: () async => dir,
      );
      const other = MessageAttachment(
        type: 'document',
        name: 'Price list.xlsx',
        url: 'https://x.test/o/other.xlsx',
      );
      final a = await r.download(attachment);
      final b = await r.download(other);
      expect(a, isNot(b));
      expect(dir.listSync().whereType<File>(), hasLength(2));
    });

    test('a copy removed behind its back is forgotten, so ⬇ comes back',
        () async {
      final r = repo();
      final path = await r.download(attachment);
      File(path).deleteSync();

      expect(await r.localPathFor(attachment.url), isNull);
      expect(await r.downloadedUrls(), isEmpty);
    });

    test('auto-download saves the same way the ⬇ does on a phone', () async {
      final r = repo();
      final path = await r.prefetch(attachment);
      expect(File(path).existsSync(), isTrue);
      expect(await r.downloadedUrls(), <String>{attachment.url});
    });

    test('a refused fetch is an error, and nothing is remembered', () async {
      final r = repo(status: 403);

      await expectLater(
        r.download(attachment),
        throwsA(isA<DownloadException>()),
      );
      expect(await r.localPathFor(attachment.url), isNull);
    });
  });

  group('File row save states', () {
    Message doc() => Message(
          id: 'm1',
          chatId: 'c1',
          userId: 'u1',
          direction: MessageDirection.inbound,
          content: Message.attachmentMarker(
            type: 'document',
            name: attachment.name,
            url: attachment.url,
          ),
          status: MessageStatus.delivered,
          createdAt: DateTime(2026, 9, 17, 17, 40),
        );

    Future<void> pump(WidgetTester tester, AttachmentSaveState state) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: <Widget>[
                  MessageBubble(
                    message: doc(),
                    onDownloadAttachment: (_) {},
                    saveState: state,
                  ),
                ],
              ),
            ),
          ),
        );

    testWidgets('⬇ until saved, a spinner while saving, nothing after',
        (tester) async {
      final download = find.byKey(const ValueKey<String>('attachment-download'));
      final saving = find.byKey(const ValueKey<String>('attachment-saving'));

      await pump(tester, AttachmentSaveState.notSaved);
      expect(download, findsOneWidget);
      expect(saving, findsNothing);

      await pump(tester, AttachmentSaveState.saving);
      expect(download, findsNothing);
      expect(saving, findsOneWidget);

      await pump(tester, AttachmentSaveState.saved);
      expect(download, findsNothing);
      expect(saving, findsNothing);
      // The file itself is still there to tap.
      expect(find.text(attachment.name), findsOneWidget);
    });
  });
}
