import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../models/message.dart';
import 'supabase_client.dart';

/// Raised when the outbound message row was written but WhatsApp delivery
/// could not be triggered.
class MessageSendException implements Exception {
  const MessageSendException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Media attached to an outbound message.
///
/// The `whatsapp-send` edge function does NOT read the `[attachment:…]`
/// marker out of the message text — a voice note sent that way arrived at the
/// customer as the literal marker string. So media is passed in its own keys
/// and the marker is kept for the stored row only.
///
/// The key names here are the conventional ones for such a handler and still
/// need confirming against the edge function; [payload] is the single place
/// to change them.
class OutboundMedia {
  const OutboundMedia({
    required this.url,
    required this.type,
    required this.mimeType,
    required this.fileName,
    this.caption = '',
  });

  final String url;

  /// WhatsApp's own media kind: image, video, audio, document.
  final String type;
  final String mimeType;
  final String fileName;

  /// Text sent alongside the media, empty for a bare voice note.
  final String caption;

  Map<String, dynamic> get payload => <String, dynamic>{
        // The function branches on the message kind and defaults it to text:
        // without this it answered `Missing 'message' for text` and never
        // looked at the URL. `mediaType` rides along because only one of the
        // two names is the real one and the call cannot be probed without a
        // signed-in token — drop whichever turns out to be ignored.
        'type': type,
        'mediaType': type,
        'mediaUrl': url,
        'mimeType': mimeType,
        'fileName': fileName,
        if (caption.isNotEmpty) 'caption': caption,
      };
}

/// Reads, streams and sends rows on the existing `messages` table.
class MessagesRepository {
  const MessagesRepository();

  static const String _selectColumns = '''
id, chat_id, user_id, direction, content, status, template_name,
whatsapp_message_id, reply_to_message_id, reaction, send_error_message,
created_at
''';

  Future<List<Message>> fetchMessages(String chatId, {int limit = 200}) async {
    final rows = await db
        .from(Db.messages)
        .select(_selectColumns)
        .eq('chat_id', chatId)
        .order('created_at', ascending: false)
        .limit(limit) as List<dynamic>;

    return rows
        .whereType<Map<String, dynamic>>()
        .map(Message.fromMap)
        .toList()
        .reversed
        .toList();
  }

  /// Realtime feed for one chat, oldest first.
  ///
  /// `ascending` must be passed: postgrest defaults `order()` to DESCENDING,
  /// which returned the thread newest-first and stood it on its head.
  Stream<List<Message>> watchMessages(String chatId) {
    return db
        .from(Db.messages)
        .stream(primaryKey: <String>['id'])
        .eq('chat_id', chatId)
        .order('created_at', ascending: true)
        .map(
          (rows) =>
              rows.whereType<Map<String, dynamic>>().map(Message.fromMap).toList(),
        );
  }

  /// Inserts the outbound row, then asks the existing `whatsapp-send` edge
  /// function to deliver it.
  ///
  /// If the edge function call fails, the row is marked `failed` so the UI can
  /// show it rather than silently losing the message.
  Future<Message> sendTextMessage({
    required String chatId,
    required String senderUserId,
    required String chatOwnerUserId,
    required String content,
    String? contactPhone,
    String? replyToWhatsAppMessageId,
    OutboundMedia? media,
  }) async {
    final inserted = await db
        .from(Db.messages)
        .insert(<String, dynamic>{
          'chat_id': chatId,
          'user_id': senderUserId,
          'direction': MessageDirection.outbound,
          'content': content,
          'status': MessageStatus.sending,
        })
        .select(_selectColumns)
        .single();

    final message = Message.fromMap(inserted);

    try {
      // Keys match the edge function's handler exactly: `message` (not
      // `content`), `localMessageId` (the row we just inserted) and
      // `chatOwnerUserId`, which it needs to resolve the sending number.
      final response = await db.functions.invoke(
        Db.whatsappSendFn,
        body: <String, dynamic>{
          'to': contactPhone,
          // Media travels in its own keys. The `[attachment:…]` marker is how
          // the row is STORED so this app can render it; sending that marker
          // as the message text delivered the raw text to the customer.
          'message': media == null ? content : media.caption,
          'localMessageId': message.id,
          'chatOwnerUserId': chatOwnerUserId,
          'chatId': chatId,
          'replyToWhatsAppMessageId': ?replyToWhatsAppMessageId,
          if (media != null) ...media.payload,
        },
      );

      if (response.status >= 400) {
        throw MessageSendException(
          _reasonFor(response.data) ??
              'whatsapp-send returned HTTP ${response.status}.',
        );
      }

      await _markSent(message.id, response.data);
      return message;
    } on FunctionException catch (error) {
      // invoke() throws on a non-2xx rather than returning it, and the raw
      // exception reads as `FunctionsHttpException(status: 400, details: …)`
      // in the bubble. The function's own message is inside `details`.
      final reason = _reasonFor(error.details) ??
          (error.details is Map ? null : error.details?.toString());
      await _markFailed(message.id, reason ?? error.toString());
      throw MessageSendException(
        reason ?? 'whatsapp-send rejected the message (${error.reasonPhrase}).',
      );
    } catch (error) {
      await _markFailed(message.id, error.toString());
      throw MessageSendException(
        error is MessageSendException
            ? error.message
            : 'Message could not be delivered: $error',
      );
    }
  }

  /// Turns the edge function's `reason` code into something readable.
  static String? _reasonFor(Object? data) {
    if (data is! Map) return null;
    return switch (data['reason']) {
      'OUTSIDE_24H_WINDOW' =>
        'The 24-hour window has closed. Send an approved template instead.',
      'INVALID_RECIPIENT' => 'This number is not on WhatsApp.',
      'AUTH_ERROR' =>
        'WhatsApp connection or token problem. Reconnect it in Settings.',
      'MEDIA_ERROR' ||
      'MEDIA_URL_UNREACHABLE' ||
      'UNSUPPORTED_MEDIA_FORMAT' ||
      'MEDIA_TOO_LARGE' =>
        'WhatsApp would not accept that file. Try a different one.',
      'RATE_LIMITED' => 'Sending too fast. Wait a few seconds and retry.',
      'BILLING_NOT_CONFIGURED' =>
        (data['meta_message'] as String?) ??
            'WhatsApp billing setup is pending in Meta.',
      _ => data['error'] as String?,
    };
  }

  /// Mirrors the web app: on success the row is moved to `sent` and stamped
  /// with Meta's message id, which later delivery receipts key off.
  Future<void> _markSent(String messageId, Object? data) async {
    final metaId = data is Map ? data['meta_message_id'] : null;
    try {
      await db.from(Db.messages).update(<String, dynamic>{
        'status': MessageStatus.sent,
        'send_error_code': null,
        'send_error_message': null,
        if (metaId is String && metaId.trim().isNotEmpty)
          'whatsapp_message_id': metaId,
      }).eq('id', messageId);
    } on PostgrestException {
      // The webhook also stamps this; a failure here is not fatal.
    }
  }

  Future<void> _markFailed(String messageId, String reason) async {
    try {
      await db.from(Db.messages).update(<String, dynamic>{
        'status': MessageStatus.failed,
        'send_error_message': reason,
      }).eq('id', messageId);
    } on PostgrestException {
      // Best effort — the thrown MessageSendException already surfaces to UI.
    }
  }
}
