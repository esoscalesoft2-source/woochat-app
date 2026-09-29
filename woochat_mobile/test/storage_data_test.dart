import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/data/attachment_picker.dart';
import 'package:woochat_mobile/src/data/downloads_repository.dart';
import 'package:woochat_mobile/src/data/media_policy.dart';
import 'package:woochat_mobile/src/data/photo_compressor.dart';
import 'package:woochat_mobile/src/data/storage_settings.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_bubble.dart';
import 'package:woochat_mobile/src/features/shell/storage_data_screen.dart';
import 'package:woochat_mobile/src/models/message.dart';

void main() {
  late SharedPreferencesWithCache prefs;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
  });

  StorageSettings settings() => StorageSettings(prefs: () async => prefs);

  group('StorageSettings', () {
    test('starts with WhatsApp\'s defaults', () async {
      final s = settings();
      await s.load();
      expect(s.uploadQuality, UploadQuality.standard);
      expect(s.onMobileData.kinds, <MediaKind>{MediaKind.photos});
      expect(s.onWifi.kinds, MediaKind.values.toSet());
    });

    test('a change is kept for the next session', () async {
      final s = settings();
      await s.setUploadQuality(UploadQuality.hd);
      await s.setOnMobileData(
        const AutoDownload(<MediaKind>{MediaKind.audio, MediaKind.documents}),
      );

      final next = settings();
      await next.load();
      expect(next.uploadQuality, UploadQuality.hd);
      expect(next.onMobileData.kinds, <MediaKind>{MediaKind.audio, MediaKind.documents});
      expect(next.onMobileData.label, 'Audio, Documents');
      expect(next.onWifi.label, 'All media');
    });

    test('the rules mean what they say', () {
      expect(AutoDownload.none.allows('image'), isFalse);
      expect(AutoDownload.none.label, 'No media');
      expect(AutoDownload.photosOnly.allows('image'), isTrue);
      expect(AutoDownload.photosOnly.allows('sticker'), isTrue);
      expect(AutoDownload.photosOnly.allows('video'), isFalse);
      expect(AutoDownload.photosOnly.allows('document'), isFalse);
      expect(AutoDownload.all.allows('video'), isTrue);
      expect(AutoDownload.all.allows('document'), isTrue);
      // Voice notes always, whatever is ticked.
      expect(AutoDownload.none.allows('voice'), isTrue);
      // Toggling is a copy, not a mutation.
      final one = AutoDownload.photosOnly.toggled(MediaKind.videos);
      expect(one.label, 'Photos, Videos');
      expect(AutoDownload.photosOnly.label, 'Photos');
    });
  });

  group('MediaPolicy', () {
    test('picks the mobile rule on mobile data and the Wi-Fi rule otherwise',
        () async {
      final s = settings();
      await s.setOnMobileData(AutoDownload.none);
      await s.setOnWifi(AutoDownload.all);
      final connection = StreamController<List<ConnectivityResult>>();
      final policy = MediaPolicy(settings: s, connectivity: connection.stream);
      addTearDown(policy.dispose);
      addTearDown(connection.close);

      // Starts assuming Wi-Fi.
      expect(policy.autoLoads('image'), isTrue);

      var notified = 0;
      policy.addListener(() => notified++);
      connection.add(<ConnectivityResult>[ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      expect(policy.onMobileData, isTrue);
      expect(policy.autoLoads('image'), isFalse);
      // At least the connection change; the settings' own load may add one.
      expect(notified, greaterThanOrEqualTo(1));

      // Wi-Fi alongside mobile is Wi-Fi.
      connection.add(<ConnectivityResult>[
        ConnectivityResult.mobile,
        ConnectivityResult.wifi,
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(policy.autoLoads('image'), isTrue);

      // A settings change redraws too.
      await s.setOnWifi(AutoDownload.none);
      expect(policy.autoLoads('image'), isFalse);
    });
  });

  group('PhotoCompressor', () {
    PickedAttachment photo(int w, int h, {String mime = 'image/png'}) {
      final image = img.Image(width: w, height: h);
      // Random noise: like a photo, it is something PNG cannot squeeze and
      // JPEG can — a regular pattern would go the other way and the
      // compressor would rightly keep the PNG.
      final random = Random(1);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          image.setPixelRgb(
            x,
            y,
            random.nextInt(256),
            random.nextInt(256),
            random.nextInt(256),
          );
        }
      }
      return PickedAttachment(
        bytes: Uint8List.fromList(img.encodePng(image)),
        fileName: 'shot.png',
        mimeType: mime,
        type: 'image',
      );
    }

    test('a big photo comes out at 1600 on its long side, as a JPEG',
        () async {
      final out = await PhotoCompressor.standardQuality(photo(1800, 900));
      final decoded = img.decodeImage(out.bytes)!;
      expect(decoded.width, 1600);
      expect(decoded.height, 800);
      expect(out.mimeType, 'image/jpeg');
      expect(out.fileName, 'shot.jpg');
    });

    test('a photo already small is not upscaled', () async {
      final out = await PhotoCompressor.standardQuality(photo(400, 300));
      final decoded = img.decodeImage(out.bytes)!;
      expect(decoded.width, 400);
    });

    test('a GIF, a video, a document all go up untouched', () async {
      final gif = PickedAttachment(
        bytes: Uint8List(10),
        fileName: 'a.gif',
        mimeType: 'image/gif',
        type: 'image',
      );
      expect(identical(await PhotoCompressor.standardQuality(gif), gif), isTrue);
      final doc = PickedAttachment(
        bytes: Uint8List(10),
        fileName: 'a.pdf',
        mimeType: 'application/pdf',
        type: 'document',
      );
      expect(identical(await PhotoCompressor.standardQuality(doc), doc), isTrue);
    });
  });

  group('Tap to load', () {
    Message picture() => Message(
          id: 'm1',
          chatId: 'c1',
          userId: 'u1',
          direction: MessageDirection.inbound,
          content: Message.attachmentMarker(
            type: 'image',
            name: 'a.jpg',
            url: 'https://x.test/o/a.jpg',
          ),
          status: MessageStatus.delivered,
          createdAt: DateTime(2026, 9, 19, 10),
        );

    testWidgets('a picture waits under a no-media rule until tapped',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                MessageBubble(message: picture(), autoLoadMedia: false),
              ],
            ),
          ),
        ),
      );
      final tile = find.byKey(const ValueKey<String>('media-tap-to-load'));
      expect(tile, findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await tester.tap(tile);
      await tester.pump();
      expect(tile, findsNothing);
      expect(find.byType(Image), findsOneWidget);
      // The image request fails in a test; that is not the point here.
      tester.takeException();
    });
  });

  group('Storage and data page', () {
    late Directory dir;
    late DownloadsRepository downloads;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('woochat-storage');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      downloads = DownloadsRepository(
        client: MockClient((_) async => http.Response.bytes(List<int>.filled(2048, 1), 200)),
        prefs: () async => prefs,
        directory: () async => dir,
      );
    });

    /// Lets real IO finish, then draws what it produced.
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StorageAndDataScreen(
            settings: settings(),
            downloads: downloads,
            onReloadTemplates: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the three things WhatsApp shows, with current values',
        (tester) async {
      await open(tester);
      expect(find.text('Manage storage'), findsOneWidget);
      expect(find.text('Media upload quality'), findsOneWidget);
      expect(find.text('Standard quality'), findsOneWidget);
      expect(find.text('When using mobile data'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('When connected on Wi-Fi'), findsOneWidget);
      expect(find.text('All media'), findsOneWidget);
    });

    testWidgets('picking HD changes the row and is saved', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storage-upload-quality')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('choice-HD quality')));
      await tester.pumpAndSettle();

      expect(find.text('HD quality'), findsOneWidget);
      final saved = settings();
      await saved.load();
      expect(saved.uploadQuality, UploadQuality.hd);
    });

    testWidgets('mobile data offers a tick per kind, saved on OK',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storage-auto-mobile')));
      await tester.pumpAndSettle();

      // Photos is already ticked; the other three are not.
      for (final kind in MediaKind.values) {
        expect(find.byKey(ValueKey<String>('kind-${kind.name}')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey<String>('kind-documents')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('kind-audio')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('kinds-ok')));
      await tester.pumpAndSettle();

      expect(find.text('Photos, Audio, Documents'), findsOneWidget);
      final saved = settings();
      await saved.load();
      expect(saved.onMobileData.kinds,
          <MediaKind>{MediaKind.photos, MediaKind.audio, MediaKind.documents});
    });

    testWidgets('Cancel keeps the ticks as they were', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey<String>('storage-auto-wifi')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('kind-videos')));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('All media'), findsOneWidget);
    });

    testWidgets('Manage storage counts the saved files and can clear them',
        (tester) async {
      // Real file IO does not complete under the test's fake clock, so the
      // steps that touch the disk run under runAsync.
      await tester.runAsync(() => downloads.download(const MessageAttachment(
            type: 'document',
            name: 'a.pdf',
            url: 'https://x.test/o/a.pdf',
          )));
      await tester.runAsync(() => open(tester));
      await settle(tester);
      expect(find.text('2 KB'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('storage-manage')));
      await settle(tester);
      expect(find.textContaining('2 KB · tap to clear'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('storage-clear-downloads')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await settle(tester);

      expect(find.text('Nothing saved from chats yet'), findsOneWidget);
      expect(await downloads.downloadedUrls(), isEmpty);
    });
  });

  test('formatBytes reads like WhatsApp', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2 KB');
    expect(formatBytes(1024 * 1024 * 12 + 400000), '12.4 MB');
    expect(formatBytes(1024 * 1024 * 1024 * 1.6 ~/ 1), '1.6 GB');
  });
}
