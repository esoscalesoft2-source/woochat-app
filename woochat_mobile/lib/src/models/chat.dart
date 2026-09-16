import '../core/constants.dart';

/// A row from the existing `chats` table.
class Chat {
  const Chat({
    required this.id,
    required this.userId,
    this.contactName,
    this.contactPhone,
    this.profilePhotoUrl,
    this.isArchived = false,
    this.isPinned = false,
    this.isUnread = false,
    this.unreadCount = 0,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageDirection,
    this.lastMessageStatus,
    this.lastInboundAt,
    this.lastAutomationId,
    this.lastAutomationTriggeredAt,
    this.lastAdHeadline,
    this.lastAdThumbnailUrl,
    this.assignedTo,
  });

  final String id;
  final String userId;
  final String? contactName;
  final String? contactPhone;
  final String? profilePhotoUrl;
  final bool isArchived;
  final bool isPinned;
  final bool isUnread;
  final int unreadCount;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastMessageDirection;
  final String? lastMessageStatus;

  /// When the contact last messaged in — drives the 24-hour WhatsApp window.
  final DateTime? lastInboundAt;

  /// The automation that last touched this chat, for the Auto Reply filter.
  final String? lastAutomationId;
  final DateTime? lastAutomationTriggeredAt;

  /// Headline of the ad the chat arrived on — one of the two ways a chat
  /// resolves to a product.
  final String? lastAdHeadline;

  /// Thumbnail of that ad, shown beside the headline on the list row.
  final String? lastAdThumbnailUrl;

  /// The team member this chat is assigned to, or null when unassigned.
  final String? assignedTo;

  /// Columns this app reads. Explicit so we never over-select.
  static const String selectColumns = '''
id, user_id, contact_name, contact_phone, profile_photo_url,
is_archived, is_pinned, is_unread, unread_count,
last_message, last_message_at, last_message_direction, last_message_status,
last_inbound_at, last_automation_id, last_automation_triggered_at,
last_ad_headline, last_ad_thumbnail_url, assigned_to
''';

  factory Chat.fromMap(Map<String, dynamic> map) {
    return Chat(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      contactName: map['contact_name'] as String?,
      contactPhone: map['contact_phone'] as String?,
      profilePhotoUrl: map['profile_photo_url'] as String?,
      isArchived: map['is_archived'] as bool? ?? false,
      isPinned: map['is_pinned'] as bool? ?? false,
      isUnread: map['is_unread'] as bool? ?? false,
      unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
      lastMessage: map['last_message'] as String?,
      lastMessageAt: _parseDate(map['last_message_at']),
      lastMessageDirection: map['last_message_direction'] as String?,
      lastMessageStatus: map['last_message_status'] as String?,
      lastInboundAt: _parseDate(map['last_inbound_at']),
      lastAutomationId: map['last_automation_id'] as String?,
      lastAutomationTriggeredAt:
          _parseDate(map['last_automation_triggered_at']),
      lastAdHeadline: map['last_ad_headline'] as String?,
      lastAdThumbnailUrl: map['last_ad_thumbnail_url'] as String?,
      assignedTo: map['assigned_to'] as String?,
    );
  }

  /// Used to carry the contact directory's photo into the thread, so the
  /// header shows the same picture the list does.
  Chat withPhoto(String? url) => Chat(
        id: id,
        userId: userId,
        contactName: contactName,
        contactPhone: contactPhone,
        profilePhotoUrl: url ?? profilePhotoUrl,
        isArchived: isArchived,
        isPinned: isPinned,
        isUnread: isUnread,
        unreadCount: unreadCount,
        lastMessage: lastMessage,
        lastMessageAt: lastMessageAt,
        lastMessageDirection: lastMessageDirection,
        lastMessageStatus: lastMessageStatus,
        lastInboundAt: lastInboundAt,
        lastAutomationId: lastAutomationId,
        lastAutomationTriggeredAt: lastAutomationTriggeredAt,
        lastAdHeadline: lastAdHeadline,
        lastAdThumbnailUrl: lastAdThumbnailUrl,
        assignedTo: assignedTo,
      );

  /// Falls back to the phone number when the contact has no saved name.
  String get displayName {
    final name = contactName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final phone = displayPhone(contactPhone);
    if (phone.isNotEmpty) return phone;
    return 'Unknown contact';
  }

  /// The number as every screen shows it — see [displayPhone].
  String get shownPhone => displayPhone(contactPhone);

  String get initials {
    final source = displayName.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  bool get lastMessageWasOutbound =>
      lastMessageDirection == MessageDirection.outbound;

  /// WhatsApp only allows free-form replies within 24 hours of the contact's
  /// last inbound message; outside it, only approved templates may be sent.
  /// A brand new chat has no inbound message, so the window starts closed.
  bool get isCustomerWindowOpen {
    final inbound = lastInboundAt;
    if (inbound == null) return false;
    return DateTime.now().difference(inbound) < const Duration(hours: 24);
  }

  /// Digits only, so '+91 98765 43210' and '919876543210' compare equal.
  static String normalisePhone(String? value) =>
      (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  String get normalisedPhone => normalisePhone(contactPhone);

  /// The number in one fixed shape, so rows for the same customer compare
  /// equal however the number was typed: `6381318192` and `916381318192`
  /// are one person. A bare ten-digit number is taken to be Indian, which
  /// is what every number in this workspace is.
  String get canonicalPhone {
    final digits = normalisedPhone;
    return digits.length == 10 ? '91$digits' : digits;
  }

  /// The number as the list shows it: India's `91` prefix dropped when the
  /// digits are certainly an Indian mobile, anything else left as stored —
  /// the same rule as the web app's `displayPhone`.
  static String displayPhone(String? raw) {
    final original = (raw ?? '').trim();
    if (original.isEmpty) return '';
    final digits = normalisePhone(original);
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    return original;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}
