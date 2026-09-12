import '../core/constants.dart';
import '../models/chat.dart';
import '../models/chat_filters.dart';
import 'supabase_client.dart';

/// Loads the reference data the "More filters" dropdown needs.
///
/// Everything is read from tables and RPCs that already exist; RLS scopes each
/// read, so no tenant filter is added on top. The chat list itself is loaded in
/// full and filtered in memory, so these are plain whole-table reads too.
class ChatFiltersRepository {
  const ChatFiltersRepository();

  /// `chat_labels` and `customer_collections` can outgrow PostgREST's default
  /// page, so both are walked by ascending id like the web app does.
  static const int _pageSize = 1000;

  Future<ChatFilterData> load({String? funnelStart, String? funnelEnd}) async {
    final results = await Future.wait<Object>(<Future<Object>>[
      _labels(),
      _chatLabels(),
      _categories(),
      _chatCategories(),
      _products(),
      _customerCollections(),
      _adProductMap(),
      _automations(),
      _notes(),
      _contactNotes(),
      _contactDirectory(),
      _adSourcedChatIds(),
      _funnelChatIds(start: funnelStart, end: funnelEnd),
    ]);

    final labels = results[0] as List<Label>;
    final chatLabels = results[1] as List<ChatLabel>;
    final categories = results[2] as List<Category>;
    final chatCategories = results[3] as Map<String, List<String>>;
    final products = results[4] as List<Product>;
    final collections = results[5] as Map<String, String>;
    final adMap = results[6] as Map<String, String>;
    final automations = results[7] as List<Automation>;
    final noteTags = results[8] as List<String>;
    final notesByContact = results[9] as Map<String, List<Note>>;
    final directory = results[10] as Map<String, DirectoryEntry>;
    final adSourced = results[11] as Set<String>;
    final funnel = results[12] as ({Set<String> failed, Set<String> replied});

    final labelIdsByChat = <String, List<String>>{};
    final labelAppliedAt = <String, DateTime>{};
    for (final row in chatLabels) {
      final ids = labelIdsByChat.putIfAbsent(row.chatId, () => <String>[]);
      if (!ids.contains(row.labelId)) ids.add(row.labelId);
      final at = row.createdAt;
      if (at != null) {
        labelAppliedAt.putIfAbsent('${row.chatId}:${row.labelId}', () => at);
      }
    }

    return ChatFilterData(
      labels: labels,
      labelIdsByChat: labelIdsByChat,
      labelAppliedAt: labelAppliedAt,
      categories: categories,
      categoryIdsByChat: chatCategories,
      products: products,
      collectionProductIdByPhone: collections,
      productIdByAdHeadline: adMap,
      automations: automations,
      adSourcedChatIds: adSourced,
      funnelFailed: funnel.failed,
      funnelReplied: funnel.replied,
      contactIdByPhone: <String, String>{
        for (final entry in directory.entries) entry.key: entry.value.id,
      },
      contactLabelIdsByPhone: <String, List<String>>{
        for (final entry in directory.entries)
          entry.key: entry.value.labelIds,
      },
      contactPhotoByPhone: <String, String>{
        for (final entry in directory.entries)
          if (entry.value.photoUrl?.trim().isNotEmpty ?? false)
            entry.key: entry.value.photoUrl!.trim(),
      },
      notesByContactId: notesByContact,
      noteTags: noteTags,
    );
  }

  /// Only the funnel sets move with the date range, so the chat list can
  /// refresh them without re-reading every table.
  Future<({Set<String> failed, Set<String> replied})> refreshFunnel({
    String? start,
    String? end,
  }) =>
      _funnelChatIds(start: start, end: end);

