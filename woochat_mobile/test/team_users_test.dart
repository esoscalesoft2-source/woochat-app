import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chats/chat_filter_state.dart';
import 'package:woochat_mobile/src/features/chats/widgets/chat_owners.dart';
import 'package:woochat_mobile/src/models/chat.dart';
import 'package:woochat_mobile/src/models/chat_filters.dart';

Chat owned(String id, String userId) =>
    Chat(id: id, userId: userId, contactName: id);

void main() {
  final chats = <Chat>[
    owned('a', 'me'),
    owned('b', 'me'),
    owned('c', 'mate'),
  ];

  group('ownersOf', () {
    test('groups by chats.user_id and counts, busiest first', () {
      final owners = ownersOf(
        chats,
        signedInUserId: 'me',
        signedInLabel: 'admin@example.com',
      );

      expect(owners.map((o) => o.userId), <String>['me', 'mate']);
      expect(owners.first.count, 2);
      expect(owners.first.label, 'admin@example.com');
    });

    test('falls back to a short id for other team members', () {
      final owners = ownersOf(
        chats,
        signedInUserId: 'me',
        signedInLabel: null,
      );

      expect(owners.first.label, 'You');
      expect(owners.last.label, startsWith('User '));
    });

    test('an empty list has no owners', () {
      expect(
        ownersOf(const <Chat>[], signedInUserId: 'me', signedInLabel: null),
        isEmpty,
      );
    });
  });

  group('owner filter', () {
    test('narrows to one team member', () {
      final result = ChatFilterEngine.apply(
        chats: chats,
        data: ChatFilterData.empty,
        state: ChatFilterState.initial.selectOwner('mate'),
      );

      expect(result.map((c) => c.id), <String>['c']);
    });

    test('is an independent axis that clears nothing', () {
      final state = ChatFilterState.initial
          .selectLabel('l1')
          .selectCategory('c1')
          .selectOwner('mate');

      expect(state.ownerId, 'mate');
      expect(state.labelId, 'l1');
      expect(state.categoryId, 'c1');
      expect(state.isNarrowed, isTrue);
    });

    test('Clear all drops it', () {
      final state = ChatFilterState.initial.selectOwner('mate').clearAll();
      expect(state.ownerId, isNull);
    });
  });
}
