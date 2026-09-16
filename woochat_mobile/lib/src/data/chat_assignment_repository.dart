import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';

/// Raised when an assignment could not be read or written.
class ChatAssignmentException implements Exception {
  const ChatAssignmentException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Someone a chat can be assigned to.
class TeamMember {
  const TeamMember({required this.userId, required this.name});

  final String userId;
  final String name;
}

/// Reads and writes `chats.assigned_to`, and resolves the ids behind it to
/// names from the existing `profiles` table.
///
/// Nothing here creates a column, a table or a policy. Whichever profiles RLS
/// lets this user see are the ones that get a name; anyone else falls back to
/// a shortened id, so the picker never hides a real assignee.
class ChatAssignmentRepository {
  const ChatAssignmentRepository();

  /// The id currently in `chats.assigned_to`, or null when unassigned.
  Future<String?> assigneeOf(String chatId) async {
    try {
      final row = await db
          .from(Db.chats)
          .select(Db.assignedToColumn)
          .eq('id', chatId)
          .maybeSingle();
      final value = row?[Db.assignedToColumn];
      return value is String && value.isNotEmpty ? value : null;
    } on PostgrestException catch (error) {
      throw ChatAssignmentException(
        'Could not read who this chat is assigned to: ${error.message}',
      );
    }
  }

  /// Everyone who can be picked, named where a profile is readable.
  ///
  /// [alsoInclude] carries ids the caller already knows are involved — the
  /// chat's owner and its current assignee — so they are offered even when
  /// their profile row is not visible.
  /// Every readable profile's display name by user id, for the owner /
  /// assignee line on each chat row. Profiles that cannot be read are simply
  /// absent; callers fall back to a short id.
  Future<Map<String, String>> displayNames() async {
    final names = <String, String>{};
    try {
      final rows = await db
          .from(Db.profiles)
          .select('user_id, display_name, first_name, last_name') as List;

      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final id = row['user_id']?.toString();
        if (id == null || id.isEmpty) continue;
        final name = _nameFrom(row);
        if (name != null) names[id] = name;
      }
    } on PostgrestException {
      // Names are a nicety; the ids still make the list usable.
    }
    return names;
  }

  /// Whether the signed-in staff member may set a chat back to unread — an
  /// admin capability that an admin can delegate per user from the Users page.
  Future<bool> canMarkUnread(String userId) async {
    try {
      final row = await db
          .from(Db.profiles)
          .select('can_mark_unread')
          .eq('user_id', userId)
          .maybeSingle();
      return row?['can_mark_unread'] == true;
    } on PostgrestException {
      return false;
    }
  }

  /// Everyone who can be picked, named where a profile is readable.
  ///
  /// [alsoInclude] carries ids the caller already knows are involved — the
  /// chat's owner and its current assignee — so they are offered even when
  /// their profile row is not visible.
  Future<List<TeamMember>> members({
    required Set<String> alsoInclude,
    String? signedInUserId,
    String? signedInFallbackName,
  }) async {
    final names = await displayNames();

    final ids = <String>{...names.keys, ...alsoInclude}
      ..removeWhere((id) => id.isEmpty);

    final members = ids
        .map(
          (id) => TeamMember(
            userId: id,
            name: names[id] ??
                (id == signedInUserId && signedInFallbackName != null
                    ? signedInFallbackName
                    : 'User ${id.substring(0, id.length.clamp(0, 8))}'),
          ),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return members;
  }

  /// Reassigns every chat in [chatIds] to [userId] (null clears) through the
  /// existing `transfer_chats_bulk` RPC — the same call the web app's
  /// "Assign User" makes from its select mode. It writes `assigned_to` and
  /// the assignment log in one transaction and returns how many rows moved.
  Future<int> assignMany(Iterable<String> chatIds, String? userId) async {
    final ids = chatIds.toList();
    if (ids.isEmpty) return 0;
    try {
      final result = await db.rpc<dynamic>(
        Db.transferChatsBulkFn,
        params: <String, dynamic>{'p_chat_ids': ids, 'p_to_user': userId},
      );
      return result is num ? result.toInt() : ids.length;
    } on PostgrestException catch (error) {
      throw ChatAssignmentException(
        'Could not reassign the chats: ${error.message}',
      );
    }
  }

  /// Writes the assignment. A null [userId] clears it.
  Future<void> assign(String chatId, String? userId) async {
    try {
      await db
          .from(Db.chats)
          .update(<String, dynamic>{Db.assignedToColumn: userId})
          .eq('id', chatId);
    } on PostgrestException catch (error) {
      throw ChatAssignmentException(
        'Could not change the assignment: ${error.message}',
      );
    }
  }

  static String? _nameFrom(Map<String, dynamic> row) {
    final display = (row['display_name'] as String?)?.trim();
    if (display != null && display.isNotEmpty) return display;

    final parts = <String>[
      (row['first_name'] as String?)?.trim() ?? '',
      (row['last_name'] as String?)?.trim() ?? '',
    ].where((part) => part.isNotEmpty);

    return parts.isEmpty ? null : parts.join(' ');
  }
}
