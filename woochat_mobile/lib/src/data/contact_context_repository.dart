import '../core/constants.dart';
import '../models/chat.dart';
import '../models/chat_filters.dart';
import 'supabase_client.dart';

/// What the contact info sheet shows beyond the chat row itself: the Contacts
/// record, the product the customer is on, and their notes.
class ContactContext {
  const ContactContext({
    this.contactId,
    this.name,
    this.photoUrl,
    this.contactLabelIds = const <String>[],
    this.productName,
    this.notes = const <Note>[],
  });

  static const ContactContext empty = ContactContext();

  final String? contactId;

  /// The Contacts-page name, e.g. "Fi00008-Loki".
  final String? name;
  final String? photoUrl;

  /// Labels held on the contact record rather than the chat.
  final List<String> contactLabelIds;

  /// A hand-picked collection first, else the product inferred from the ad
  /// the chat came in on — the same precedence as the list row's 🛍 chip.
  final String? productName;

  /// Newest first.
  final List<Note> notes;
}

/// Loads [ContactContext] for one chat with targeted reads, so opening a
/// thread does not pull the whole workspace the way the list's filters do.
class ContactContextRepository {
  const ContactContextRepository();

  Future<ContactContext> load(Chat chat) async {
    final phone = chat.normalisedPhone;

    final results = await Future.wait<Object?>(<Future<Object?>>[
      _directoryEntry(phone),
      _productName(phone: phone, adHeadline: chat.lastAdHeadline),
    ]);

    final entry = results[0] as DirectoryEntry?;
    final productName = results[1] as String?;
    final notes = entry == null ? const <Note>[] : await _notes(entry.id);

    return ContactContext(
      contactId: entry?.id,
      name: entry?.name,
      photoUrl: entry?.photoUrl,
      contactLabelIds: entry?.labelIds ?? const <String>[],
      productName: productName,
      notes: notes,
    );
  }

  /// Every contact's name and photo, keyed by normalised phone — for lists
  /// that need to name many chats at once, such as the forward picker.
  Future<Map<String, DirectoryEntry>> directory() async {
    try {
      final result = await db.rpc<dynamic>(Db.chatContactDirectoryFn);
      if (result is! Map) return const <String, DirectoryEntry>{};
      return <String, DirectoryEntry>{
        for (final entry in result.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key.toString():
                DirectoryEntry.fromMap(entry.value as Map<String, dynamic>),
      };
    } catch (_) {
      return const <String, DirectoryEntry>{};
    }
  }

  /// The directory RPC returns every contact keyed by normalised phone; only
  /// this chat's entry is kept.
  Future<DirectoryEntry?> _directoryEntry(String phone) async {
    if (phone.isEmpty) return null;
    try {
      final result = await db.rpc<dynamic>(Db.chatContactDirectoryFn);
      if (result is! Map) return null;
      final value = result[phone];
      return value is Map<String, dynamic> ? DirectoryEntry.fromMap(value) : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _productName({
    required String phone,
    required String? adHeadline,
  }) async {
    try {
      final productId = await _collectionProductId(phone) ??
          await _adProductId(adHeadline);
      if (productId == null) return null;

      final row = await db
          .from(Db.products)
          .select('title')
          .eq('id', productId)
          .maybeSingle();
      final title = row?['title']?.toString().trim();
      return (title == null || title.isEmpty) ? null : title;
    } catch (_) {
      return null;
    }
  }

  /// `customer_collections.phone` is stored in whatever shape it was typed,
  /// so candidates are narrowed by the last digits and then compared on
  /// digits only.
  Future<String?> _collectionProductId(String phone) async {
    if (phone.isEmpty) return null;
    final tail = phone.length > 10 ? phone.substring(phone.length - 10) : phone;
    final rows = await db
        .from(Db.customerCollections)
        .select('phone, product_id')
        .like('phone', '%$tail%') as List<dynamic>;

    for (final row in rows.whereType<Map<String, dynamic>>()) {
      if (Chat.normalisePhone(row['phone']?.toString()) == phone) {
        final id = row['product_id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  Future<String?> _adProductId(String? adHeadline) async {
    final headline = adHeadline?.trim();
    if (headline == null || headline.isEmpty) return null;
    final row = await db
        .from(Db.adProductMap)
        .select('product_id')
        .eq('ad_headline', headline)
        .limit(1)
        .maybeSingle();
    final id = row?['product_id']?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  Future<List<Note>> _notes(String contactId) async {
    try {
      final rows = await db
          .from(Db.contactNotes)
          .select('contact_id, notes(*)')
          .eq('contact_id', contactId) as List<dynamic>;

      final notes = <Note>[];
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final note = row['notes'];
        if (note is! Map<String, dynamic>) continue;
        final parsed = Note.fromMap(note);
        if (!notes.any((existing) => existing.id == parsed.id)) {
          notes.add(parsed);
        }
      }
      notes.sort((a, b) {
        final aAt = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bAt = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bAt.compareTo(aAt);
      });
      return notes;
    } catch (_) {
      return const <Note>[];
    }
  }
}
