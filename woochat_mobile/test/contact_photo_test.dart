import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chats/widgets/contact_avatar.dart';
import 'package:woochat_mobile/src/models/chat.dart';
import 'package:woochat_mobile/src/models/chat_filters.dart';

const contactPhoto = 'https://spx.aurotec.in/storage/contact.jpg';
const chatPhoto = 'https://spx.aurotec.in/storage/chat.jpg';

Chat chat({String? phone, String? photo}) => Chat(
      id: 'c1',
      userId: 'u1',
      contactName: 'Asha',
      contactPhone: phone,
      profilePhotoUrl: photo,
    );

void main() {
  group('photo resolution', () {
    const data = ChatFilterData(
      contactPhotoByPhone: <String, String>{'919876543210': contactPhoto},
    );

    test('a photo on the contact record wins over the chat column', () {
      expect(data.photoFor('919876543210', chatPhoto), contactPhoto);
    });

    test('falls back to the chat column when the contact has none', () {
      expect(data.photoFor('910000000000', chatPhoto), chatPhoto);
    });

    test('null when neither source has one, so the placeholder shows', () {
      expect(data.photoFor('910000000000', null), isNull);
      expect(data.photoFor('910000000000', '   '), isNull);
    });

    test('blank contact photos do not mask a real chat photo', () {
      const blank = ChatFilterData(
        contactPhotoByPhone: <String, String>{'919876543210': '  '},
      );
      expect(blank.photoFor('919876543210', chatPhoto), chatPhoto);
    });
  });

  group('withFunnel', () {
    test('keeps the contact photos when the date range changes', () {
      const before = ChatFilterData(
        contactPhotoByPhone: <String, String>{'919876543210': contactPhoto},
        noteTags: <String>['billing'],
      );

      final after = before.withFunnel(
        failed: <String>{'a'},
        replied: <String>{'b'},
      );

      // Refreshing the funnel sets must not drop anything else.
      expect(after.contactPhotoByPhone, before.contactPhotoByPhone);
      expect(after.noteTags, before.noteTags);
      expect(after.funnelFailed, <String>{'a'});
      expect(after.funnelReplied, <String>{'b'});
    });
  });

  group('ContactAvatar override', () {
    testWidgets('uses the directory photo when one is passed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactAvatar(
              chat: chat(phone: '919876543210', photo: chatPhoto),
              photoUrl: contactPhoto,
            ),
          ),
        ),
      );
      await tester.pump();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect((avatar.foregroundImage! as NetworkImage).url, contactPhoto);
      expect(tester.takeException(), isA<NetworkImageLoadException>());
    });

    testWidgets('falls back to the chat photo when no override is given',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactAvatar(chat: chat(phone: '91987', photo: chatPhoto)),
          ),
        ),
      );
      await tester.pump();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect((avatar.foregroundImage! as NetworkImage).url, chatPhoto);
      expect(tester.takeException(), isA<NetworkImageLoadException>());
    });
  });
}
