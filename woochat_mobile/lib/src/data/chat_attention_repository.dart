import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../models/chat_attention.dart';
import 'supabase_client.dart';

/// Raised when "Checked" could not be saved.
class ChatAttentionException implements Exception {
  const ChatAttentionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads what the Mine and Chatbot pills hold, and writes "Checked", which
/// clears a chat out of Mine.
///
/// Same queries as the web app's `useChatAttention`; nothing here creates a
/// table, a column or a policy.
class ChatAttentionRepository {
  const ChatAttentionRepository();

  /// Ids per `in` filter, so the request URL stays short.
  static const int _slice = 100;

  Future<ChatAttention> load(String userId) async {
    final now = DateTime.now();
    final since = now.subtract(ChatAttention.window).toUtc().toIso8601String();

    final results = await Future.wait<List<dynamic>>(<Future<List<dynamic>>>[
      db
          .from(Db.chatAlerts)
          .select('chat_id, created_at')
          .eq('user_id', userId)
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(300),
      db
          .from(Db.salesAgentChats)
          .select('chat_id, handed_over_at, paused_until')
          .eq('active', true)
          .limit(2000),
    ]);

    final alerts = <AlertRow>[
      for (final row in results[0].whereType<Map<String, dynamic>>())
        if (_id(row['chat_id']) case final chatId?)
          if (_time(row['created_at']) case final createdAt?)
            (chatId: chatId, createdAt: createdAt),
    ];
    final agentRows = <AgentRow>[
      for (final row in results[1].whereType<Map<String, dynamic>>())
        if (_id(row['chat_id']) case final chatId?)
          (
            chatId: chatId,
            handedOverAt: _time(row['handed_over_at']),
            pausedUntil: _time(row['paused_until']),
          ),
    ];

    final candidates = ChatAttention.candidates(
      alerts: alerts,
      agentRows: agentRows,
      now: now,
    );
    final settled = await _settledAt(candidates.keys.toList(), since);

    return ChatAttention(
      needs: ChatAttention.unsettled(candidates, settled),
      bot: ChatAttention.botChats(agentRows, now),
    );
  }

  /// Per chat, the later of the last reply a person sent and the moment
  /// someone marked it "Checked". Automations, templates and the AI's own
  /// messages are not a person answering.
  Future<Map<String, DateTime>> _settledAt(
    List<String> chatIds,
    String since,
  ) async {
    final settled = <String, DateTime>{};
    void keepLatest(String chatId, DateTime at) {
      final seen = settled[chatId];
      if (seen == null || at.isAfter(seen)) settled[chatId] = at;
    }

    for (var i = 0; i < chatIds.length; i += _slice) {
      final slice = chatIds.sublist(i, (i + _slice).clamp(0, chatIds.length));
      final results = await Future.wait<List<dynamic>>(<Future<List<dynamic>>>[
        db
            .from(Db.messages)
            .select('chat_id, created_at')
            .inFilter('chat_id', slice)
            .eq('direction', 'outbound')
            .eq('ai_generated', false)
            .isFilter('automation_id', null)
            .isFilter('template_name', null)
            .gte('created_at', since)
            .order('created_at', ascending: false)
            .limit(1000),
        db
            .from(Db.chats)
            .select('id, attention_cleared_at')
            .inFilter('id', slice)
            .not('attention_cleared_at', 'is', null),
      ]);
      for (final row in results[0].whereType<Map<String, dynamic>>()) {
        final chatId = _id(row['chat_id']);
        final at = _time(row['created_at']);
        if (chatId != null && at != null) keepLatest(chatId, at);
      }
      for (final row in results[1].whereType<Map<String, dynamic>>()) {
        final chatId = _id(row['id']);
        final at = _time(row['attention_cleared_at']);
        if (chatId != null && at != null) keepLatest(chatId, at);
      }
    }
    return settled;
  }

  /// "Checked — nothing to reply": the chat leaves Mine. A chat the AI was
  /// running carries on; the RPC leaves that switch alone.
  Future<void> markChecked(String chatId) async {
    try {
      await db.rpc(Db.chatCheckedByTeamFn, params: {'p_chat_id': chatId});
    } on PostgrestException catch (error) {
      throw ChatAttentionException(
        "Couldn't mark it checked: ${error.message}",
      );
    }
  }

  static String? _id(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
