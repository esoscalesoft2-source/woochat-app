/// Reference data behind the "More filters" dropdown.
///
/// Every type here maps to an existing table or RPC; nothing new is created.
library;

class Label {
  const Label({required this.id, required this.name, this.color});

  final String id;
  final String name;
  final String? color;

  String get key => name.trim().toLowerCase();

  factory Label.fromMap(Map<String, dynamic> map) => Label(
        id: map['id'].toString(),
        name: (map['name'] as String?)?.trim() ?? '',
        color: map['color'] as String?,
      );
}

/// A row of `chat_labels`.
class ChatLabel {
  const ChatLabel({
    required this.chatId,
    required this.labelId,
    this.createdAt,
  });

  final String chatId;
  final String labelId;
  final DateTime? createdAt;

  factory ChatLabel.fromMap(Map<String, dynamic> map) => ChatLabel(
        chatId: map['chat_id'].toString(),
        labelId: map['label_id'].toString(),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')
            ?.toLocal(),
      );
}

class Category {
  const Category({required this.id, required this.name, this.color});

  final String id;
  final String name;
  final String? color;

  factory Category.fromMap(Map<String, dynamic> map) => Category(
        id: map['id'].toString(),
        name: (map['name'] as String?)?.trim() ?? '',
        color: map['color'] as String?,
      );
}

class Product {
  const Product({required this.id, required this.title});

  final String id;
  final String title;

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'].toString(),
        title: (map['title'] as String?)?.trim() ?? '',
      );
}

class Automation {
  const Automation({required this.id, required this.name});

  final String id;
  final String name;

  factory Automation.fromMap(Map<String, dynamic> map) => Automation(
        id: map['id'].toString(),
        name: (map['name'] as String?)?.trim() ?? '',
      );
}

class Note {
  const Note({
    required this.id,
    this.text,
    this.tags = const <String>[],
    this.createdAt,
  });

  final String id;
  final String? text;
  final List<String> tags;
  final DateTime? createdAt;

  factory Note.fromMap(Map<String, dynamic> map) => Note(
        id: map['id'].toString(),
        text: map['note_text'] as String?,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
        tags: (map['tags'] as List<dynamic>? ?? const <dynamic>[])
            .map((tag) => tag.toString())
            .where((tag) => tag.trim().isNotEmpty)
            .toList(),
      );
}

/// One customer's contact record from the `chat_contact_directory()` RPC,
/// keyed by normalised phone. The short field names are the RPC's own.
class DirectoryEntry {
  const DirectoryEntry({
    required this.id,
    this.name,
    this.photoUrl,
    this.labelIds = const <String>[],
  });

  final String id;
  final String? name;
  final String? photoUrl;

  /// Label ids held on the CONTACT record, e.g. applied by a Contacts import.
  final List<String> labelIds;

  factory DirectoryEntry.fromMap(Map<String, dynamic> map) => DirectoryEntry(
        id: map['id'].toString(),
        name: map['n'] as String?,
        photoUrl: map['p'] as String?,
        labelIds: (map['l'] as List<dynamic>? ?? const <dynamic>[])
            .map((id) => id.toString())
            .toList(),
      );
}

/// Everything the filters need, loaded once and filtered in memory.
class ChatFilterData {
  const ChatFilterData({
    this.labels = const <Label>[],
    this.labelIdsByChat = const <String, List<String>>{},
    this.labelAppliedAt = const <String, DateTime>{},
    this.categories = const <Category>[],
    this.categoryIdsByChat = const <String, List<String>>{},
    this.products = const <Product>[],
    this.collectionProductIdByPhone = const <String, String>{},
    this.productIdByAdHeadline = const <String, String>{},
    this.automations = const <Automation>[],
    this.adSourcedChatIds = const <String>{},
    this.funnelFailed = const <String>{},
    this.funnelReplied = const <String>{},
    this.contactIdByPhone = const <String, String>{},
    this.notesByContactId = const <String, List<Note>>{},
    this.contactLabelIdsByPhone = const <String, List<String>>{},
    this.contactPhotoByPhone = const <String, String>{},
    this.contactNameByPhone = const <String, String>{},
    this.noteTags = const <String>[],
    this.notes = const <Note>[],
  });

  final List<Label> labels;

  /// Chat id -> label ids held on the chat itself (`chat_labels`).
  final Map<String, List<String>> labelIdsByChat;

  /// "chatId:labelId" -> when the label went on, for the date-range exception.
  final Map<String, DateTime> labelAppliedAt;

  final List<Category> categories;
  final Map<String, List<String>> categoryIdsByChat;

  final List<Product> products;
  final Map<String, String> collectionProductIdByPhone;
  final Map<String, String> productIdByAdHeadline;

