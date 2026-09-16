import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/thread_items.dart';
import 'package:woochat_mobile/src/models/message.dart';

Message msg(String id, int minute) => Message(
      id: id,
      chatId: 'c1',
      userId: 'u1',
      direction: 'outbound',
      content: id,
      createdAt: DateTime(2026, 9, 14, 10, minute),
    );

void main() {
  group('mergeThread', () {
    test('older pages sit above the feed, pending rows below it', () {
      final merged = mergeThread(
        older: <Message>[msg('o1', 1), msg('o2', 2)],
        feed: <Message>[msg('f1', 10), msg('f2', 11)],
        pending: <String, Message>{'p1': msg('p1', 12)},
      );

      expect(
        merged.messages.map((m) => m.id),
        <String>['o1', 'o2', 'f1', 'f2', 'p1'],
      );
      expect(merged.caughtUp, isEmpty);
    });

    test('a pending row the feed now carries is drawn once and reported', () {
      final merged = mergeThread(
        feed: <Message>[msg('f1', 10), msg('p1', 12)],
        pending: <String, Message>{'p1': msg('p1', 12), 'p2': msg('p2', 13)},
      );

      expect(merged.messages.map((m) => m.id), <String>['f1', 'p1', 'p2']);
      expect(merged.caughtUp, <String>['p1']);
    });

    test('an older page overlapping the feed is not duplicated', () {
      final merged = mergeThread(
        older: <Message>[msg('o1', 1), msg('f1', 10)],
        feed: <Message>[msg('f1', 10), msg('f2', 11)],
      );

      expect(merged.messages.map((m) => m.id), <String>['o1', 'f1', 'f2']);
    });

    test('nothing extra leaves the feed untouched', () {
      final feed = <Message>[msg('f1', 10)];
      final merged = mergeThread(feed: feed);
      expect(merged.messages.map((m) => m.id), <String>['f1']);
    });
  });
}
