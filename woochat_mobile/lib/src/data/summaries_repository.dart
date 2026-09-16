import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';

/// One written summary of a conversation.
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.text,
    this.createdAt,
    this.dayNumber,
  });

  final String id;
  final String text;
  final DateTime? createdAt;

  /// Which day of the follow-up it was written on, when the funnel set it.
  final int? dayNumber;

  factory ChatSummary.fromMap(Map<String, dynamic> map) => ChatSummary(
        id: map['id'].toString(),
        text: (map['summary'] as String? ?? '').trim(),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')
            ?.toLocal(),
        dayNumber: (map['day_number'] as num?)?.toInt(),
      );
}

/// Raised when a summary could not be read or written.
class SummaryException implements Exception {
  const SummaryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The `chat_summaries` table the web's B2B page and lead cards read.
///
/// A summary is a record of what was said, so it accumulates: adding one is
/// always a new row, never an edit of the last, and the list is the history.
class SummariesRepository {
  const SummariesRepository();

  /// Newest first.
  Future<List<ChatSummary>> forChat(String chatId) async {
    try {
      final rows = await db
          .from(Db.chatSummaries)
          .select('id, summary, created_at, day_number')
          .eq('chat_id', chatId)
          .order('created_at', ascending: false) as List<dynamic>;
      return rows
          .whereType<Map<String, dynamic>>()
          .map(ChatSummary.fromMap)
          .where((summary) => summary.text.isNotEmpty)
          .toList();
    } on PostgrestException catch (error) {
      throw SummaryException('Could not load summaries: ${error.message}');
    }
  }

  Future<ChatSummary> add({
    required String chatId,
    required String authUserId,
    required String text,
  }) async {
    final body = text.trim();
    if (body.isEmpty) {
      throw const SummaryException('Write the summary first.');
    }
    try {
      final row = await db
          .from(Db.chatSummaries)
          .insert(<String, dynamic>{
            'chat_id': chatId,
            'user_id': authUserId,
            'summary': body,
          })
          .select('id, summary, created_at, day_number')
          .single();
      return ChatSummary.fromMap(row);
    } on PostgrestException catch (error) {
      throw SummaryException('Could not add the summary: ${error.message}');
    }
  }
}
