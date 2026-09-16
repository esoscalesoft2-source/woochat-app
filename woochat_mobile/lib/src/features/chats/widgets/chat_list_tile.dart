import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../models/chat.dart';
import '../../../theme/wa_colors.dart';
import 'contact_avatar.dart';

/// Who the small 👤 line under the name talks about — the web app shows the
/// chat's owner to a super admin and the assigned employee to an admin.
enum OwnerLineKind { owner, assignee, unassigned }

/// The one line of team context on a row, if the role gets one at all.
class OwnerLine {
  const OwnerLine(this.kind, this.text);

  final OwnerLineKind kind;
  final String text;
}

/// One conversation row, laid out exactly like the web sidebar: name and label
/// dots, then the optional owner, ad, product, preview and note lines, with
/// the stamp, pin and unread badge down the right.
///
/// Every line after the name only renders when it has data, so a plain chat
/// stays a compact two-line row.
class ChatListTile extends StatelessWidget {
  const ChatListTile({
    super.key,
    required this.chat,
    required this.subtitleStamp,
    required this.onTap,
    this.onLongPress,
    this.showDivider = true,
    this.photoUrl,
    this.name,
    this.labelColors = const <String>[],
    this.ownerLine,
    this.productName,
    this.noteExcerpt,
    this.selecting = false,
    this.selected = false,
  });

  final Chat chat;
  final String subtitleStamp;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showDivider;

  /// Resolved from the contact directory by the caller.
  final String? photoUrl;

  /// The Contacts-page name; falls back to the chat's own when null.
  final String? name;

  /// Hex colours of the labels on this chat, drawn as dots after the name.
  final List<String> labelColors;

  final OwnerLine? ownerLine;

  /// The 🛍 chip text.
  final String? productName;

  /// The latest note, already cut to length.
  final String? noteExcerpt;

  /// True while the list is in select mode — every row then shows whether it
  /// is in the selection, the way WhatsApp does after a long press.
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final hasUnread = chat.unreadCount > 0 || chat.isUnread;
    final displayName = name?.trim().isNotEmpty ?? false
        ? name!.trim()
        : chat.displayName;
    final thumbnail = chat.lastAdThumbnailUrl?.trim();
    final hasAd = thumbnail != null && thumbnail.isNotEmpty;
    final preview = chatPreview(chat.lastMessage);

    return Material(
      color: selected
          ? Wa.rowSelected
          : hasUnread
              ? Wa.rowUnread
              : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        hoverColor: Wa.rowHover,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _SelectableAvatar(
                  chat: chat,
                  photoUrl: photoUrl,
                  selecting: selecting,
                  selected: selected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(top: 10, bottom: 10, right: 16),
                  decoration: showDivider
                      ? const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Wa.divider, width: 0.5),
                          ),
                        )
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _NameRow(
                              name: displayName,
                              unread: hasUnread,
                              labelColors: labelColors,
                            ),
                            if (ownerLine != null) _OwnerRow(line: ownerLine!),
                            if (hasAd)
                              _AdRow(
                                thumbnailUrl: thumbnail,
                                headline: chat.lastAdHeadline,
                              ),
                            if (productName?.trim().isNotEmpty ?? false)
                              _ProductChip(name: productName!.trim()),
                            const SizedBox(height: 2),
                            _PreviewRow(
                              chat: chat,
                              unread: hasUnread,
                              // No message yet: the number stands in for it.
                              text: preview.isEmpty
                                  ? Chat.displayPhone(chat.contactPhone)
                                  : preview,
                            ),
                            if (noteExcerpt?.isNotEmpty ?? false)
                              _NoteRow(excerpt: noteExcerpt!),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Trailing(
                        stamp: subtitleStamp,
                        unread: hasUnread,
                        unreadCount: chat.unreadCount,
                        pinned: chat.isPinned,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The avatar, with WhatsApp's green tick badge at its corner once the row is
/// selected. In select mode an unselected row shows nothing extra — the tick
/// appearing is the feedback.
class _SelectableAvatar extends StatelessWidget {
  const _SelectableAvatar({
    required this.chat,
    required this.photoUrl,
    required this.selecting,
    required this.selected,
  });

  final Chat chat;
  final String? photoUrl;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final avatar = ContactAvatar(chat: chat, radius: 24.5, photoUrl: photoUrl);
    if (!selecting || !selected) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            key: const ValueKey<String>('selected-tick'),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Wa.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Wa.background, width: 2),
            ),
            child: const Icon(Icons.check, size: 12, color: Wa.onAccent),
          ),
        ),
      ],
    );
  }
}

class _NameRow extends StatelessWidget {
  const _NameRow({
    required this.name,
    required this.unread,
    required this.labelColors,
  });

  final String name;
  final bool unread;
  final List<String> labelColors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: unread ? Wa.title : const Color(0xFFE9EDEF),
              fontSize: 16,
              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        for (final color in labelColors) ...<Widget>[
          const SizedBox(width: 4),
          _LabelDot(color: color),
        ],
      ],
    );
  }
}

class _LabelDot extends StatelessWidget {
  const _LabelDot({required this.color});

