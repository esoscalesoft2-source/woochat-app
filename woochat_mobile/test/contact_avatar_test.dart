import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chats/widgets/contact_avatar.dart';
import 'package:woochat_mobile/src/models/chat.dart';

Chat chat({String? phone, String? name, String? photo}) => Chat(
      id: 'c1',
      userId: 'u1',
      contactName: name,
      contactPhone: phone,
      profilePhotoUrl: photo,
    );

void main() {
  group('avatar colour', () {
    test('is stable for the same phone number', () {
      final a = ContactAvatar.colorFor(phone: '919876543210', name: 'Asha');
      final b = ContactAvatar.colorFor(phone: '919876543210', name: 'Renamed');

      // Keyed on the phone, so renaming the contact must not recolour them.
      expect(a, b);
      expect(ContactAvatar.palette, contains(a));
    });

    test('different contacts generally get different colours', () {
      final colours = <Color>{
        for (final phone in <String>[
          '919000000001',
          '919000000002',
          '919000000003',
          '919000000004',
        ])
          ContactAvatar.colorFor(phone: phone, name: null),
      };

      expect(colours.length, greaterThan(1));
    });

    test('falls back to the name, then to a constant', () {
      final byName = ContactAvatar.colorFor(phone: null, name: 'Asha');
      final byNameAgain = ContactAvatar.colorFor(phone: '', name: 'Asha');
      expect(byName, byNameAgain);

      expect(ContactAvatar.palette, contains(ContactAvatar.colorFor()));
    });
  });

  group('avatar widget', () {
    testWidgets('shows a person icon rather than initials', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactAvatar(chat: chat(phone: '919876543210', name: 'Asha')),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.person), findsOneWidget);
      // Initials must not appear anywhere.
      expect(find.text('A'), findsNothing);

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(
        avatar.backgroundColor,
        ContactAvatar.colorFor(phone: '919876543210', name: 'Asha'),
      );
      expect(avatar.foregroundImage, isNull);
    });

    testWidgets('uses the real profile photo when there is one',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactAvatar(
              chat: chat(phone: '91987', photo: 'https://example.com/a.jpg'),
            ),
          ),
        ),
      );
      await tester.pump();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.foregroundImage, isA<NetworkImage>());
      // The person icon stays underneath as the loading/error fallback.
      expect(find.byIcon(Icons.person), findsOneWidget);

      // The test harness cannot fetch images, so the load failure it reports
      // is expected here and must be consumed.
      expect(tester.takeException(), isA<NetworkImageLoadException>());
    });
  });
}
