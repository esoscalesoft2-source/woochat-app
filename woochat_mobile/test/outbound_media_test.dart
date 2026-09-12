import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/messages_repository.dart';
import 'package:woochat_mobile/src/models/message.dart';

void main() {
  group('OutboundMedia', () {
    const media = OutboundMedia(
      url: 'https://spx.aurotec.in/storage/v1/object/public/'
          'chat-attachments/u/c/voice-1.m4a',
      type: 'audio',
      mimeType: 'audio/mp4',
      fileName: 'voice-1.m4a',
    );

    test('names the message kind, or the function assumes text', () {
      // `Missing 'message' for text` came back when this was absent: the
      // function defaults the kind to text and then demands message text.
      expect(media.payload['type'], 'audio');
      expect(media.payload['mediaType'], 'audio');
    });

    test('carries the URL and the file details', () {
      expect(media.payload['mediaUrl'], contains('voice-1.m4a'));
      expect(media.payload['mimeType'], 'audio/mp4');
      expect(media.payload['fileName'], 'voice-1.m4a');
    });

    test('a bare voice note sends no caption key at all', () {
      expect(media.payload.containsKey('caption'), isFalse);
    });

    test('a caption is passed through when there is one', () {
      const captioned = OutboundMedia(
        url: 'https://x.test/a.jpg',
        type: 'image',
        mimeType: 'image/jpeg',
        fileName: 'a.jpg',
        caption: 'Size chart',
      );

      expect(captioned.payload['caption'], 'Size chart');
    });

    test('the stored marker is separate from what is sent', () {
      // The row keeps the marker so the thread can draw a player; the marker
      // must never be the message text, which is what reached the customer
      // as raw `[attachment:audio|…]`.
      final marker = Message.attachmentMarker(
        type: 'audio',
        name: media.fileName,
        url: media.url,
      );

      expect(marker, startsWith('[attachment:audio|'));
      expect(media.payload.values.join(' '), isNot(contains('[attachment:')));
    });
  });
}
