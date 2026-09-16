import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';

/// Raised when the user has to act before a picker can work — a permission
/// they denied, or a device with no camera.
class AttachmentPickerException implements Exception {
  const AttachmentPickerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A file chosen from the device, ready to upload and send.
class PickedAttachment {
  const PickedAttachment({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.type,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  /// WhatsApp's own media kind: image, video, audio, document.
  final String type;

  /// The caps the `whatsapp-send` function itself enforces, so a file it
  /// would refuse is caught here instead of after the upload.
  int get limitBytes => switch (type) {
        'image' => 5 * 1024 * 1024,
        'document' => 100 * 1024 * 1024,
        _ => 16 * 1024 * 1024,
      };

  bool get isTooLarge => bytes.length > limitBytes;

  String get limitLabel => '${(limitBytes / (1024 * 1024)).round()}MB';

  /// The formats `whatsapp-send` will actually forward, copied from its own
  /// `isSupportedMediaType`. A document may be anything.
  static const Map<String, List<String>> supportedMimeTypes =
      <String, List<String>>{
    'image': <String>['image/jpeg', 'image/jpg', 'image/png'],
    'audio': <String>[
      'audio/aac',
      'audio/mp4',
      'audio/mpeg',
      'audio/amr',
      'audio/ogg',
    ],
    'video': <String>['video/mp4', 'video/3gpp'],
  };

  /// False when WhatsApp would refuse this file's format outright — a HEIC
  /// photo or a .mov clip, which a browser hands over unconverted.
  bool get isSupportedFormat {
    final allowed = supportedMimeTypes[type];
    if (allowed == null) return true;
    return allowed.any(mimeType.startsWith);
  }
}

/// Opens the right device picker for each attach-menu option.
///
/// Every method returns null when the user backs out, and throws
/// [AttachmentPickerException] only when something needs saying — a denied
/// permission, or a file too large for WhatsApp to accept.
class AttachmentPicker {
  const AttachmentPicker();

  /// True in a browser running on a desktop, where the `capture` attribute
  /// image_picker relies on is ignored — the plugin's own docs say it "is
  /// only supported in mobile browsers", so asking for the camera there just
  /// opens a file chooser. A phone browser honours it, so only desktop is
  /// ruled out.
  static bool get _isDesktopBrowser =>
      kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// The back camera, for a photo. The plugin asks for the camera permission
  /// itself the first time and reports a refusal as an exception.
  Future<PickedAttachment?> takePhoto() async {
    if (_isDesktopBrowser) {
      throw const AttachmentPickerException(
        'A desktop browser cannot open the camera. Run the app on a phone, '
        'or use Photos & Videos to pick an existing picture.',
      );
    }
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        // A full-resolution phone photo goes past the send function's 5MB
        // image cap; this keeps it well under and the upload quick.
        maxWidth: 2048,
        imageQuality: 85,
      );
      return file == null ? null : await _fromXFile(file, 'image');
    } catch (error) {
      throw AttachmentPickerException(_cameraReason(error));
    }
  }

  /// How many photos or videos one send may carry — WhatsApp's own cap on a
  /// gallery pick, and enough for a product set.
  static const int maxMediaPerSend = 15;

  /// The gallery, for up to [maxMediaPerSend] photos and videos at once. An
  /// empty list means the user backed out.
  Future<List<PickedAttachment>> pickPhotosOrVideos() async {
    final List<XFile> files;
    try {
      // imageQuality re-encodes each picked photo as JPEG — iPhone HEIC and
      // gallery WebP are formats the send function refuses. Videos are
      // handed over untouched.
      files = await ImagePicker().pickMultipleMedia(
        limit: maxMediaPerSend,
        maxWidth: 2048,
        imageQuality: 85,
      );
    } catch (error) {
      throw const AttachmentPickerException(
        'Photos could not be opened. Allow photo access for WOO Chat in '
        'Settings, then try again.',
      );
    }
    // The platform picker enforces the limit on Android and iOS; a browser
    // file dialog does not, so it is applied again here.
    return <PickedAttachment>[
      for (final file in files.take(maxMediaPerSend))
        await _fromXFile(
          file,
          _isVideo(file.name, file.mimeType) ? 'video' : 'image',
        ),
    ];
  }

