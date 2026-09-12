import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/features/chat/thread_items.dart';
import 'package:woochat_mobile/src/models/message.dart';

Message at(String id, DateTime? createdAt) => Message(
      id: id,
      chatId: 'c1',
      userId: 'u1',
      direction: 'inbound',
      content: id,
      createdAt: createdAt,
    );

final sept7 = DateTime(2026, 9, 7, 10, 0);
final sept8Morning = DateTime(2026, 9, 8, 9, 58);
final sept8Later = DateTime(2026, 9, 8, 10, 24);
final sept9 = DateTime(2026, 9, 9, 12, 29);

List<String> shape(List<Object> items) => items
    .map((item) => item is Message ? item.id : 'DAY ${(item as DateTime).day}')
    .toList();

void main() {
  group('buildThreadItems', () {
    test('orders oldest first so the newest message is last', () {
      final items = buildThreadItems(<Message>[
        at('sept7', sept7),
        at('sept8a', sept8Morning),
        at('sept9', sept9),
      ]);

      expect(shape(items), <String>[
        'DAY 7', 'sept7',
        'DAY 8', 'sept8a',
        'DAY 9', 'sept9',
      ]);
    });

    test('re-sorts a newest-first list rather than trusting the query', () {
      // What a missing `ascending:` on the Supabase order returns.
      final items = buildThreadItems(<Message>[
        at('sept9', sept9),
        at('sept8a', sept8Morning),
        at('sept7', sept7),
      ]);

      expect(shape(items).last, 'sept9');
      expect(shape(items).first, 'DAY 7');
    });

    test('one divider per day, not per message', () {
      final items = buildThreadItems(<Message>[
        at('a', sept8Morning),
        at('b', sept8Later),
      ]);

      expect(shape(items), <String>['DAY 8', 'a', 'b']);
    });

    test('messages with no timestamp sink to the top', () {
      final items = buildThreadItems(<Message>[
        at('dated', sept9),
        at('undated', null),
      ]);

      expect(shape(items), <String>['undated', 'DAY 9', 'dated']);
    });

    test('an empty thread produces nothing', () {
      expect(buildThreadItems(const <Message>[]), isEmpty);
    });
  });

  group('startsRun', () {
    Message msg(String id, {required bool outbound}) => Message(
          id: id,
          chatId: 'c1',
          userId: 'u1',
          direction:
              outbound ? MessageDirection.outbound : MessageDirection.inbound,
          content: id,
          createdAt: DateTime(2026, 9, 9, 10),
        );

    test('the first message always opens a run', () {
      final items = <Object>[msg('a', outbound: true)];
      expect(startsRun(items, 0), isTrue);
    });

    test('a message from the same side is tucked under the one before it', () {
      final items = <Object>[
        msg('a', outbound: true),
        msg('b', outbound: true),
      ];
      expect(startsRun(items, 1), isFalse);
    });

    test('a reply from the other side opens a new run', () {
      final items = <Object>[
        msg('a', outbound: true),
        msg('b', outbound: false),
      ];
      expect(startsRun(items, 1), isTrue);
    });

    test('a day divider breaks the run', () {
      final items = <Object>[
        msg('a', outbound: true),
        DateTime(2026, 9, 10),
        msg('b', outbound: true),
      ];
      expect(startsRun(items, 2), isTrue);
    });

    test('a divider is not a message and opens nothing', () {
      expect(startsRun(<Object>[DateTime(2026, 9, 10)], 0), isFalse);
    });

    test('an index outside the list is safe', () {
      expect(startsRun(<Object>[], 0), isFalse);
      expect(startsRun(<Object>[msg('a', outbound: true)], 5), isFalse);
    });
  });
}
