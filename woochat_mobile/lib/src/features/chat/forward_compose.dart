import '../../data/attachment_picker.dart';
import '../../data/messages_repository.dart';
import '../../models/message.dart';

/// What a forwarded message becomes once the "Add a message…" text is folded
/// in: the content to store, and the media to hand to WhatsApp.
///
/// On a picture, video or file the note becomes (part of) the caption, so the
/// customer gets ONE message with the text under the media — not a file and
/// then a line of text. On a text message it is appended. Whatever the
/// original already said stays in front of it.
({String content, OutboundMedia? media}) composeForward(
  Message message, {
  String note = '',
}) {
  final attachment = message.attachment;
  final trimmed = note.trim();

  if (attachment == null) {
    final original = (message.content ?? '').trim();
    return (
      content: trimmed.isEmpty ? original : '$original\n\n$trimmed',
      media: null,
    );
  }

  final caption = <String>[
    if (message.body.isNotEmpty) message.body,
    if (trimmed.isNotEmpty) trimmed,
  ].join('\n');

  return (
    content: Message.attachmentMarker(
      type: attachment.type,
      name: attachment.name,
      url: attachment.url,
      caption: caption,
    ),
    media: OutboundMedia(
      url: attachment.url,
      type: attachment.type,
      mimeType: AttachmentPicker.mimeForFileName(
        attachment.name,
        attachment.type,
      ),
      fileName: attachment.name,
      caption: caption,
    ),
  );
}
