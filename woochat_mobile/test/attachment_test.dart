import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/attachment_picker.dart';
import 'package:woochat_mobile/src/data/messages_repository.dart';
import 'package:woochat_mobile/src/features/chat/widgets/attachment_preview_sheet.dart';

void main() {
  PickedAttachment attachment({
    required String type,
    String name = 'file.bin',
    int sizeBytes = 1024,
    String mime = 'application/octet-stream',
  }) =>
      PickedAttachment(
        bytes: Uint8List(sizeBytes),
        fileName: name,
        mimeType: mime,
        type: type,
      );

  group('PickedAttachment limits', () {
    test('uses the caps the send function itself enforces', () {
      expect(attachment(type: 'image').limitBytes, 5 * 1024 * 1024);
      expect(attachment(type: 'video').limitBytes, 16 * 1024 * 1024);
      expect(attachment(type: 'audio').limitBytes, 16 * 1024 * 1024);
      expect(attachment(type: 'document').limitBytes, 100 * 1024 * 1024);
    });

    test('flags a file the send function would refuse', () {
      expect(
        attachment(type: 'image', sizeBytes: 6 * 1024 * 1024).isTooLarge,
        isTrue,
      );
      expect(
        attachment(type: 'document', sizeBytes: 6 * 1024 * 1024).isTooLarge,
        isFalse,
      );
    });
  });

  group('PickedAttachment formats', () {
    test('accepts only what the send function forwards', () {
      expect(
        attachment(type: 'image', mime: 'image/jpeg').isSupportedFormat,
        isTrue,
      );
      // A browser hands iPhone photos over as HEIC unconverted.
      expect(
        attachment(type: 'image', mime: 'image/heic').isSupportedFormat,
        isFalse,
      );
      expect(
        attachment(type: 'video', mime: 'video/quicktime').isSupportedFormat,
        isFalse,
      );
      expect(
        attachment(type: 'audio', mime: 'audio/mpeg').isSupportedFormat,
        isTrue,
      );
      // Documents may be anything.
      expect(
        attachment(type: 'document', mime: 'text/vcard').isSupportedFormat,
        isTrue,
      );
    });
  });

  group('OutboundMedia', () {
    test('sends the file name as the message field, not the caption', () {
      const media = OutboundMedia(
        url: 'https://example.test/x.pdf',
        type: 'document',
        mimeType: 'application/pdf',
        fileName: 'invoice.pdf',
        caption: 'Your invoice',
      );

      // The document branch refuses the call when `message` is empty, and
      // Meta shows it as the file name to the customer.
      expect(media.messageField, 'invoice.pdf');
      expect(media.payload['caption'], 'Your invoice');
      expect(media.payload['type'], 'document');
      expect(media.payload['mediaUrl'], 'https://example.test/x.pdf');
    });

    test('a bare file still names itself and sends no caption key', () {
      const media = OutboundMedia(
        url: 'https://example.test/a.jpg',
        type: 'image',
        mimeType: 'image/jpeg',
        fileName: 'a.jpg',
      );

      expect(media.messageField, 'a.jpg');
      expect(media.payload.containsKey('caption'), isFalse);
    });
  });

  group('PickedContact', () {
    test('reads as the name and numbers in the thread', () {
      const contact = PickedContact(
        displayName: 'Appu .M',
        phones: <String>['+91 95147 41502'],
        vCard: 'BEGIN:VCARD\nEND:VCARD',
      );
      expect(contact.preview, '👤 Appu .M\n+91 95147 41502');

      const noPhone = PickedContact(
        displayName: 'Appu .M',
        phones: <String>[],
        vCard: '',
      );
      expect(noPhone.preview, '👤 Appu .M');
    });
  });

  group('Attachment preview sheet', () {
    Future<Future<String?>> open(
      WidgetTester tester,
      PickedAttachment picked,
    ) async {
      Future<String?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showAttachmentPreviewSheet(
                    context,
                    attachment: picked,
                    chatName: 'Mahi',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result!;
    }

    testWidgets('sends the typed caption back', (tester) async {
      final result = await open(
        tester,
        attachment(type: 'document', name: 'invoice.pdf'),
      );

      expect(find.text('Send to Mahi'), findsOneWidget);
      expect(find.text('invoice.pdf'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('attachment-caption')),
        '  Your invoice  ',
      );
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(await result, 'Your invoice');
    });

    testWidgets('audio carries no caption field', (tester) async {
      await open(tester, attachment(type: 'audio', name: 'song.mp3'));

      expect(find.text('song.mp3'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('attachment-caption')),
        findsNothing,
      );
    });

    testWidgets('warns before sending something over the limit',
        (tester) async {
      await open(
        tester,
        attachment(
          type: 'image',
          name: 'big.jpg',
          sizeBytes: 6 * 1024 * 1024,
          mime: 'image/jpeg',
        ),
      );

      expect(find.textContaining('up to 5MB'), findsOneWidget);
    });

    testWidgets('warns about a format WhatsApp refuses', (tester) async {
      await open(
        tester,
        attachment(type: 'video', name: 'clip.mov', mime: 'video/quicktime'),
      );

      expect(find.textContaining('does not accept video/quicktime'),
          findsOneWidget);
    });

    testWidgets('backing out sends nothing', (tester) async {
      final result = await open(tester, attachment(type: 'document'));

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(await result, isNull);
    });
  });

  group('Attachment preview sheet with several files', () {
    List<PickedAttachment> three() => <PickedAttachment>[
          attachment(type: 'image', name: '1.jpg', mime: 'image/jpeg'),
          attachment(type: 'image', name: '2.jpg', mime: 'image/jpeg'),
          attachment(type: 'video', name: '3.mp4', mime: 'video/mp4'),
        ];

    Future<Future<AttachmentSendChoice?>> open(
      WidgetTester tester,
      List<PickedAttachment> files, {
      Future<List<PickedAttachment>> Function(int remaining)? onAddMore,
    }) async {
      Future<AttachmentSendChoice?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showAttachmentsPreviewSheet(
                    context,
                    attachments: files,
                    chatName: 'Mahi',
                    onAddMore: onAddMore,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result!;
    }

    testWidgets('counts the set in the title and the button', (tester) async {
      await open(tester, three());

      expect(find.text('Send 3 to Mahi'), findsOneWidget);
      expect(find.text('Send 3'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('attachment-strip')), findsOneWidget);
    });

    testWidgets('removing one shrinks the set; Send hands back the rest',
        (tester) async {
      final result = await open(tester, three());

      await tester.tap(find.byKey(const ValueKey<String>('attachment-remove-1')));
      await tester.pumpAndSettle();
      expect(find.text('Send 2'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('attachment-caption')),
        'New set',
      );
      await tester.tap(find.text('Send 2'));
      await tester.pumpAndSettle();

      final choice = await result;
      expect(choice?.attachments.map((a) => a.fileName), <String>['1.jpg', '3.mp4']);
      expect(choice?.caption, 'New set');
    });

    testWidgets('removing the last file closes the sheet with nothing',
        (tester) async {
      final result = await open(tester, three().take(1).toList());
      // A single file shows no strip — nothing to remove from — so the
      // sheet simply sends or is dismissed.
      expect(find.byKey(const ValueKey<String>('attachment-strip')), findsNothing);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });

  group('Attachment preview sheet: + adds more', () {
    testWidgets('no + without a picker to open', (tester) async {
      Future<AttachmentSendChoice?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showAttachmentsPreviewSheet(
                    context,
                    attachments: <PickedAttachment>[
                      attachment(type: 'document', name: 'a.pdf'),
                    ],
                    chatName: 'Mahi',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('attachment-add')), findsNothing);
      expect(result, isNotNull);
    });

    testWidgets('+ opens the picker again and the pick joins the set',
        (tester) async {
      var askedFor = -1;
      Future<AttachmentSendChoice?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showAttachmentsPreviewSheet(
                    context,
                    attachments: <PickedAttachment>[
                      attachment(type: 'document', name: 'a.pdf'),
                    ],
                    chatName: 'Mahi',
                    onAddMore: (remaining) async {
                      askedFor = remaining;
                      return <PickedAttachment>[
                        attachment(type: 'document', name: 'b.pdf'),
                        attachment(type: 'document', name: 'c.pdf'),
                      ];
                    },
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Send to Mahi'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('attachment-add')));
      await tester.pumpAndSettle();

      // 15 minus the one already there.
      expect(askedFor, 14);
      expect(find.text('Send 3 to Mahi'), findsOneWidget);
      // The first of what just came in is shown large.
      expect(find.text('b.pdf'), findsOneWidget);

      await tester.tap(find.text('Send 3'));
      await tester.pumpAndSettle();
      expect(
        (await result)?.attachments.map((a) => a.fileName),
        <String>['a.pdf', 'b.pdf', 'c.pdf'],
      );
    });

    testWidgets('the cap is fifteen in total', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAttachmentsPreviewSheet(
                  context,
                  attachments: <PickedAttachment>[
                    for (var i = 0; i < 15; i++)
                      attachment(type: 'document', name: '$i.pdf'),
                  ],
                  chatName: 'Mahi',
                  onAddMore: (_) async => <PickedAttachment>[
                    attachment(type: 'document', name: 'extra.pdf'),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('attachment-add')));
      await tester.pumpAndSettle();

      expect(find.textContaining('up to 15'), findsOneWidget);
      expect(find.text('Send 15 to Mahi'), findsOneWidget);
    });
  });
}
