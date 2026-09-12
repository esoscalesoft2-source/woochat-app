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
  const Note({required this.id, this.text, this.tags = const <String>[]});

  final String id;
  final String? text;
  final List<String> tags;

  factory Note.fromMap(Map<String, dynamic> map) => Note(
        id: map['id'].toString(),
        text: map['note_text'] as String?,
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
    this.noteTags = const <String>[],
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

  final List<String> noteTags;

  /// The photo to show for a chat: the contact record first, then the chat's
  /// own column, then null so the coloured placeholder is used.
  String? photoFor(String normalisedPhone, String? chatPhotoUrl) {
    final fromContact = contactPhotoByPhone[normalisedPhone]?.trim();
    if (fromContact != null && fromContact.isNotEmpty) return fromContact;
    final own = chatPhotoUrl?.trim();
    return (own != null && own.isNotEmpty) ? own : null;
  }

  static const ChatFilterData empty = ChatFilterData();

  /// Swaps in freshly fetched funnel sets, which are the only part that moves
  /// with the date range. Copying field-by-field at the call site silently
  /// dropped whatever was added later, so it lives here instead.
  ChatFilterData withFunnel({
    required Set<String> failed,
    required Set<String> replied,
  }) =>
      ChatFilterData(
        labels: labels,
        labelIdsByChat: labelIdsByChat,
        labelAppliedAt: labelAppliedAt,
        categories: categories,
        categoryIdsByChat: categoryIdsByChat,
        products: products,
        collectionProductIdByPhone: collectionProductIdByPhone,
        productIdByAdHeadline: productIdByAdHeadline,
        automations: automations,
        adSourcedChatIds: adSourcedChatIds,
        funnelFailed: failed,
        funnelReplied: replied,
        contactIdByPhone: contactIdByPhone,
        notesByContactId: notesByContactId,
        contactLabelIdsByPhone: contactLabelIdsByPhone,
        contactPhotoByPhone: contactPhotoByPhone,
        noteTags: noteTags,
      );

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
