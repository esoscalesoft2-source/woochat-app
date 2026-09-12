import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/models/message.dart';

Message withContent(String content) => Message(
      id: 'm1',
      chatId: 'c1',
      userId: 'u1',
      direction: 'inbound',
      content: content,
    );

void main() {
  group('attachment marker', () {
    test('parses type, name and url, decoding the percent-encoding', () {
      final message = withContent(
        '[attachment:image|50_day_camp_intro_en.jpg|'
        'https%3A%2F%2Fspx.aurotec.in%2Fstorage%2Fv1%2Fobject%2Fpublic%2F'
        'chat-attachments%2Fx.jpg]\nExclusive Update!',
      );

      final attachment = message.attachment!;
      expect(attachment.type, 'image');
      expect(attachment.name, '50_day_camp_intro_en.jpg');
      expect(
        attachment.url,
        'https://spx.aurotec.in/storage/v1/object/public/chat-attachments/x.jpg',
      );
      expect(attachment.isImage, isTrue);
      // The marker line is stripped from the visible body.
      expect(message.body, 'Exclusive Update!');
    });

    test('a plain message has no attachment and keeps its whole body', () {
      final message = withContent('Hello there');

      expect(message.attachment, isNull);
      expect(message.body, 'Hello there');
    });

    test('a malformed marker is treated as plain text', () {
      final message = withContent('[attachment:image|broken]');

      expect(message.attachment, isNull);
      expect(message.body, '[attachment:image|broken]');
    });

    test('an attachment with no caption has an empty body', () {
      final message = withContent('[attachment:document|invoice.pdf|https%3A%2F%2Fx/y.pdf]');

      expect(message.attachment!.type, 'document');
      expect(message.attachment!.isImage, isFalse);
      expect(message.body, isEmpty);
    });
  });
}
