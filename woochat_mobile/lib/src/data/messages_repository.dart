import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../models/message.dart';
import 'edge_function_auth.dart';
import 'supabase_client.dart';
import 'templates_repository.dart';

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

  /// What the function's `message` field must carry for this media.
  ///
  /// It is the FILE NAME, not the caption — the document branch refuses the
  /// call outright with `Missing filename in 'message' for document`, and
  /// Meta uses it as the name the customer sees on the file. The caption
  /// travels in its own key. This is what the web app sends too.
  String get messageField => fileName;
}

/// Reads, streams and sends rows on the existing `messages` table.
class MessagesRepository {
  const MessagesRepository();

  static const String _selectColumns = '''
id, chat_id, user_id, direction, content, status, template_name,
template_language, template_params, whatsapp_message_id,
reply_to_message_id, reaction, send_error_message, send_error_code,
created_at, scheduled_at
''';

  /// How much of a thread opens live. The web app opens 40 and pages back;
  /// this is more generous because the page-back here is a tap, not a scroll.
  static const int livePageSize = 150;

  /// One page of older messages, ending just before [before] — oldest first.
  Future<List<Message>> fetchMessages(
    String chatId, {
    int limit = livePageSize,
    DateTime? before,
  }) async {
    var query = db
        .from(Db.messages)
        .select(_selectColumns)
        .eq('chat_id', chatId);
    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }
    final rows = await query
        .order('created_at', ascending: false)
        .limit(limit) as List<dynamic>;