  final String color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: parseHexColor(color) ?? Wa.secondaryText,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _OwnerRow extends StatelessWidget {
  const _OwnerRow({required this.line});

  final OwnerLine line;

  @override
  Widget build(BuildContext context) {
    final assigned = line.kind == OwnerLineKind.assignee;
    final color = assigned ? Wa.accent : Wa.mutedText;
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(
        children: <Widget>[
          Icon(Icons.person_outline, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              line.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontStyle: line.kind == OwnerLineKind.unassigned
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdRow extends StatelessWidget {
  const _AdRow({required this.thumbnailUrl, required this.headline});

  final String thumbnailUrl;
  final String? headline;

  @override
  Widget build(BuildContext context) {
    final text = headline?.trim().isNotEmpty ?? false
        ? headline!.trim()
        : 'From ad';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              thumbnailUrl,
              width: 24,
              height: 24,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(width: 24, height: 24),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '📢 $text',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Wa.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductChip extends StatelessWidget {
  const _ProductChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Wa.productChipBackground,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '🛍 $name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Wa.productChip,
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.chat,
    required this.unread,
    required this.text,
  });

  final Chat chat;
  final bool unread;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (chat.lastMessageWasOutbound) ...<Widget>[
          _StatusTick(status: chat.lastMessageStatus),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: unread ? const Color(0xFFE9EDEF) : Wa.secondaryText,
              fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.excerpt});

  final String excerpt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: <Widget>[
          const Icon(Icons.sticky_note_2_outlined, size: 11, color: Wa.note),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              excerpt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Wa.note,
                decoration: TextDecoration.underline,
                decorationColor: Wa.note,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing({
    required this.stamp,
    required this.unread,
    required this.unreadCount,
    required this.pinned,
  });

  final String stamp;
  final bool unread;
  final int unreadCount;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (stamp.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              stamp,
              style: TextStyle(
                fontSize: 12,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                color: unread ? Wa.accent : Wa.secondaryText,
                fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        if (pinned || unread)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (pinned)
                  const Icon(
                    Icons.push_pin,
                    size: 13,
                    color: Wa.secondaryText,
                  ),
                if (pinned && unread) const SizedBox(width: 4),
                if (unread) _UnreadBadge(count: unreadCount),
              ],
            ),
          ),
      ],
    );
  }
}

/// Turns a stored `last_message` into a one-line preview, the way the web
/// app's `formatLastMessage` does: attachments collapse to an emoji label,
/// and long text is cut so the row never wraps.
///
/// Returns '' when there is nothing to show, so the caller can fall back to
/// the phone number.
String chatPreview(String? lastMessage) {
  final raw = lastMessage?.trim();
  if (raw == null || raw.isEmpty) return '';

  if (raw.contains('[attachment:audio')) return '🎤 Audio';
  if (raw.contains('[attachment:image')) return '📷 Photo';
  if (raw.contains('[attachment:video')) return '🎥 Video';
  if (raw.contains('[attachment:sticker')) return '🌟 Sticker';
  if (raw.contains('[attachment:document')) return '📄 Document';

  if (raw.startsWith('📎')) {
    final name = raw.replaceFirst('📎 ', '');
    if (RegExp(r'\.(ogg|mp3|wav|m4a)$', caseSensitive: false).hasMatch(name)) {
      return '🎤 Audio';
    }
    if (RegExp(r'\.(jpg|png|jpeg|gif|webp)$', caseSensitive: false)
        .hasMatch(name)) {
      return '📷 Photo';
    }
    if (RegExp(r'\.(mp4|mov|avi)$', caseSensitive: false).hasMatch(name)) {
      return '🎥 Video';
    }
    return '📄 Document';
  }

  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Longest note excerpt shown on a row before it is cut short.
const int notePreviewMax = 20;

/// One-line excerpt of a note: whitespace collapsed, then cut to
/// [notePreviewMax] characters with an ellipsis only when something was
/// actually removed.
String noteExcerpt(String? text) {
  final clean = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= notePreviewMax) return clean;
  return '${clean.substring(0, notePreviewMax).trimRight()}...';
}

/// `#rgb`, `#rrggbb` or `#rrggbbaa` → Color; null for anything else.
Color? parseHexColor(String value) {
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // `is_unread` can be true with no counter, so show a plain dot then.
    final label = count > 99 ? '99+' : (count > 0 ? '$count' : '');

    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: EdgeInsets.symmetric(horizontal: label.length > 2 ? 5 : 0),
      decoration: const BoxDecoration(
        color: Wa.accent,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: label.isEmpty
          ? null
          : Text(
              label,
              style: const TextStyle(
                color: Wa.onAccent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

/// Delivery indicator for the tenant's own last message.
class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (status) {
      MessageStatus.read => (Icons.done_all, Wa.tickBlue),
      MessageStatus.delivered => (Icons.done_all, Wa.secondaryText),
      MessageStatus.sent => (Icons.done, Wa.secondaryText),
      MessageStatus.failed => (Icons.error_outline, Wa.error),
      _ => (Icons.schedule, Wa.secondaryText),
    };
    return Icon(icon, size: 16, color: color);
  }
}
