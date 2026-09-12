import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';

/// One saved reply from the existing `shortcuts` table.
class QuickReply {
  const QuickReply({
    required this.id,
    required this.title,
    required this.message,
  });

  final String id;

  /// The trigger word, stored without a slash even when typed with one.
  final String title;
  final String message;

  factory QuickReply.fromMap(Map<String, dynamic> map) {
    final title = (map['title'] as String? ?? '').trim();
    return QuickReply(
      id: map['id'].toString(),
      // Rows are saved either way round; the slash belongs to the UI.
      title: title.startsWith('/') ? title.substring(1) : title,
      message: (map['message'] as String? ?? '').trim(),
    );
  }
}

/// Raised when a quick reply could not be saved.
class ShortcutException implements Exception {
  const ShortcutException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads and writes the saved replies behind the composer's `/` menu.
class ShortcutsRepository {
  const ShortcutsRepository();

  /// Saves a new quick reply for [userId]. The title is stored without its
  /// slash — the slash belongs to the UI.
  Future<QuickReply> create({
    required String userId,
    required String title,
    required String message,
  }) async {
    final cleanTitle = title.trim().replaceFirst(RegExp(r'^/+'), '');
    try {
      final row = await db
          .from(Db.shortcuts)
          .insert(<String, dynamic>{
            'user_id': userId,
            'title': cleanTitle,
            'message': message.trim(),
          })
          .select('id, title, message')
          .single();
      return QuickReply.fromMap(row);
    } on PostgrestException catch (error) {
      throw ShortcutException(
        'Could not save the quick reply: ${error.message}',
      );
    }
  }

  /// The workspace owner's shortcuts plus the signed-in user's own.
  ///
  /// Both ids are asked for explicitly rather than relying on RLS alone, so a
  /// team member sees the shared set as well as anything they saved.
  Future<List<QuickReply>> fetchAll({
    required String tenantAdminId,
    required String authUserId,
  }) async {
    final owners = <String>{tenantAdminId, authUserId}.toList();

    try {
      final rows = await db
          .from(Db.shortcuts)
          .select('id, title, message')
          .inFilter('user_id', owners)
          .order('title', ascending: true) as List;

      return rows
          .whereType<Map<String, dynamic>>()
          .map(QuickReply.fromMap)
          .where((reply) => reply.title.isNotEmpty && reply.message.isNotEmpty)
          .toList();
    } on PostgrestException {
      // The composer falls back to plain typing rather than blocking on this.
      return const <QuickReply>[];
    }
  }
}
