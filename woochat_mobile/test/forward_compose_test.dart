import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/forward_compose.dart';
import 'package:woochat_mobile/src/models/message.dart';

Message msg(String content) => Message(
      id: 'm1',
      chatId: 'c1',
      userId: 'u1',
      direction: 'outbound',
      content: content,
    );

void main() {
  final photo = msg(Message.attachmentMarker(
    type: 'image',
    name: 'chart.jpg',
    url: 'https://x.test/chart.jpg',
  ));
  final captioned = msg(Message.attachmentMarker(
    type: 'image',
    name: 'chart.jpg',
    url: 'https://x.test/chart.jpg',
    caption: 'hello',
  ));

  group('composeForward', () {
    test('a photo plus a note goes as one message with the note as caption',
        () {
      final out = composeForward(photo, note: ' test message ');

      expect(out.media?.caption, 'test message');
      expect(out.media?.url, 'https://x.test/chart.jpg');
      expect(out.media?.type, 'image');
      // The stored row carries the caption too, so the thread shows it.
      expect(Message.fromMap(<String, dynamic>{
        'id': 'x', 'chat_id': 'c', 'direction': 'outbound',
        'content': out.content,
      }).body, 'test message');
    });

    test('an existing caption is kept in front of the note', () {
      final out = composeForward(captioned, note: 'test message');
      expect(out.media?.caption, 'hello\ntest message');
    });

    test('no note leaves the media exactly as it was', () {
      final out = composeForward(captioned);
      expect(out.media?.caption, 'hello');
      expect(out.content, captioned.content);
    });

    test('a text message gets the note appended, not a second message', () {
      final out = composeForward(msg('Price is 499'), note: 'Offer today');
      expect(out.media, isNull);
      expect(out.content, 'Price is 499\n\nOffer today');
    });

    test('a text message with no note is unchanged', () {
      final out = composeForward(msg('Price is 499'));
      expect(out.content, 'Price is 499');
    });
  });
}