  /// The gallery, for one photo or video.
  Future<PickedAttachment?> pickPhotoOrVideo() async {
    try {
      // imageQuality re-encodes a picked photo as JPEG — iPhone HEIC and
      // gallery WebP are formats the send function refuses. Videos are
      // handed over untouched.
      final file = await ImagePicker().pickMedia(
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (file == null) return null;
      final isVideo = _isVideo(file.name, file.mimeType);
      return await _fromXFile(file, isVideo ? 'video' : 'image');
    } catch (error) {
      throw AttachmentPickerException(
        'Photos could not be opened. Allow photo access for WOO Chat in '
        'Settings, then try again.',
      );
    }
  }

  /// The device's audio files.
  Future<PickedAttachment?> pickAudio() => _pickFile(FileType.audio, 'audio');

  /// The gallery, images only — what a quick reply's "Add images" takes.
  Future<PickedAttachment?> pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // The shortcut image cap is 2MB, so this is squeezed harder than a
        // chat attachment. The web app resizes to 1600px the same way.
        maxWidth: 1600,
        imageQuality: 80,
      );
      return file == null ? null : await _fromXFile(file, 'image');
    } catch (error) {
      throw const AttachmentPickerException(
        'Photos could not be opened. Allow photo access for WOO Chat in '
        'Settings, then try again.',
      );
    }
  }

  /// The gallery, videos only.
  Future<PickedAttachment?> pickVideo() async {
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      return file == null ? null : await _fromXFile(file, 'video');
    } catch (error) {
      throw const AttachmentPickerException(
        'Videos could not be opened. Allow photo access for WOO Chat in '
        'Settings, then try again.',
      );
    }
  }

  /// Any document.
  Future<PickedAttachment?> pickDocument() =>
      _pickFile(FileType.any, 'document');

  Future<PickedAttachment?> _pickFile(FileType type, String kind) async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(type: type);
    } catch (error) {
      throw AttachmentPickerException(
        'Files could not be opened. Allow file access for WOO Chat in '
        'Settings, then try again.',
      );
    }
    if (file == null) return null;

    final Uint8List bytes;
    try {
      // The bytes are what gets uploaded; on Android a content:// path is
      // not readable as a plain file.
      bytes = await file.readAsBytes();
    } catch (error) {
      throw const AttachmentPickerException(
        'That file could not be read. Try copying it to your device first.',
      );
    }

    final name = file.name;
    // What was picked as a document goes as a document — the file card with
    // its name and size — even when it is a JPG or an MP4. That is how
    // WhatsApp's own "Document" works, and it is the way to send a photo
    // uncompressed or a video without it playing inline. Photos & Videos is
    // the option for the media kind.
    return PickedAttachment(
      bytes: bytes,
      fileName: name,
      mimeType: _mimeFor(name, kind),
      type: kind,
    );
  }

  /// One contact from the address book, as a vCard.
  ///
  /// The system's own contact picker is used, so the app never lists anyone's
  /// contacts itself — on iOS that also means the limited-access prompt is
  /// not needed at all.
  Future<PickedContact?> pickContact() async {
    if (kIsWeb) {
      throw const AttachmentPickerException(
        'Sharing a contact needs the phone address book, which a browser '
        'cannot reach. Run the app on a phone to share a contact.',
      );
    }

    final PermissionStatus status;
    try {
      status = await FlutterContacts.permissions.request(PermissionType.read);
    } on MissingPluginException {
      throw const AttachmentPickerException(
        'Contacts are not available on this platform.',
      );
    }
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      throw const AttachmentPickerException(
        'Allow contact access for WOO Chat in Settings to share a contact.',
      );
    }

    final contact = await FlutterContacts.native.showPicker(
      properties: <ContactProperty>{
        ContactProperty.name,
        ContactProperty.phone,
        ContactProperty.email,
      },
    );
    if (contact == null) return null;

    final name = (contact.displayName ?? '').trim();
    return PickedContact(
      displayName: name.isEmpty ? 'Contact' : name,
      phones: <String>[
        for (final phone in contact.phones)
          if (phone.number.trim().isNotEmpty) phone.number.trim(),
      ],
      vCard: FlutterContacts.vCard.export(contact),
    );
  }

  Future<PickedAttachment> _fromXFile(XFile file, String type) async {
    final bytes = await file.readAsBytes();
    final name = file.name.isEmpty
        ? '${DateTime.now().millisecondsSinceEpoch}.${type == 'video' ? 'mp4' : 'jpg'}'
        : file.name;
    return PickedAttachment(
      bytes: bytes,
      fileName: name,
      mimeType: file.mimeType ?? _mimeFor(name, type),
      type: type,
    );
  }

  static String _cameraReason(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('camera_access_denied') || text.contains('permission')) {
      return 'Allow camera access for WOO Chat in Settings, then try again.';
    }
    if (text.contains('no_available_camera') || text.contains('no camera')) {
      return 'This device has no camera available.';
    }
    return 'The camera could not be opened: $error';
  }

  static bool _isVideo(String name, String? mimeType) {
    if (mimeType != null && mimeType.startsWith('video/')) return true;
    return RegExp(r'\.(mp4|mov|avi|mkv|3gp|webm)$', caseSensitive: false)
        .hasMatch(name);
  }

  /// The MIME type a file name implies, falling back on [type]. Public so a
  /// stored URL with no recorded type can be sent correctly too.
  static String mimeForFileName(String name, String type) =>
      _mimeFor(name, type);

  static String _mimeFor(String name, String type) {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      '3gp' => 'video/3gpp',
      'mp3' => 'audio/mpeg',
      'ogg' || 'opus' => 'audio/ogg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'amr' => 'audio/amr',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv' => 'text/csv',
      'txt' => 'text/plain',
      _ => switch (type) {
          'image' => 'image/jpeg',
          'video' => 'video/mp4',
          'audio' => 'audio/mpeg',
          _ => 'application/octet-stream',
        },
    };
  }
}

/// A contact picked from the address book.
class PickedContact {
  const PickedContact({
    required this.displayName,
    required this.phones,
    required this.vCard,
  });

  final String displayName;
  final List<String> phones;

  /// The vCard text WhatsApp turns into a contact card.
  final String vCard;

  /// What the message row stores, so the thread shows something readable
  /// even though WhatsApp receives the card itself.
  String get preview => phones.isEmpty
      ? '👤 $displayName'
      : '👤 $displayName\n${phones.join(', ')}';
}
