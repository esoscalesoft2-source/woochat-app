import '../core/constants.dart';
import '../models/chat.dart';
import 'supabase_client.dart';

/// Reads the existing `chats` table, scoped to the tenant.
///
/// `chats` has no tenant column — rows belong to the tenant owner through
/// `chats.user_id`, which is the uuid returned by `tenant_admin_id(p_user)`.
class ChatsRepository {
  const ChatsRepository();

  Future<List<Chat>> fetchChats({
    required String tenantAdminId,
    bool includeArchived = false,
  }) async {
    final rows = await db
        .from(Db.chats)
        .select(Chat.selectColumns)
        .eq('user_id', tenantAdminId)
        .order('last_message_at', ascending: false, nullsFirst: false)
        .limit(200) as List<dynamic>;

    return _mapAndSort(rows, includeArchived: includeArchived);
  }

  /// Live chat list. Supabase realtime streams support a single filter, so
  /// archiving is filtered client-side.
  Stream<List<Chat>> watchChats({
    required String tenantAdminId,
    bool includeArchived = false,
  }) {
    return db
        .from(Db.chats)
        .stream(primaryKey: <String>['id'])
        .eq('user_id', tenantAdminId)
        .map((rows) => _mapAndSort(rows, includeArchived: includeArchived));
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

    final rows = await db
        .from(Db.chats)
        .select(Chat.selectColumns)
        .eq('user_id', ownerId) as List<dynamic>;

    for (final row in rows.whereType<Map<String, dynamic>>()) {
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
