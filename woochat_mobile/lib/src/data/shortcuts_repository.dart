import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';

/// One file attached to a quick reply.
class QuickReplyMedia {
  const QuickReplyMedia({
    required this.url,
    required this.type,
    required this.name,
  });

  final String url;

  /// image, video, audio or document — the same four the web app stores.
  final String type;
  final String name;

  static const Set<String> types = <String>{
    'image',
    'video',
    'audio',
    'document',
  };

  static QuickReplyMedia? fromMap(Object? value) {
    if (value is! Map) return null;
    final url = value['url']?.toString().trim() ?? '';
    final type = value['type']?.toString() ?? '';
    if (url.isEmpty || !types.contains(type)) return null;
    final name = value['name']?.toString().trim() ?? '';
    return QuickReplyMedia(
      url: url,
      type: type,
      name: name.isEmpty ? _nameFromUrl(url) : name,
    );
  }

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'url': url, 'type': type, 'name': name};

  static String _nameFromUrl(String url) {
    final raw = url.split('/').last.split('?').first;
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }
}

/// One saved reply from the existing `shortcuts` table.
class QuickReply {
  const QuickReply({
    required this.id,
    required this.title,
    required this.message,
    this.media = const <QuickReplyMedia>[],
    this.userId,
  });

  final String id;

  /// Who saved it. Null when the column was not selected.
  final String? userId;

  /// A reply may be edited by whoever saved it, and by any admin — the same
  /// rule the web Shortcuts page applies.
  bool canBeManagedBy({required String authUserId, required bool isAdmin}) =>
      isAdmin || userId == null || userId == authUserId;

  /// The trigger word, stored without a slash even when typed with one.
  final String title;

  /// May be empty when the reply is media only.
  final String message;

  final List<QuickReplyMedia> media;

  bool get hasMedia => media.isNotEmpty;

  /// `📎 7 media` — how the web list labels a reply's attachments.
  String get mediaLabel =>
      media.isEmpty ? '' : '\u{1F4CE} ${media.length} media';

  /// What the list row shows under the shortcut name: its text, or the media
  /// count when it carries files instead.
  String get preview => message.isNotEmpty
      ? message
      : media.isEmpty
          ? ''
          : '$mediaLabel (media only)';

  factory QuickReply.fromMap(Map<String, dynamic> map) {
    final title = (map['title'] as String? ?? '').trim();
    return QuickReply(
      id: map['id'].toString(),
      // Rows are saved either way round; the slash belongs to the UI.
      title: title.startsWith('/') ? title.substring(1) : title,
      message: (map['message'] as String? ?? '').trim(),
      media: _mediaFrom(map),
      userId: map['user_id']?.toString(),
    );
  }

  /// `media_urls` is the current shape; a row written before it existed
  /// carries a single `media_url` + `media_type` instead, which the web app
  /// still falls back to.
  static List<QuickReplyMedia> _mediaFrom(Map<String, dynamic> map) {
    final raw = map['media_urls'];
    if (raw is List && raw.isNotEmpty) {
      final items = <QuickReplyMedia>[
        for (final entry in raw) ?QuickReplyMedia.fromMap(entry),
      ];
      if (items.isNotEmpty) return items;
    }

    final url = map['media_url']?.toString().trim() ?? '';
    final type = map['media_type']?.toString() ?? '';
    if (url.isEmpty || !QuickReplyMedia.types.contains(type)) {
      return const <QuickReplyMedia>[];
    }
    return <QuickReplyMedia>[
      QuickReplyMedia(
        url: url,
        type: type,
        name: QuickReplyMedia._nameFromUrl(url),
      ),
    ];
  }
}

/// Raised when a quick reply could not be saved.
class ShortcutException implements Exception {
  const ShortcutException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads and writes the saved replies behind the composer's `/` menu.
class ShortcutsRepository {
  const ShortcutsRepository();

