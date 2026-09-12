import 'package:flutter/material.dart';

import '../../../theme/wa_colors.dart';

/// The options behind the composer's `+` button.
enum AttachOption {
  template('Template Message', Icons.description, Color(0xFF1FA855)),
  // Amber is WhatsApp's own colour for quick replies
  // (`--attachment-type-quick-replies-color`).
  quickReply('Quick Replies', Icons.bolt, Color(0xFFFFBC38)),
  document('Document', Icons.insert_drive_file, Color(0xFF7B61FF)),
  photos('Photos & Videos', Icons.image, Color(0xFF2196F3)),
  audio('Audio', Icons.music_note, Color(0xFFEF4444)),
  camera('Camera', Icons.photo_camera, Color(0xFFEC4899)),
  contact('Contact', Icons.person, Color(0xFF14B8A6));

  const AttachOption(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

/// The `+` button and its popup, styled like the web app's attach menu:
/// a coloured circular icon beside each label.
class AttachButton extends StatelessWidget {
  const AttachButton({
    super.key,
    required this.onSelected,
    this.rowHeight = 46,
  });

  final ValueChanged<AttachOption> onSelected;

  /// The bar's single-line height. The button is boxed and centred in it so
  /// it sits level with the field and the other icons.
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowHeight,
      child: Center(
        child: _menu(),
      ),
    );
  }

  Widget _menu() {
    return PopupMenuButton<AttachOption>(
      tooltip: 'Attach',
      icon: const Icon(Icons.add, size: 22),
      color: Wa.menu,
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      // The same 38px box as _BarIcon; it used to be 34, which left the +
      // sitting visibly higher than the emoji beside it.
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      onSelected: onSelected,
      itemBuilder: (context) => <PopupMenuEntry<AttachOption>>[
        for (final option in AttachOption.values)
          PopupMenuItem<AttachOption>(
            value: option,
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: option.color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(option.icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    option.label,
                    style: const TextStyle(
                      color: Thread.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
