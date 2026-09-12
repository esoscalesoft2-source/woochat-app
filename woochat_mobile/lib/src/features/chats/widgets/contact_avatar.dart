import 'package:flutter/material.dart';

import '../../../models/chat.dart';

/// Contact photo, or a deterministic coloured circle with a person icon.
///
/// The colour is derived from the contact's phone number so the same customer
/// always gets the same colour and the list stays visually stable — the same
/// hash and palette the web app uses, so both surfaces match.
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.chat,
    this.radius = 26,
    this.photoUrl,
  });

  final Chat chat;
  final double radius;

  /// Overrides the chat's own column — a photo uploaded against the contact
  /// record wins, which is where most photos actually live.
  final String? photoUrl;

  /// WhatsApp-style default avatar palette.
  static const List<Color> palette = <Color>[
    Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8),
    Color(0xFF9575CD), Color(0xFF7986CB), Color(0xFF64B5F6),
    Color(0xFF4FC3F7), Color(0xFF4DB6AC), Color(0xFF81C784),
    Color(0xFFFF8A65), Color(0xFFA1887F), Color(0xFF90A4AE),
    Color(0xFFF59E0B), Color(0xFF26A69A), Color(0xFF5C6BC0),
  ];

  /// `hash = hash * 31 + charCode`, kept to 32 unsigned bits so it matches the
  /// web app's `>>> 0` exactly.
  static Color colorFor({String? phone, String? name}) {
    final key = (phone?.isNotEmpty ?? false)
        ? phone!
        : (name?.isNotEmpty ?? false)
            ? name!
            : '?';

    var hash = 0;
    for (final code in key.codeUnits) {
      hash = (hash * 31 + code) & 0xFFFFFFFF;
    }
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final resolved = (photoUrl?.trim().isNotEmpty ?? false)
        ? photoUrl!.trim()
        : chat.profilePhotoUrl?.trim();
    final hasPhoto = resolved != null && resolved.isNotEmpty;
    final background = colorFor(
      phone: chat.contactPhone,
      name: chat.displayName,
    );

    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      foregroundImage: hasPhoto ? NetworkImage(resolved) : null,
      // Shown while the photo loads and if it fails to load.
      child: Icon(
        Icons.person,
        size: radius * 1.15,
        color: Colors.white.withValues(alpha: 0.92),
      ),
    );
  }
}
