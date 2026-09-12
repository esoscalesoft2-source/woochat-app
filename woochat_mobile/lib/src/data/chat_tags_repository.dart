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

  Future<void> setLabel(
    String chatId,
    String labelId, {
    required bool applied,
  }) =>
      _toggle(Db.chatLabels, 'label_id', chatId, labelId, applied, 'label');

  Future<void> setCategory(
    String chatId,
    String categoryId, {
    required bool applied,
  }) =>
      _toggle(
        Db.chatCategories,
        'category_id',
        chatId,
        categoryId,
        applied,
        'category',
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

  Future<void> _toggle(
    String table,
    String column,
    String chatId,
    String valueId,
    bool applied,
    String what,
  ) async {
    try {
      if (applied) {
        await db.from(table).insert(<String, dynamic>{
          'chat_id': chatId,
          column: valueId,
        });
      } else {
        await db.from(table).delete().eq('chat_id', chatId).eq(column, valueId);
      }
    } on PostgrestException catch (error) {
      throw ChatTagException(
        applied
            ? 'Could not add that $what: ${error.message}'
            : 'Could not remove that $what: ${error.message}',
      );
    }
  }
}