  final List<Automation> automations;
  final Set<String> adSourcedChatIds;
  final Set<String> funnelFailed;
  final Set<String> funnelReplied;

  final Map<String, String> contactIdByPhone;
  final Map<String, List<Note>> notesByContactId;

  /// Labels held on the CONTACT record, keyed by normalised phone.
  final Map<String, List<String>> contactLabelIdsByPhone;

  /// Profile photos from the contact directory, keyed by normalised phone.
  /// A photo uploaded against the CONTACT wins over the chat row's own
  /// `profile_photo_url`, matching the web app.
  final Map<String, String> contactPhotoByPhone;

  /// The Contacts-page name per phone, e.g. "Fi00008-Loki".
  final Map<String, String> contactNameByPhone;

  final List<String> noteTags;

  /// The whole note library, newest first — what the Notes menu offers to
  /// attach.
  final List<Note> notes;

  /// The photo to show for a chat: the contact record first, then the chat's
  /// own column, then null so the coloured placeholder is used.
  String? photoFor(String normalisedPhone, String? chatPhotoUrl) {
    final fromContact = contactPhotoByPhone[normalisedPhone]?.trim();
    if (fromContact != null && fromContact.isNotEmpty) return fromContact;
    final own = chatPhotoUrl?.trim();
    return (own != null && own.isNotEmpty) ? own : null;
  }

  static const ChatFilterData empty = ChatFilterData();

  ChatFilterData copyWith({
    List<Label>? labels,
    Map<String, List<String>>? labelIdsByChat,
    Map<String, DateTime>? labelAppliedAt,
    List<Category>? categories,
    Map<String, List<String>>? categoryIdsByChat,
    List<Product>? products,
    Map<String, String>? collectionProductIdByPhone,
    Map<String, String>? productIdByAdHeadline,
    List<Automation>? automations,
    Set<String>? adSourcedChatIds,
    Set<String>? funnelFailed,
    Set<String>? funnelReplied,
    Map<String, String>? contactIdByPhone,
    Map<String, List<Note>>? notesByContactId,
    Map<String, List<String>>? contactLabelIdsByPhone,
    Map<String, String>? contactPhotoByPhone,
    Map<String, String>? contactNameByPhone,
    List<String>? noteTags,
    List<Note>? notes,
  }) =>
      ChatFilterData(
        labels: labels ?? this.labels,
        labelIdsByChat: labelIdsByChat ?? this.labelIdsByChat,
        labelAppliedAt: labelAppliedAt ?? this.labelAppliedAt,
        categories: categories ?? this.categories,
        categoryIdsByChat: categoryIdsByChat ?? this.categoryIdsByChat,
        products: products ?? this.products,
        collectionProductIdByPhone:
            collectionProductIdByPhone ?? this.collectionProductIdByPhone,
        productIdByAdHeadline:
            productIdByAdHeadline ?? this.productIdByAdHeadline,
        automations: automations ?? this.automations,
        adSourcedChatIds: adSourcedChatIds ?? this.adSourcedChatIds,
        funnelFailed: funnelFailed ?? this.funnelFailed,
        funnelReplied: funnelReplied ?? this.funnelReplied,
        contactIdByPhone: contactIdByPhone ?? this.contactIdByPhone,
        notesByContactId: notesByContactId ?? this.notesByContactId,
        contactLabelIdsByPhone:
            contactLabelIdsByPhone ?? this.contactLabelIdsByPhone,
        contactPhotoByPhone: contactPhotoByPhone ?? this.contactPhotoByPhone,
        contactNameByPhone: contactNameByPhone ?? this.contactNameByPhone,
        noteTags: noteTags ?? this.noteTags,
        notes: notes ?? this.notes,
      );

  /// Swaps in freshly fetched funnel sets, which are the only part that moves
  /// with the date range.
  ChatFilterData withFunnel({
    required Set<String> failed,
    required Set<String> replied,
  }) =>
      copyWith(funnelFailed: failed, funnelReplied: replied);

  /// The same data with one chat's label or category rows replaced, after a
  /// toggle from the row menu — cheaper than reloading every table.
  ChatFilterData withChatTags({
    required String chatId,
    List<String>? labelIds,
    List<String>? categoryIds,
  }) =>
      copyWith(
        labelIdsByChat: labelIds == null
            ? null
            : <String, List<String>>{...labelIdsByChat, chatId: labelIds},
        categoryIdsByChat: categoryIds == null
            ? null
            : <String, List<String>>{...categoryIdsByChat, chatId: categoryIds},
      );

