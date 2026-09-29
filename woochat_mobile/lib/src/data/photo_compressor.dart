import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'attachment_picker.dart';

/// "Standard quality": a photo shrunk to what a phone screen can show and
/// recompressed before it goes up — WhatsApp's own default. A 4 MB camera
/// shot becomes a few hundred KB and the send stops feeling stuck.
///
/// Only photos are touched. Videos, documents, audio and anything the
/// decoder does not recognise go up as they are, and so does a photo the
/// recompression would not actually make smaller.
class PhotoCompressor {
  const PhotoCompressor._();

  /// Longest side after resizing. WhatsApp uses 1600.
  static const int maxSide = 1600;
  static const int jpegQuality = 80;

  static Future<PickedAttachment> standardQuality(
    PickedAttachment photo,
  ) async {
    if (photo.type != 'image') return photo;
    if (!_recompressible.contains(photo.mimeType.toLowerCase())) return photo;

    // Decoding a camera photo takes real time; off the UI thread on a
    // phone. On the web `compute` just runs it here, which is what the
    // web can do.
    final Uint8List? smaller;
    try {
      smaller = await compute(_shrink, photo.bytes);
    } catch (_) {
      return photo;
    }
    if (smaller == null || smaller.length >= photo.bytes.length) return photo;

    return PickedAttachment(
      bytes: smaller,
      fileName: _asJpeg(photo.fileName),
      mimeType: 'image/jpeg',
      type: photo.type,
    );
  }

  /// A GIF is animated, and a WebP may be; recompressing to JPEG would
  /// freeze either. HEIC the decoder cannot read.
  static const Set<String> _recompressible = <String>{
    'image/jpeg',
    'image/jpg',
    'image/png',
  };

  static String _asJpeg(String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    return '$stem.jpg';
  }
}

/// Runs in an isolate: returns the JPEG, or null when the image could not
/// be read.
Uint8List? _shrink(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  // Photos straight off a camera carry an orientation flag; bake it in so
  // the resized copy is not sideways.
  final upright = img.bakeOrientation(decoded);
  final longest =
      upright.width > upright.height ? upright.width : upright.height;
  final sized = longest > PhotoCompressor.maxSide
      ? (upright.width >= upright.height
          ? img.copyResize(upright, width: PhotoCompressor.maxSide)
          : img.copyResize(upright, height: PhotoCompressor.maxSide))
      : upright;
  return Uint8List.fromList(
    img.encodeJpg(sized, quality: PhotoCompressor.jpegQuality),
  );
}
