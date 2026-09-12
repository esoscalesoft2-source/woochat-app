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
    final path = '$authUserId/$chatId/$fileName';
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
