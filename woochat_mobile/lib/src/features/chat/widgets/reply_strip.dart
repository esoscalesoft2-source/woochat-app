import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../theme/wa_colors.dart';

/// The quote that sits above the message box while replying — WhatsApp's
/// green-barred preview with the author, a line of the message (or "Photo",
/// "Audio"…), a thumbnail for a picture, and ✕ to drop it.
class ReplyStrip extends StatelessWidget {
  const ReplyStrip({
    super.key,
    required this.message,
    required this.authorName,
    required this.onCancel,
    this.warning,
  });

  final Message message;
  final String authorName;
  final VoidCallback onCancel;

  /// Why the customer will not see this quote, when they will not.
  final String? warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('reply-strip'),
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.fromLTRB(0, 6, 4, 6),
      decoration: BoxDecoration(
        color: Thread.composer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _quoteRow(),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 12, 2),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.info_outline, size: 14, color: Wa.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      warning!,
                      key: const ValueKey<String>('reply-warning'),
                      style: const TextStyle(color: Wa.warning, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _quoteRow() {
    final attachment = message.attachment;
    final (IconData? icon, String text) = attachment == null
        ? (null, message.body)
        : switch (attachment.type) {
            'image' || 'sticker' => (Icons.image_outlined, 'Photo'),
            'video' => (Icons.videocam_outlined, 'Video'),
            'audio' => (Icons.mic_none, 'Audio'),
            _ => (Icons.insert_drive_file_outlined, attachment.name),
          };
    // A captioned photo quotes the caption, the way WhatsApp does.
    final line = attachment != null && message.body.isNotEmpty
        ? message.body
        : text;

    return Row(
      children: <Widget>[
        Container(
          width: 4,
          height: 44,
          margin: const EdgeInsets.only(left: 8, right: 10),
          decoration: BoxDecoration(
            color: Wa.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Wa.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 15, color: Thread.meta),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Thread.meta,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (attachment != null && attachment.isImage) ...<Widget>[
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              attachment.url,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(width: 44, height: 44),
            ),
          ),
        ],
        IconButton(
          onPressed: onCancel,
          tooltip: 'Cancel reply',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 20, color: Thread.meta),
        ),
      ],
    );
  }
}