  /// Columns a quick reply is read from, including its media.
  static const String _columns =
      'id, user_id, title, message, media_urls, media_url, media_type';

  /// Saves a new quick reply for [userId]. The title is stored without its
  /// slash — the slash belongs to the UI.
  ///
  /// [media] is written to `media_urls`, with the first item mirrored into
  /// the older `media_url` / `media_type` columns so a client reading only
  /// those still sees something — exactly what the web app writes.
  Future<QuickReply> create({
    required String userId,
    required String title,
    required String message,
    List<QuickReplyMedia> media = const <QuickReplyMedia>[],
  }) async {
    final cleanTitle = title.trim().replaceFirst(RegExp(r'^/+'), '');
    final cleanMessage = message.trim();
    final first = media.isEmpty ? null : media.first;

    try {
      final row = await db
          .from(Db.shortcuts)
          .insert(<String, dynamic>{
            'user_id': userId,
            'title': cleanTitle,
            // The column is nullable, and a media-only reply has no text.
            'message': cleanMessage.isEmpty ? null : cleanMessage,
            'media_urls': <Map<String, dynamic>>[
              for (final item in media) item.toMap(),
            ],
            'media_url': first?.url,
            'media_type': first?.type,
          })
          .select(_columns)
          .single();
      return QuickReply.fromMap(row);
    } on PostgrestException catch (error) {
      throw ShortcutException(
        'Could not save the quick reply: ${error.message}',
      );
    }
  }

  /// Rewrites an existing quick reply. Same columns as [create], so the two
  /// stay in step.
  Future<QuickReply> update({
    required String id,
    required String title,
    required String message,
    List<QuickReplyMedia> media = const <QuickReplyMedia>[],
  }) async {
    final cleanTitle = title.trim().replaceFirst(RegExp(r'^/+'), '');
    final cleanMessage = message.trim();
    final first = media.isEmpty ? null : media.first;

    try {
      final row = await db
          .from(Db.shortcuts)
          .update(<String, dynamic>{
            'title': cleanTitle,
            'message': cleanMessage.isEmpty ? null : cleanMessage,
            'media_urls': <Map<String, dynamic>>[
              for (final item in media) item.toMap(),
            ],
            'media_url': first?.url,
            'media_type': first?.type,
          })
          .eq('id', id)
          .select(_columns)
          .single();
      return QuickReply.fromMap(row);
    } on PostgrestException catch (error) {
      throw ShortcutException(
        'Could not update the quick reply: ${error.message}',
      );
    }
  }

  /// Removes a quick reply. The stored media is left in the bucket — another
  /// reply may point at the same file, and storage is not this app's to
  /// prune.
  Future<void> delete(String id) async {
    try {
      await db.from(Db.shortcuts).delete().eq('id', id);
    } on PostgrestException catch (error) {
      throw ShortcutException(
        'Could not delete the quick reply: ${error.message}',
      );
    }
  }

  /// The workspace owner's shortcuts plus the signed-in user's own.
  ///
  /// Both ids are asked for explicitly rather than relying on RLS alone, so a
  /// team member sees the shared set as well as anything they saved.
  Future<List<QuickReply>> fetchAll({
    required String tenantAdminId,
    required String authUserId,
  }) async {
    final owners = <String>{tenantAdminId, authUserId}.toList();

    try {
      final rows = await db
          .from(Db.shortcuts)
          .select(_columns)
          .inFilter('user_id', owners)
          .order('title', ascending: true) as List;

      return rows
          .whereType<Map<String, dynamic>>()
          .map(QuickReply.fromMap)
          // A reply with neither text nor media has nothing to insert.
          .where((reply) =>
              reply.title.isNotEmpty &&
              (reply.message.isNotEmpty || reply.media.isNotEmpty))
          .toList();
    } on PostgrestException {
      // The composer falls back to plain typing rather than blocking on this.
      return const <QuickReply>[];
    }
  }
}