    return rows
        .whereType<Map<String, dynamic>>()
        .map(Message.fromMap)
        .toList()
        .reversed
        .toList();
  }

  /// Messages by id, from any chat. A reply may quote something the thread
  /// does not hold — older than the live page, or filed under a duplicate
  /// chat row for the same customer — and the quote must still be drawn.
  Future<List<Message>> fetchByIds(Iterable<String> ids) async {
    final wanted = ids.toSet().toList();
    if (wanted.isEmpty) return const <Message>[];
    final rows = await db
        .from(Db.messages)
        .select(_selectColumns)
        .inFilter('id', wanted) as List<dynamic>;
    return rows.whereType<Map<String, dynamic>>().map(Message.fromMap).toList();
  }

  /// Realtime feed for one chat: the newest [livePageSize] messages, kept
  /// live, oldest first.
  ///
  /// Uncapped, opening a long-running customer thread pulled every row it
  /// had (up to PostgREST's 1000) before anything was drawn. Only the tail
  /// needs to be live; anything older is paged in on demand with
  /// [fetchMessages]. The stream builder re-sorts and re-trims on every
  /// change, so a new message always displaces the oldest, never itself.
  Stream<List<Message>> watchMessages(String chatId) {
    return db
        .from(Db.messages)
        .stream(primaryKey: <String>['id'])
        .eq('chat_id', chatId)
        .order('created_at', ascending: false)
        .limit(livePageSize)
        .map(
          (rows) => rows
              .whereType<Map<String, dynamic>>()
              .map(Message.fromMap)
              .toList()
              .reversed
              .toList(),
        );
  }

  /// Inserts the outbound row, then asks the existing `whatsapp-send` edge
  /// function to deliver it, and returns once WhatsApp has answered.
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
    final message = await insertOutbound(
      chatId: chatId,
      senderUserId: senderUserId,
      content: content,
    );
    await deliver(
      message,
      chatOwnerUserId: chatOwnerUserId,
      contactPhone: contactPhone,
      replyToWhatsAppMessageId: replyToWhatsAppMessageId,
      media: media,
    );
    return message;
  }

  /// Step one of a send: the row, in `sending`. This is the fast part — one
  /// insert — and it is all the composer waits for. The moment it lands the
  /// bubble can show with its clock, the box can clear and the next message
  /// can be typed, while [deliver] does the slow WhatsApp round trip behind
  /// it. That is how WhatsApp itself feels, and how the web app sends.
  Future<Message> insertOutbound({
    required String chatId,
    required String senderUserId,
    required String content,
    String? replyToMessageId,
  }) async {
    final inserted = await db
        .from(Db.messages)
        .insert(<String, dynamic>{
          'chat_id': chatId,
          'user_id': senderUserId,
          'direction': MessageDirection.outbound,
          'content': content,
          'status': MessageStatus.sending,
          // The quote. WhatsApp itself is told through
          // replyToWhatsAppMessageId at delivery; this is what the thread
          // draws.
          'reply_to_message_id': ?replyToMessageId,
        })
        .select(_selectColumns)
        .single();
    return Message.fromMap(inserted);
  }

  /// Queues rows for `scheduled-message-sender` to send at [at].
  ///
  /// Nothing is sent from here — the row is the whole job. pg_cron picks it
  /// up once `scheduled_at` has passed, sends it through Meta, and moves it
  /// to `sent` with a fresh `created_at` (or back into the queue on a
  /// failure). A template row carries its name, language and `{{n}}` values
  /// so the sender can rebuild it; `content` is the rendered body the
  /// bubble shows meanwhile.
  ///
  /// Several free-form rows (a set of staged files) get increasing
  /// `scheduled_at` stamps a millisecond apart, so the sender takes them in
  /// order.
  Future<List<Message>> schedule({
    required String chatId,
    required String senderUserId,
    required DateTime at,
    required List<String> contents,
    String? templateName,
    String? templateLanguage,
    List<String>? templateParams,
  }) async {
    if (contents.isEmpty) return const <Message>[];
    final base = at.toUtc();
    final rows = await db
        .from(Db.messages)
        .insert(<Map<String, dynamic>>[
          for (var i = 0; i < contents.length; i++)
            <String, dynamic>{
              'chat_id': chatId,
              'user_id': senderUserId,
              'direction': MessageDirection.outbound,
              'status': MessageStatus.scheduled,
              'scheduled_at':
                  base.add(Duration(milliseconds: i)).toIso8601String(),
              'content': contents[i],
              'template_name': ?templateName,
              'template_language': ?templateLanguage,
              'template_params': ?templateParams,
            },
        ])
        .select(_selectColumns) as List<dynamic>;
    return rows.whereType<Map<String, dynamic>>().map(Message.fromMap).toList();
  }

  /// Pulls a queued row before the sender gets to it. The status guard is
  /// what keeps this from deleting one that is mid-send: once the sender has
  /// claimed it the status is `sending`, and the delete matches nothing.
  /// Returns whether a row was actually removed.
  Future<bool> cancelScheduled(String messageId) async {
    final rows = await db
        .from(Db.messages)
        .delete()
        .eq('id', messageId)
        .eq('status', MessageStatus.scheduled)
        .select('id') as List<dynamic>;
    return rows.isNotEmpty;
  }

  /// Several rows in one insert, in the order given.
  ///
  /// A batch insert stamps every row with the same `now()`, and the thread
  /// is ordered by `created_at` — so without explicit, increasing stamps a
  /// ten-photo set would land in whatever order Postgres felt like. The web
  /// app assigns them client-side for the same reason.
  Future<List<Message>> insertOutboundMany({
    required String chatId,
    required String senderUserId,
    required List<String> contents,
    String? replyToMessageId,
  }) async {
    if (contents.isEmpty) return const <Message>[];
    final base = DateTime.now().toUtc();
    final rows = await db
        .from(Db.messages)
        .insert(<Map<String, dynamic>>[
          for (var i = 0; i < contents.length; i++)
            <String, dynamic>{
              'chat_id': chatId,
              'user_id': senderUserId,
              'direction': MessageDirection.outbound,
              'content': contents[i],
              'status': MessageStatus.sending,
              'created_at':
                  base.add(Duration(milliseconds: i)).toIso8601String(),
              // Only the first of a set answers the quote.
              if (i == 0 && replyToMessageId != null)
                'reply_to_message_id': replyToMessageId,
            },
        ])
        .select(_selectColumns) as List<dynamic>;
    final inserted =
        rows.whereType<Map<String, dynamic>>().map(Message.fromMap).toList()
          ..sort((a, b) {
            final aAt = a.createdAt?.millisecondsSinceEpoch ?? 0;
            final bAt = b.createdAt?.millisecondsSinceEpoch ?? 0;
            return aAt.compareTo(bAt);
          });
    return inserted;
  }

  /// Step two: hands the stored row to `whatsapp-send`. On success the row
  /// moves to `sent`; on failure it is marked `failed` with the reason and a
  /// [MessageSendException] is thrown carrying the same text.
  Future<void> deliver(
    Message message, {
    required String chatOwnerUserId,
    String? contactPhone,
    String? replyToWhatsAppMessageId,
    OutboundMedia? media,
  }) async {
    final content = message.content ?? '';
    try {
      // Keys match the edge function's handler exactly: `message` (not
      // `content`), `localMessageId` (the row we just inserted) and
      // `chatOwnerUserId`, which it needs to resolve the sending number.
      final response = await invokeEdgeFunction(
        Db.whatsappSendFn,
        body: <String, dynamic>{
          'to': contactPhone,
          // Media travels in its own keys. The `[attachment:…]` marker is how
          // the row is STORED so this app can render it; sending that marker
          // as the message text delivered the raw text to the customer.
          'message': media == null ? content : media.messageField,
          'localMessageId': message.id,
          'chatOwnerUserId': chatOwnerUserId,
          'chatId': message.chatId,
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
    } on EdgeFunctionAuthException catch (error) {
      await _markFailed(message.id, error.message);
      throw MessageSendException(error.message);
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

  /// A template that did not fail this recently counts as already delivered.
  static const Duration templateRepeatWindow = Duration(minutes: 2);

  /// How far back to look for this template's own earlier attempt.
  static const Duration templateReuseWindow = Duration(minutes: 10);

  static const String templateInFlight =
      'This template is already being sent to this customer. Wait for it to finish.';
  static const String templateJustSent =
      'This template already went to this customer a moment ago.';

  /// Sends an approved template — the only thing WhatsApp accepts once the
  /// 24-hour window has closed.
  ///
  /// Mirrors the web app step for step: the rendered body is stored as the
  /// row (with the header media embedded so the bubble shows what the
  /// customer got), the template name / language / values are kept on the
  /// row so Retry can rebuild it, and the same duplicate guard stops a second
  /// press putting the template in front of the customer twice.
  Future<Message> sendTemplateMessage({
    required String chatId,
    required String senderUserId,
    required String chatOwnerUserId,
    required String? contactPhone,
    required MessageTemplate template,
    required Map<int, String> values,
  }) async {
    final numbers = template.parameterNumbers;
    for (final n in numbers) {
      if ((values[n]?.trim() ?? '').isEmpty) {
        throw MessageSendException('Template parameter {{$n}} is required.');
      }
    }
    final paramValues = <String>[for (final n in numbers) values[n]!.trim()];
    final rendered = template.render(values).trim();

    var stored = rendered;
    final headerType = template.headerMediaType;
    final headerUrl = template.headerExampleUrl?.trim() ?? '';
    if (headerType != null && headerUrl.isNotEmpty) {
      final name = headerUrl.split('/').last.split('?').first;
      final line = Message.attachmentMarker(
        type: headerType,
        name: name.isEmpty ? template.name : name,
        url: headerUrl,
      );
      stored = rendered.isEmpty ? line : '$line\n$rendered';
    }

    final plan = await _planTemplateSend(chatId, template.name, stored);
    final String messageId;
    switch (plan) {
      case TemplateSendBlocked(:final reason):
        throw MessageSendException(reason);
      case TemplateSendReuse(:final id):
        messageId = id;
        await db.from(Db.messages).update(<String, dynamic>{
          'status': MessageStatus.sending,
          'send_error_code': null,
          'send_error_message': null,
        }).eq('id', id);
      case TemplateSendInsert():
        final inserted = await db
            .from(Db.messages)
            .insert(<String, dynamic>{
              'chat_id': chatId,
              'user_id': senderUserId,
              'direction': MessageDirection.outbound,
              'content': stored,
              'status': MessageStatus.sending,
              'template_name': template.name,
              'template_language': template.language,
              'template_params': paramValues,
            })
            .select(_selectColumns)
            .single();
        messageId = inserted['id'].toString();
    }

    await _touchChat(chatId, <String, dynamic>{
      'last_message': rendered,
      'last_message_at': DateTime.now().toUtc().toIso8601String(),
    });

    try {
      final response = await invokeEdgeFunction(
        Db.whatsappSendFn,
        body: <String, dynamic>{
          'to': contactPhone,
          'type': 'template',
          'templateName': template.name,
          'templateLanguage': template.language,
          'templateParameters': paramValues,
          'localMessageId': messageId,
          'chatOwnerUserId': chatOwnerUserId,
          'chatId': chatId,
        },
      );

      final data = response.data;
      // A 200 with ok:false is how the function reports a Meta-side rejection.
      final rejected = data is Map && (data['ok'] == false || data['error'] != null);
      if (response.status >= 400 || rejected) {
        throw MessageSendException(
          _reasonFor(data) ?? 'whatsapp-send returned HTTP ${response.status}.',
        );
      }

      await _markSent(messageId, data);
      await _touchChat(chatId, <String, dynamic>{
        'last_message_status': MessageStatus.sent,
        'last_message_direction': MessageDirection.outbound,
      });
    } on EdgeFunctionAuthException catch (error) {
      await _failTemplate(messageId, chatId, error.message);
      throw MessageSendException(error.message);
    } on FunctionException catch (error) {
      final reason = _reasonFor(error.details) ??
          (error.details is Map ? null : error.details?.toString()) ??
          'whatsapp-send rejected the template (${error.reasonPhrase}).';
      await _failTemplate(messageId, chatId, reason);
      throw MessageSendException(reason);
    } catch (error) {
      final reason = error is MessageSendException
          ? error.message
          : 'Template could not be delivered: $error';
      await _failTemplate(messageId, chatId, reason);
      throw MessageSendException(reason);
    }

    final row = await db
        .from(Db.messages)
        .select(_selectColumns)
        .eq('id', messageId)
        .single();
    return Message.fromMap(row);
  }

  /// What a press of Send on this template should do, given what already
  /// went to this chat recently. The rule is the web app's, in one place:
  ///
  ///   • one still `sending` → refuse; a second call would race it
  ///   • one that did NOT fail moments ago → refuse; the customer has it
  ///   • the one that failed, same content → reuse that row
  ///   • otherwise → a new row
  Future<TemplateSendPlan> _planTemplateSend(
    String chatId,
    String templateName,
    String content,
  ) async {
    final since = DateTime.now().toUtc().subtract(templateReuseWindow);
    final rows = await db
        .from(Db.messages)
        .select('id, status, content, created_at')
        .eq('chat_id', chatId)
        .eq('template_name', templateName)
        .gte('created_at', since.toIso8601String())
        .order('created_at', ascending: false)
        .limit(5) as List<dynamic>;
    final recent = rows.whereType<Map<String, dynamic>>().toList();
    return planTemplateSend(recent, content, DateTime.now());
  }

  /// Pure so it can be tested; see [_planTemplateSend].
  static TemplateSendPlan planTemplateSend(
    List<Map<String, dynamic>> recent,
    String content,
    DateTime now,
  ) {
    if (recent.any((r) => r['status'] == MessageStatus.sending)) {
      return const TemplateSendBlocked(templateInFlight);
    }
    for (final r in recent) {
      if (r['status'] == MessageStatus.failed) continue;
      final at = DateTime.tryParse(r['created_at']?.toString() ?? '');
      if (at != null && now.difference(at) < templateRepeatWindow) {
        return const TemplateSendBlocked(templateJustSent);
      }
    }
    for (final r in recent) {
      if (r['status'] == MessageStatus.failed && r['content'] == content) {
        return TemplateSendReuse(r['id'].toString());
      }
    }
    return const TemplateSendInsert();
  }

  Future<void> _failTemplate(
    String messageId,
    String chatId,
    String reason,
  ) async {
    await _markFailed(messageId, reason);
    await _touchChat(chatId, <String, dynamic>{
      'last_message_status': MessageStatus.failed,
      'last_message_direction': MessageDirection.outbound,
    });
  }

  Future<void> _touchChat(String chatId, Map<String, dynamic> values) async {
    try {
      await db.from(Db.chats).update(values).eq('id', chatId);
    } on PostgrestException {
      // The list row catches up from the message realtime event anyway.
    }
  }

  /// Turns the edge function's `reason` code into something readable.
  static String? _reasonFor(Object? data) {
    // A 401 is normally caught and mended by invokeEdgeFunction before it
    // gets here; this is the wording for the one that could not be.
    if (data is String && data.contains('Unauthorized')) {
      return kSessionEndedMessage;
    }
    if (data is! Map) return null;
    if (data['error'] == 'Unauthorized') return kSessionEndedMessage;
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

/// See [MessagesRepository.planTemplateSend].
sealed class TemplateSendPlan {
  const TemplateSendPlan();
}

class TemplateSendBlocked extends TemplateSendPlan {
  const TemplateSendBlocked(this.reason);
  final String reason;
}

class TemplateSendReuse extends TemplateSendPlan {
  const TemplateSendReuse(this.id);
  final String id;
}

class TemplateSendInsert extends TemplateSendPlan {
  const TemplateSendInsert();
}