  Future<List<Map<String, dynamic>>> _all(
    String table,
    String columns, {
    bool paged = false,
  }) async {
    if (!paged) {
      final rows = await db.from(table).select(columns) as List<dynamic>;
      return rows.whereType<Map<String, dynamic>>().toList();
    }

    final collected = <Map<String, dynamic>>[];
    String? cursor;
    while (true) {
      var query = db.from(table).select(columns);
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

  Future<List<Label>> _labels() async =>
      (await _all(Db.labels, 'id, name, color')).map(Label.fromMap).toList();

  Future<List<ChatLabel>> _chatLabels() async =>
      (await _all(Db.chatLabels, 'id, chat_id, label_id, created_at',
              paged: true))
          .map(ChatLabel.fromMap)
          .toList();

  Future<List<Category>> _categories() async =>
      (await _all(Db.categories, 'id, name, color'))
          .map(Category.fromMap)
          .toList();

  Future<Map<String, List<String>>> _chatCategories() async {
    final rows = await _all(Db.chatCategories, 'chat_id, category_id');
    final map = <String, List<String>>{};
    for (final row in rows) {
      final chatId = row['chat_id']?.toString();
      final categoryId = row['category_id']?.toString();
      if (chatId == null || categoryId == null) continue;
      map.putIfAbsent(chatId, () => <String>[]).add(categoryId);
    }
    return map;
  }

  Future<List<Product>> _products() async =>
      (await _all(Db.products, 'id, title')).map(Product.fromMap).toList();

  Future<Map<String, String>> _customerCollections() async {
    final rows = await _all(
      Db.customerCollections,
      'id, phone, product_id',
      paged: true,
    );
    final map = <String, String>{};
    for (final row in rows) {
      final phone = Chat.normalisePhone(row['phone']?.toString());
      final productId = row['product_id']?.toString();
      if (phone.isEmpty || productId == null) continue;
      map[phone] = productId;
    }
    return map;
  }

  Future<Map<String, String>> _adProductMap() async {
    final rows = await _all(Db.adProductMap, 'ad_headline, product_id');
    final map = <String, String>{};
    for (final row in rows) {
      final headline = row['ad_headline']?.toString();
      final productId = row['product_id']?.toString();
      if (headline == null || headline.isEmpty || productId == null) continue;
      map[headline] = productId;
    }
    return map;
  }

  Future<List<Automation>> _automations() async =>
      (await _all(Db.automations, 'id, name')).map(Automation.fromMap).toList();

  /// The tag library, used to populate the Notes submenu.
  Future<List<String>> _notes() async {
    final rows = await _all(Db.notes, 'id, note_text, tags');
    final tags = <String>{};
    for (final note in rows.map(Note.fromMap)) {
      for (final tag in note.tags) {
        final trimmed = tag.trim();
        if (trimmed.isNotEmpty) tags.add(trimmed);
      }
    }
    final sorted = tags.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  Future<Map<String, List<Note>>> _contactNotes() async {
    final rows = await _all(Db.contactNotes, 'contact_id, notes(*)');
    final map = <String, List<Note>>{};
    for (final row in rows) {
      final contactId = row['contact_id']?.toString();
      final note = row['notes'];
      if (contactId == null || note is! Map<String, dynamic>) continue;
      final parsed = Note.fromMap(note);
      final list = map.putIfAbsent(contactId, () => <Note>[]);
      if (!list.any((existing) => existing.id == parsed.id)) list.add(parsed);
    }
    return map;
  }

  Future<Map<String, DirectoryEntry>> _contactDirectory() async {
    final result = await db.rpc<dynamic>(Db.chatContactDirectoryFn);
    if (result is! Map) return const <String, DirectoryEntry>{};

    final map = <String, DirectoryEntry>{};
    result.forEach((phone, value) {
      if (value is Map<String, dynamic>) {
        map[phone.toString()] = DirectoryEntry.fromMap(value);
      }
    });
    return map;
  }

  Future<Set<String>> _adSourcedChatIds() async {
    final result = await db.rpc<dynamic>(Db.adSourcedChatIdsFn);
    if (result is List) {
      return result
          .where((id) => id != null)
          .map((id) => id.toString())
          .toSet();
    }
    return const <String>{};
  }

  /// Called with no params when no range is picked, which is what the web does
  /// to get the server's default (today) window for `replied`.
  Future<({Set<String> failed, Set<String> replied})> _funnelChatIds({
    String? start,
    String? end,
  }) async {
    final params = <String, dynamic>{
      if (start != null && end != null) ...<String, dynamic>{
        Db.funnelStartParam: start,
        Db.funnelEndParam: end,
      },
    };

    final result = await db.rpc<dynamic>(Db.funnelChatIdsFn, params: params);
    final map = result is Map<String, dynamic> ? result : null;

    Set<String> ids(String key) {
      final value = map?[key];
      if (value is List) {
        return value
            .where((id) => id != null)
            .map((id) => id.toString())
            .toSet();
      }
      return const <String>{};
    }

    return (failed: ids('failed'), replied: ids('replied'));
  }
}
