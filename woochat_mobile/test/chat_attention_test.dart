import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/models/chat.dart';
import 'package:woochat_mobile/src/models/chat_attention.dart';

// Chats → All · Mine · Chatbot, mirroring the web's useChatAttention.
void main() {
  final now = DateTime.utc(2026, 10, 9, 12);
  DateTime ago(Duration d) => now.subtract(d);
  const me = 'me';

  Chat chat(String id, {String? assignedTo}) =>
      Chat.fromMap(<String, dynamic>{
        'id': id,
        'user_id': 'owner',
        'assigned_to': assignedTo,
      });

  group('candidates', () {
    test('an alert puts the chat in Mine, the newest one wins', () {
      final found = ChatAttention.candidates(
        alerts: <AlertRow>[
          (chatId: 'c1', createdAt: ago(const Duration(hours: 1))),
          (chatId: 'c1', createdAt: ago(const Duration(hours: 5))),
        ],
        agentRows: const <AgentRow>[],
        now: now,
      );
      expect(found['c1']!.alerted, isTrue);
      expect(found['c1']!.since, ago(const Duration(hours: 1)));
    });

    test('a later handover moves the clock but keeps the alert', () {
      final found = ChatAttention.candidates(
        alerts: <AlertRow>[
          (chatId: 'c1', createdAt: ago(const Duration(hours: 5))),
        ],
        agentRows: <AgentRow>[
          (
            chatId: 'c1',
            handedOverAt: ago(const Duration(hours: 1)),
            pausedUntil: null,
          ),
        ],
        now: now,
      );
      expect(found['c1']!.since, ago(const Duration(hours: 1)));
      expect(found['c1']!.alerted, isTrue);
    });

    test('a handover older than three days does not count', () {
      final found = ChatAttention.candidates(
        alerts: const <AlertRow>[],
        agentRows: <AgentRow>[
          (
            chatId: 'old',
            handedOverAt: ago(const Duration(days: 4)),
            pausedUntil: null,
          ),
        ],
        now: now,
      );
      expect(found, isEmpty);
    });
  });

  group('unsettled', () {
    final since = ago(const Duration(hours: 2));
    final candidates = <String, AttentionNeed>{
      'waiting': AttentionNeed(since: since, alerted: true),
      'replied': AttentionNeed(since: since, alerted: true),
      'replied-before': AttentionNeed(since: since, alerted: true),
    };

    test('a reply or "Checked" after the flag clears it; one before does not',
        () {
      final left = ChatAttention.unsettled(candidates, <String, DateTime>{
        'replied': ago(const Duration(hours: 1)),
        'replied-before': ago(const Duration(hours: 3)),
      });
      expect(left.keys, unorderedEquals(<String>['waiting', 'replied-before']));
    });
  });

  group('needsMe', () {
    final attention = ChatAttention(
      needs: <String, AttentionNeed>{
        'alerted': AttentionNeed(since: now, alerted: true),
        'handed': AttentionNeed(since: now, alerted: false),
      },
      bot: const <String>{'bot'},
    );

    test('an alert is mine whoever the chat is assigned to', () {
      expect(attention.needsMe(chat('alerted', assignedTo: 'x'), me), isTrue);
    });

    test('a handover is mine only when the chat is assigned to me', () {
      expect(attention.needsMe(chat('handed', assignedTo: me), me), isTrue);
      expect(attention.needsMe(chat('handed', assignedTo: 'x'), me), isFalse);
    });

    test('matches routes each pill', () {
      expect(attention.matches(OwnerView.all, chat('any'), me), isTrue);
      expect(attention.matches(OwnerView.bot, chat('bot'), me), isTrue);
      expect(attention.matches(OwnerView.bot, chat('alerted'), me), isFalse);
      expect(attention.matches(OwnerView.mine, chat('alerted'), me), isTrue);
    });
  });

  test('Chatbot holds the AI\'s chats that are not handed over or paused', () {
    final bot = ChatAttention.botChats(<AgentRow>[
      (chatId: 'live', handedOverAt: null, pausedUntil: null),
      (chatId: 'handed', handedOverAt: now, pausedUntil: null),
      (
        chatId: 'paused',
        handedOverAt: null,
        pausedUntil: now.add(const Duration(hours: 1)),
      ),
      (
        chatId: 'pause-over',
        handedOverAt: null,
        pausedUntil: now.subtract(const Duration(hours: 1)),
      ),
    ], now);
    expect(bot, unorderedEquals(<String>['live', 'pause-over']));
  });
}
