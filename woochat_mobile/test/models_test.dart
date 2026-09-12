import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/models/chat.dart';
import 'package:woochat_mobile/src/models/message.dart';

void main() {
  group('Chat', () {
    test('falls back to the phone number when there is no contact name', () {
      final chat = Chat.fromMap(<String, dynamic>{
        'id': 'c1',
        'user_id': 'u1',
        'contact_name': '   ',
        'contact_phone': '+919812345678',
      });

      expect(chat.displayName, '+919812345678');
      expect(chat.unreadCount, 0);
      expect(chat.isArchived, isFalse);
    });

    test('builds initials from the first two name parts', () {
      final chat = Chat.fromMap(<String, dynamic>{
        'id': 'c1',
        'user_id': 'u1',
        'contact_name': 'Asha Rani Patel',
      });

      expect(chat.initials, 'AR');
    });
  });

  group('Message', () {
    test('parses direction and timestamps', () {
      final message = Message.fromMap(<String, dynamic>{
        'id': 'm1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'direction': 'outbound',
        'content': 'Hello',
        'status': 'sent',
        'created_at': '2026-09-07T10:30:00Z',
      });

      expect(message.isOutbound, isTrue);
      expect(message.hasFailed, isFalse);
      expect(message.createdAt?.isUtc, isFalse); // converted to local time
    });
  });

  group('AppRole', () {
    test('maps app_role enum values and ranks them', () {
      expect(AppRole.fromWire('super_admin'), AppRole.superAdmin);
      expect(AppRole.fromWire('moderator'), AppRole.moderator);
      expect(AppRole.fromWire(null), AppRole.user);
      expect(AppRole.superAdmin.rank, greaterThan(AppRole.admin.rank));
    });
  });
}
