import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../models/chat_filters.dart';
import 'supabase_client.dart';

/// Raised when a label or category could not be applied or removed.
class ChatTagException implements Exception {
  const ChatTagException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What one chat's label and category pickers need to draw themselves.
class ChatTags {
  const ChatTags({
    required this.labels,
    required this.categories,
    required this.labelIds,
    required this.categoryIds,
  });

  static const ChatTags empty = ChatTags(
    labels: <Label>[],
    categories: <Category>[],
    labelIds: <String>{},
    categoryIds: <String>{},
  );

  /// Everything on offer in the workspace.
  final List<Label> labels;
  final List<Category> categories;

  /// What is applied to this chat right now.
  final Set<String> labelIds;
  final Set<String> categoryIds;

  ChatTags copyWith({Set<String>? labelIds, Set<String>? categoryIds}) =>
      ChatTags(
        labels: labels,
        categories: categories,
        labelIds: labelIds ?? this.labelIds,
        categoryIds: categoryIds ?? this.categoryIds,
      );
}

/// Reads and edits the label / category rows attached to a single chat.
///
/// Only the existing `labels`, `categories`, `chat_labels` and
/// `chat_categories` tables are used — the same ones the chats list already
/// reads for its filters.
class ChatTagsRepository {
  const ChatTagsRepository();

  Future<ChatTags> load(String chatId) async {
    final results = await Future.wait(<Future<Object>>[
      _labels(),
      _categories(),
      _appliedIds(Db.chatLabels, 'label_id', chatId),
      _appliedIds(Db.chatCategories, 'category_id', chatId),
    ]);

    return ChatTags(
      labels: results[0] as List<Label>,
      categories: results[1] as List<Category>,
      labelIds: results[2] as Set<String>,
      categoryIds: results[3] as Set<String>,
    );
  }

  /// [chatOwnerId] is the chat's own `user_id` and [authUserId] the signed-in
  /// user — both are needed because the link row carries a `user_id` of its
  /// own; see [_toggle].
  Future<void> setLabel(
    String chatId,
    String labelId, {
    required bool applied,
    required String chatOwnerId,
    required String authUserId,
  }) => _toggle(
    Db.chatLabels,
    'label_id',
    chatId,
    labelId,
    applied,
    'label',
    chatOwnerId: chatOwnerId,
    authUserId: authUserId,
  );

  Future<void> setCategory(
    String chatId,
    String categoryId, {
    required bool applied,
    required String chatOwnerId,
    required String authUserId,
  }) => _toggle(
    Db.chatCategories,
    'category_id',
    chatId,
    categoryId,
    applied,
    'category',
    chatOwnerId: chatOwnerId,
    authUserId: authUserId,
  );

  Future<List<Label>> _labels() async {
    final rows = await db.from(Db.labels).select('id, name, color') as List;
    return rows.whereType<Map<String, dynamic>>().map(Label.fromMap).toList();
  }

  Future<List<Category>> _categories() async {
    final rows = await db.from(Db.categories).select('id, name, color') as List;
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Category.fromMap)
        .toList();
  }

  Future<Set<String>> _appliedIds(
    String table,
    String column,
    String chatId,
  ) async {
    final rows =
        await db.from(table).select(column).eq('chat_id', chatId) as List;
    return rows
        .whereType<Map<String, dynamic>>()
        .map((row) => row[column]?.toString())
        .whereType<String>()
        .toSet();
  }

  /// Postgres' unique_violation. The row already being there is the state
  /// being asked for, not a failure.
  static const String _duplicateKey = '23505';

  /// Adds or removes one `chat_labels` / `chat_categories` row.
  ///
  /// Both tables carry a `user_id` of their own, and it is NOT optional —
  /// leaving it out is what made filing a chat under a category fail. It is
  /// written as the CHAT's owner so the row lands in that tenant; RLS may
  /// refuse another user's id (a super admin holds only the own-row policy),
  /// so the write retries as the signed-in user. This is what the web app
  /// does in `addChatToCategory`.
  Future<void> _toggle(
    String table,
    String column,
    String chatId,
    String valueId,
    bool applied,
    String what, {
    required String chatOwnerId,
    required String authUserId,
  }) async {
    if (!applied) {
      try {
        await db.from(table).delete().eq('chat_id', chatId).eq(column, valueId);
        return;
      } on PostgrestException catch (error) {
        throw ChatTagException('Could not remove that $what: ${error.message}');
      }
    }

    Future<void> insertAs(String userId) => db.from(table).insert(
      <String, dynamic>{'chat_id': chatId, column: valueId, 'user_id': userId},
    );

    final owner = chatOwnerId.isEmpty ? authUserId : chatOwnerId;
    try {
      await insertAs(owner);
    } on PostgrestException catch (error) {
      if (error.code == _duplicateKey) return;
      if (owner == authUserId) {
        throw ChatTagException('Could not add that $what: ${error.message}');
      }
      try {
        await insertAs(authUserId);
      } on PostgrestException catch (retryError) {
        if (retryError.code == _duplicateKey) return;
        throw ChatTagException(
          'Could not add that $what: ${retryError.message}',
        );
      }
    }
  }
}
