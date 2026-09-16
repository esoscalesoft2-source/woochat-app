import 'package:flutter/material.dart';

import '../../../data/shortcuts_repository.dart';
import '../../../theme/wa_colors.dart';

/// The strip above the composer holding a quick reply's files until Send.
///
/// Picking a quick reply puts its message in the box and its media here —
/// nothing leaves until Send is pressed, so the text can still be edited or
/// erased first, and the whole lot can be dropped with the ✕.
class ShortcutMediaTray extends StatelessWidget {
  const ShortcutMediaTray({
    super.key,
    required this.media,
    required this.onClear,
    this.hasCaption = false,
    this.sending = false,
  });

  final List<QuickReplyMedia> media;
  final VoidCallback onClear;

  /// Whether the message box holds text that will go out with the files.
  final bool hasCaption;

  final bool sending;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 6),
      decoration: BoxDecoration(
        color: Thread.composer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Wa.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 6),
              itemCount: media.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _Thumb(item: media[index]),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  <String>[
                    'Shortcut media'
                        '${media.length > 1 ? ' (${media.length})' : ''}',
                    if (hasCaption) 'message sent after',
                    if (sending) 'sending…',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Wa.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                onPressed: sending ? null : onClear,
                tooltip: 'Remove shortcut media',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18, color: Thread.meta),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});

  final QuickReplyMedia item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 48,
              height: 48,
              child: item.type == 'image'
                  ? Image.network(
                      item.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _Placeholder(
                        icon: Icons.broken_image_outlined,
                      ),
                    )
                  : _Placeholder(icon: _iconFor(item.type)),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Thread.meta, fontSize: 9.5),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
        'video' => Icons.videocam,
        'audio' => Icons.music_note,
        _ => Icons.attach_file,
      };
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Thread.input,
        border: Border.all(color: Wa.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 20, color: Wa.accent),
    );
  }
}
