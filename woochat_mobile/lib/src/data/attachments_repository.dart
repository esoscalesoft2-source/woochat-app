import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';

/// Raised when media could not be put into the existing storage bucket.
class AttachmentUploadException implements Exception {
  const AttachmentUploadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Uploads media into the existing `chat-attachments` bucket.
///
/// Nothing here creates a bucket or a policy — it only writes into what the
/// web app already uses.
class AttachmentsRepository {
  const AttachmentsRepository();

  /// Stores [bytes] and returns a URL WhatsApp can fetch.
  ///
  /// The object path starts with the signed-in user's id. Supabase storage
  /// policies are conventionally written against the first folder segment
  /// (`storage.foldername(name)[1] = auth.uid()`), so this shape satisfies
  /// that policy as well as a permissive one; the chat id keeps a
  /// conversation's media together underneath it.
  Future<String> upload({
    required String authUserId,
    required String chatId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final path = '$authUserId/$chatId/${safeObjectName(fileName)}';
    final bucket = db.storage.from(Db.attachmentsBucket);

    try {
      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );
    } on StorageException catch (error) {
      throw AttachmentUploadException(
        'Could not upload to the ${Db.attachmentsBucket} bucket: '
        '${error.message}',
      );
    } catch (error) {
      throw AttachmentUploadException('Could not upload the file: $error');
    }

    // WhatsApp fetches the media itself, so the URL has to be reachable
    // without a session. A private bucket would need a signed URL instead.
    return bucket.getPublicUrl(path);
  }
}

/// A file name Supabase Storage will accept as an object key.
///
/// Storage refuses keys holding anything outside a narrow ASCII set — and a
/// macOS screenshot is called "Screenshot 2026-09-15 at 10.46.59 AM.png"
/// with a narrow no-break space (U+202F) before the AM, which failed every
/// upload with "Invalid key". Everything but letters, digits, `.`, `-` and
/// `_` becomes `_`, runs collapse, and the extension survives — the same
/// rule the web app applies (`replace(/[^\w.-]/g, "_")`).
String safeObjectName(String fileName) {
  final cleaned = fileName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[._-]+'), '');
  return cleaned.isEmpty ? 'file' : cleaned;
}
