import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../models/chat.dart';
import 'supabase_client.dart';

/// Reads the existing `chats` table, scoped to the tenant.
///
/// `chats` has no tenant column — rows belong to the tenant owner through
/// `chats.user_id`, which is the uuid returned by `tenant_admin_id(p_user)`.
class ChatsRepository {
  const ChatsRepository();

  /// PostgREST caps a single response at its `max-rows` setting (1000 on a
  /// default self-hosted install), so the list is walked in id order.
  static const int _pageSize = 1000;

  /// Every chat the tenant owns, paged by ascending id like the web app does.
  Future<List<Chat>> fetchChats({
    required String tenantAdminId,
    bool includeArchived = false,
  }) async {
    final rows = await _fetchAllRows(tenantAdminId);
    return _mapAndSort(rows, includeArchived: includeArchived);
  }

  Future<List<Map<String, dynamic>>> _fetchAllRows(
    String tenantAdminId,
  ) async {
    final collected = <Map<String, dynamic>>[];
    String? cursor;
    while (true) {
      var query = db
          .from(Db.chats)
          .select(Chat.selectColumns)
          .eq('user_id', tenantAdminId);
      if (cursor != null) query = query.gt('id', cursor);
      final rows = await query.order('id', ascending: true).limit(_pageSize)
          as List<dynamic>;
      final page = rows.whereType<Map<String, dynamic>>().toList();
      collected.addAll(page);
      if (page.length < _pageSize) break;
      cursor = page.last['id']?.toString();
      if (cursor == null) break;
    }
    return collected;
  }

  /// Live chat list.
  ///
  /// `.stream()` would be simpler, but its initial fetch is a single request
  /// and therefore silently truncated at `max-rows` — a tenant with 8000+
  /// chats saw only the first 1000 and every count derived from them was
  /// wrong. Instead the full list is paged in once and then kept current by
  /// applying realtime inserts / updates / deletes on top.
  Stream<List<Chat>> watchChats({
    required String tenantAdminId,
    bool includeArchived = false,
  }) {
    final byId = <String, Map<String, dynamic>>{};
    // Ids deleted while the initial pages were still loading, so a late page
    // cannot resurrect them.
    final deleted = <String>{};
    var loaded = false;
    RealtimeChannel? channel;
    late final StreamController<List<Chat>> controller;

    void emit() {
      if (controller.isClosed) return;
      controller.add(
        _mapAndSort(byId.values.toList(), includeArchived: includeArchived),
      );
    }

    void onChange(PostgresChangePayload payload) {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final row = payload.newRecord;
          final id = row['id']?.toString();
          if (id == null) return;
          // A row moved to another owner is no longer ours.
          if (row['user_id']?.toString() != tenantAdminId) {
            byId.remove(id);
          } else {
            byId[id] = row;
          }
        case PostgresChangeEvent.delete:
          final id = payload.oldRecord['id']?.toString();
          if (id == null) return;
          byId.remove(id);
          deleted.add(id);
        case PostgresChangeEvent.all:
          return;
      }
      if (loaded) emit();
    }

    Future<void> start() async {
      // Subscribe before paging so nothing that changes mid-load is missed;
      // a live row always wins over the snapshot that follows it.
      channel = db
          .channel('chats:$tenantAdminId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: Db.chats,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: tenantAdminId,
            ),
            callback: onChange,
          )
          .subscribe();

      try {
        final rows = await _fetchAllRows(tenantAdminId);
        for (final row in rows) {
          final id = row['id']?.toString();
          if (id == null || deleted.contains(id)) continue;
          byId.putIfAbsent(id, () => row);
        }
        loaded = true;
        emit();
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<List<Chat>>(
      onListen: start,
      onCancel: () async {
        final active = channel;
        channel = null;
        if (active != null) await db.removeChannel(active);
      },
    );
    return controller.stream;
  }

  /// Finds an existing conversation with the same phone number, comparing on
  /// digits only so '+91 98765 43210' matches '919876543210'.
  ///
  /// Called before creating a chat — the web app skips this in its New Chat
  /// dialog and can end up with duplicates.
  Future<Chat?> findChatByPhone({
    required String ownerId,
    required String phone,
  }) async {
    final wanted = Chat.normalisePhone(phone);
    if (wanted.isEmpty) return null;

    final rows = await _fetchAllRows(ownerId);
    for (final row in rows) {
      final chat = Chat.fromMap(row);
      if (chat.normalisedPhone == wanted) return chat;
    }
    return null;
  }

  /// Creates a conversation row.
  ///
  /// Writes only the three columns the backend expects; every other column
  /// (unread_count, is_pinned, timestamps, ...) has a database default.
  /// This touches no WhatsApp API — it only creates the local row.
  Future<Chat> createChat({
    required String ownerId,
    required String contactName,
    required String contactPhone,
  }) async {
    final row = await db
        .from(Db.chats)
        .insert(<String, dynamic>{
          'user_id': ownerId,
          'contact_name': contactName.trim(),
          'contact_phone': contactPhone.trim(),
        })
        .select(Chat.selectColumns)
        .single();

    return Chat.fromMap(row);
  }

  /// Row-menu toggles. Each writes exactly what the web app writes, and the
  /// list picks the change up through the realtime subscription.
  Future<void> setPinned(String chatId, bool pinned) =>
      _update(chatId, <String, dynamic>{'is_pinned': pinned});

  Future<void> setArchived(String chatId, bool archived) =>
      _update(chatId, <String, dynamic>{'is_archived': archived});

  /// Marking unread also seeds the counter with 1 so the badge has a number;
  /// marking read clears both.
  Future<void> setUnread(String chatId, bool unread) => _update(
        chatId,
        <String, dynamic>{'is_unread': unread, 'unread_count': unread ? 1 : 0},
      );

  Future<void> _update(String chatId, Map<String, dynamic> values) =>
      db.from(Db.chats).update(values).eq('id', chatId);

  /// The same three toggles across a selection, in one write each — the
  /// realtime feed carries every changed row back to the list.
  Future<void> setPinnedMany(Iterable<String> chatIds, bool pinned) =>
      _updateMany(chatIds, <String, dynamic>{'is_pinned': pinned});

  Future<void> setArchivedMany(Iterable<String> chatIds, bool archived) =>
      _updateMany(chatIds, <String, dynamic>{'is_archived': archived});

  Future<void> setUnreadMany(Iterable<String> chatIds, bool unread) =>
      _updateMany(
        chatIds,
        <String, dynamic>{'is_unread': unread, 'unread_count': unread ? 1 : 0},
      );

  Future<void> _updateMany(
    Iterable<String> chatIds,
    Map<String, dynamic> values,
  ) async {
    final ids = chatIds.toList();
    if (ids.isEmpty) return;
    await db.from(Db.chats).update(values).inFilter('id', ids);
  }

  Future<Chat?> fetchChat(String chatId) async {
    final row = await db
        .from(Db.chats)
        .select(Chat.selectColumns)
        .eq('id', chatId)
        .maybeSingle();
    if (row == null) return null;
    return Chat.fromMap(row);
  }

  List<Chat> _mapAndSort(
    List<dynamic> rows, {
    required bool includeArchived,
  }) {
    final chats = rows
        .whereType<Map<String, dynamic>>()
        .map(Chat.fromMap)
        .where((chat) => includeArchived || !chat.isArchived)
        .toList();

    // Pinned first, then most recent activity.
    chats.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final aAt = a.lastMessageAt;
      final bAt = b.lastMessageAt;
      if (aAt == null && bAt == null) return 0;
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return bAt.compareTo(aAt);
    });
    return chats;
  }
}
