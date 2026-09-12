import '../core/constants.dart';

/// A row from the existing `messages` table.
class Message {
  const Message({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.direction,
    this.content,
    this.status,
    this.templateName,
    this.whatsappMessageId,
    this.replyToMessageId,
    this.reaction,
    this.sendErrorMessage,
    this.createdAt,
  });

  final String id;
  final String chatId;
  final String? userId;
  final String direction;
  final String? content;
  final String? status;
  final String? templateName;
  final String? whatsappMessageId;
  final String? replyToMessageId;
  final String? reaction;
  final String? sendErrorMessage;
  final DateTime? createdAt;

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      userId: map['user_id'] as String?,
      direction: map['direction'] as String? ?? MessageDirection.inbound,
      content: map['content'] as String?,
      status: map['status'] as String?,
      templateName: map['template_name'] as String?,
      whatsappMessageId: map['whatsapp_message_id'] as String?,
      replyToMessageId: map['reply_to_message_id'] as String?,
      reaction: map['reaction'] as String?,
      sendErrorMessage: map['send_error_message'] as String?,
      createdAt: _parseDate(map['created_at']),
    );
  }

  bool get isOutbound => direction == MessageDirection.outbound;

  /// Media is stored as a marker on the FIRST line of `content`:
  /// `[attachment:TYPE|NAME|URL]`, with name and url percent-encoded. Any
  /// remaining lines are the caption.
  static final RegExp _attachmentPattern =
      RegExp(r'^\[attachment:(\w+)\|([^|]*)\|([^\]]+)\]$');

  MessageAttachment? get attachment {
    final firstLine = (content ?? '').split('\n').firstOrNull;
    if (firstLine == null || !firstLine.startsWith('[attachment:')) return null;

    final match = _attachmentPattern.firstMatch(firstLine);
    if (match == null) return null;

    final url = _decode(match.group(3) ?? '').trim();
    if (url.isEmpty) return null;

    return MessageAttachment(
      type: match.group(1) ?? 'file',
      name: _decode(match.group(2) ?? '').trim().isEmpty
          ? 'file'
          : _decode(match.group(2) ?? '').trim(),
      url: url,
    );
  }

  /// The message text, with the attachment marker line removed.
  String get body {
    final raw = content ?? '';
    if (attachment == null) return raw.trim();
    final lines = raw.split('\n');
    return lines.skip(1).join('\n').trim();
  }

  /// Builds the marker line that [attachment] parses back out, so writing and
  /// reading media stay in step.
  static String attachmentMarker({
    required String type,
    required String name,
    required String url,
    String caption = '',
  }) {
    final marker = '[attachment:$type'
        '|${Uri.encodeComponent(name)}'
        '|${Uri.encodeComponent(url)}]';
    return caption.trim().isEmpty ? marker : '$marker\n${caption.trim()}';
  }

  static String _decode(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  bool get hasFailed => status == MessageStatus.failed;

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}

/// Media carried by a message, parsed from its `[attachment:...]` marker.
class MessageAttachment {
  const MessageAttachment({
    required this.type,
    required this.name,
    required this.url,
  });

  final String type;
  final String name;
  final String url;

  bool get isImage => type == 'image' || type == 'sticker';
  bool get isVideo => type == 'video';
  bool get isAudio => type == 'audio' || type == 'voice';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
