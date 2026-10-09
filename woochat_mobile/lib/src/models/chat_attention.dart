import 'chat.dart';

/// Chats → All · Mine · Chatbot, the same pills as the web app. Applied after
/// every other filter so each pill counts the rows it opens.
enum OwnerView { all, mine, bot }

/// Why a chat is waiting on a person, and since when.
class AttentionNeed {
  const AttentionNeed({required this.since, required this.alerted});

  final DateTime since;

  /// True when it came from an alert this person got; false when only the
  /// agent's handover put it here.
  final bool alerted;
}

/// One `chat_alerts` row this person got.
typedef AlertRow = ({String chatId, DateTime createdAt});

/// One active `sales_agent_chats` row.
typedef AgentRow = ({
  String chatId,
  DateTime? handedOverAt,
  DateTime? pausedUntil,
});

/// Which chats are waiting on this person, and which the AI is answering.
///
/// Mirrors `useChatAttention` in the web app (src/hooks/useSalesAgentChat.ts)
/// so the pills hold the same chats on both.
class ChatAttention {
  const ChatAttention({required this.needs, required this.bot});

  final Map<String, AttentionNeed> needs;
  final Set<String> bot;

  static const ChatAttention empty = ChatAttention(
    needs: <String, AttentionNeed>{},
    bot: <String>{},
  );

  /// How far back an alert or a handover still counts.
  static const Duration window = Duration(days: 3);

  /// "Mine": an alert this person got, or a chat passed to them, with no
  /// reply from a person since.
  bool needsMe(Chat chat, String userId) {
    final need = needs[chat.id];
    return need != null && (need.alerted || chat.assignedTo == userId);
  }

  bool matches(OwnerView view, Chat chat, String userId) => switch (view) {
    OwnerView.all => true,
    OwnerView.mine => needsMe(chat, userId),
    OwnerView.bot => bot.contains(chat.id),
  };

  /// The chats a person must look at, before replies are taken into account:
  /// the newest alert per chat, then any later handover inside [window].
  static Map<String, AttentionNeed> candidates({
    required List<AlertRow> alerts,
    required List<AgentRow> agentRows,
    required DateTime now,
  }) {
    final cutoff = now.subtract(window);
    final found = <String, AttentionNeed>{};
    for (final alert in alerts) {
      found.putIfAbsent(
        alert.chatId,
        () => AttentionNeed(since: alert.createdAt, alerted: true),
      );
    }
    for (final row in agentRows) {
      final handedOver = row.handedOverAt;
      if (handedOver == null || handedOver.isBefore(cutoff)) continue;
      final current = found[row.chatId];
      if (current == null || handedOver.isAfter(current.since)) {
        found[row.chatId] = AttentionNeed(
          since: handedOver,
          alerted: current?.alerted ?? false,
        );
      }
    }
    return found;
  }

  /// Drops every candidate settled since it was flagged. [settledAt] is, per
  /// chat, the later of the last reply from a person and the moment someone
  /// marked it "Checked" — both mean the same thing here.
  static Map<String, AttentionNeed> unsettled(
    Map<String, AttentionNeed> candidates,
    Map<String, DateTime> settledAt,
  ) => <String, AttentionNeed>{
    for (final entry in candidates.entries)
      if (settledAt[entry.key]?.isBefore(entry.value.since) ?? true)
        entry.key: entry.value,
  };

  /// Chats the AI is answering now: not handed over, not paused.
  static Set<String> botChats(
    List<AgentRow> agentRows,
    DateTime now,
  ) => <String>{
    for (final row in agentRows)
      if (row.handedOverAt == null && !(row.pausedUntil?.isAfter(now) ?? false))
        row.chatId,
  };
}
