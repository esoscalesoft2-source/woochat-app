import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/features/chat/widgets/document_viewer.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_bubble.dart';
import 'package:woochat_mobile/src/models/message.dart';

void main() {
  group('MessageAttachment kinds', () {
    MessageAttachment att(String type, String name, [String? url]) =>
        MessageAttachment(
          type: type,
          name: name,
          url: url ?? 'https://x.test/chat-attachments/a/inbound/$name',
        );

    test('a photo sent as a document is still a picture', () {
      expect(att('document', '28160971500238066.jpg').looksLikeImage, isTrue);
      expect(att('document', 'scan.PNG').looksLikeImage, isTrue);
      expect(att('image', 'anything').looksLikeImage, isTrue);
      expect(att('document', 'invoice.pdf').looksLikeImage, isFalse);
    });

    test('a PDF is known by its extension, from the name or the URL', () {
      expect(att('document', 'invoice.pdf').isPdf, isTrue);
      expect(att('document', 'Invoice.PDF').isPdf, isTrue);
      expect(
        att('document', '', 'https://x.test/o/inbound/9.pdf').isPdf,
        isTrue,
      );
      expect(att('document', 'sheet.xlsx').isPdf, isFalse);
    });

    test('the download link asks storage for an attachment under its name', () {
      final uri = att('document', 'Price list.xlsx',
              'https://x.test/storage/v1/object/public/b/o/a.xlsx?token=1')
          .downloadUri!;
      expect(uri.queryParameters['download'], 'Price list.xlsx');
      expect(uri.queryParameters['token'], '1', reason: 'keeps what was there');
      expect(uri.path, '/storage/v1/object/public/b/o/a.xlsx');
    });

    test('a name with no extension is not mistaken for one', () {
      expect(att('document', 'README').extension, '');
      expect(att('document', 'v1.2 release notes', 'https://x.test/o/notes')
          .extension, '');
    });
  });

  group('File row', () {
    Message doc(String name) => Message(
          id: 'm1',
          chatId: 'c1',
          userId: 'u1',
          direction: MessageDirection.inbound,
          content: Message.attachmentMarker(
            type: 'document',
            name: name,
            url: 'https://x.test/o/inbound/$name',
          ),
          status: MessageStatus.delivered,
          createdAt: DateTime(2026, 9, 17, 17, 40),
        );

    testWidgets('tapping the name opens; only ⬇ downloads', (tester) async {
      final opened = <String>[];
      final downloaded = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                MessageBubble(
                  message: doc('brochure.docx'),
                  onOpenAttachment: (a) => opened.add(a.name),
                  onDownloadAttachment: (a) => downloaded.add(a.name),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('brochure.docx'));
      await tester.pump();
      expect(opened, <String>['brochure.docx']);
      expect(downloaded, isEmpty, reason: 'a look is not a download');

      await tester.tap(find.byKey(const ValueKey<String>('attachment-download')));
      await tester.pump();
      expect(downloaded, <String>['brochure.docx']);
      expect(opened, hasLength(1), reason: '⬇ must not also open it');
    });

    testWidgets('no ⬇ when nothing is wired to download', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[MessageBubble(message: doc('a.pdf'))],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('attachment-download')),
          findsNothing);
    });
  });

  group('Document viewer', () {
    testWidgets('opens as a page in the app with the file name and a way out',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDocumentViewer(
                  context,
                  attachment: const MessageAttachment(
                    type: 'document',
                    name: 'invoice.pdf',
                    url: 'https://x.test/o/inbound/invoice.pdf',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.byTooltip('Open in another app'), findsOneWidget);
      // Nothing was launched externally to get here.
      expect(find.byType(Dialog), findsNothing);
      // Whatever the renderer did without a network, it did not crash the page.
      tester.takeException();
    });
  });
}