  /// The hand-picked product on one customer replaced, or cleared with null.
  ChatFilterData withCollectionProduct(
    String normalisedPhone,
    String? productId,
  ) {
    final next = <String, String>{...collectionProductIdByPhone};
    if (productId == null) {
      next.remove(normalisedPhone);
    } else {
      next[normalisedPhone] = productId;
    }
    return copyWith(collectionProductIdByPhone: next);
  }

  /// One contact's attached notes replaced, newest first.
  ChatFilterData withContactNotes(String contactId, List<Note> attached) =>
      copyWith(
        notesByContactId: <String, List<Note>>{
          ...notesByContactId,
          contactId: attached,
        },
      );

  /// A freshly written note put at the top of the library.
  ChatFilterData withNote(Note note) => copyWith(
        notes: <Note>[note, ...notes.where((n) => n.id != note.id)],
      );

  /// The name the row shows: the Contacts-page name so both surfaces read the
  /// same source, falling back to the chat's own name only when the customer
  /// has no contact record.
  String nameFor(String normalisedPhone, String fallback) {
    final fromContact = contactNameByPhone[normalisedPhone]?.trim();
    return (fromContact != null && fromContact.isNotEmpty)
        ? fromContact
        : fallback;
  }

  /// The product the row's 🛍 chip names, or null when there is none.
  String? productNameForChat(String normalisedPhone, String? adHeadline) {
    final id = productIdForChat(normalisedPhone, adHeadline);
    if (id == null) return null;
    for (final product in products) {
      if (product.id == id) return product.title;
    }
    return null;
  }

  /// The newest note on this customer. Lists are kept newest-first.
  Note? latestNoteFor(String normalisedPhone) {
    final contactId = contactIdByPhone[normalisedPhone];
    if (contactId == null) return null;
    final notes = notesByContactId[contactId];
    return (notes == null || notes.isEmpty) ? null : notes.first;
  }

  /// Colours of every label on the chat, for the dots after the name. Labels
  /// the tenant cannot see are skipped rather than drawn colourless.
  List<String> labelColorsForChat(String chatId, String normalisedPhone) {
    final colors = <String>[];
    for (final id in labelIdsForChat(chatId, normalisedPhone)) {
      for (final label in labels) {
        if (label.id == id) {
          final color = label.color?.trim();
          if (color != null && color.isNotEmpty) colors.add(color);
          break;
        }
      }
    }
    return colors;
  }

  /// Labels collapsed to one entry per name — tenant users each own their own
  /// rows, so an admin would otherwise see the same name repeatedly.
  List<Label> get dedupedLabels {
    final seen = <String, Label>{};
    for (final label in labels) {
      seen.putIfAbsent(label.key, () => label);
    }
    final result = seen.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// Every label id sharing [labelId]'s name, so filtering matches across all
  /// of the tenant's label rows rather than silently missing chats.
  List<String> idsSharingNameWith(String labelId) {
    final target = labels
        .where((label) => label.id == labelId)
        .map((label) => label.key)
        .firstOrNull;
    if (target == null || target.isEmpty) return <String>[labelId];
    return labels
        .where((label) => label.key == target)
        .map((label) => label.id)
        .toList();
  }

  /// The union shown by the badges: labels on the chat plus labels on the
  /// customer's contact record.
  List<String> labelIdsForChat(String chatId, String normalisedPhone) {
    final ids = <String>[...?labelIdsByChat[chatId]];
    for (final id in contactLabelIdsByPhone[normalisedPhone] ?? const <String>[]) {
      if (!ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  /// True when any of [labelIds] went on this chat inside [range] — the web
  /// uses `.some()`, so one matching assignment is enough.
  bool labelAppliedInRange(
    String chatId,
    List<String> labelIds,
    DateTimeRangeMs? range,
  ) {
    if (range == null) return true;
    return labelIds.any((id) {
      final at = labelAppliedAt['$chatId:$id'];
      if (at == null) return false;
      final ms = at.millisecondsSinceEpoch;
      return ms >= range.start && ms <= range.end;
    });
  }

  /// The one product a chat belongs to, resolved exactly like the badge: a
  /// hand-picked collection wins over the product inferred from the ad the
  /// chat arrived on. Products the tenant cannot see resolve to null.
  String? productIdForChat(String normalisedPhone, String? adHeadline) {
    final id = collectionProductIdByPhone[normalisedPhone] ??
        (adHeadline == null ? null : productIdByAdHeadline[adHeadline]);
    if (id == null) return null;
    return products.any((product) => product.id == id) ? id : null;
  }
}

/// A date range reduced to epoch milliseconds.
class DateTimeRangeMs {
  const DateTimeRangeMs(this.start, this.end);

  final int start;
  final int end;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
