import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../models/chat.dart';
import '../../../theme/wa_colors.dart';
import 'contact_avatar.dart';

/// One 72px conversation row: avatar, name, delivery tick, preview and unread
/// badge, matching the chats mockup.
class ChatListTile extends StatelessWidget {
  const ChatListTile({
    super.key,
    required this.chat,
    required this.subtitleStamp,
    required this.onTap,
    this.showDivider = true,
    this.photoUrl,
  });

  final Chat chat;
  final String subtitleStamp;
  final VoidCallback onTap;
  final bool showDivider;

  /// Resolved from the contact directory by the caller.
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasUnread = chat.unreadCount > 0 || chat.isUnread;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Wa.rowHover,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                ContactAvatar(chat: chat, radius: 24.5, photoUrl: photoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: showDivider
                        ? const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Wa.divider, width: 0.5),
                            ),
                          )
                        : null,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                chat.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (chat.isPinned) ...<Widget>[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.push_pin,
                                size: 13,
                                color: Wa.secondaryText,
                              ),
                            ],
                            const SizedBox(width: 8),
                            Text(
                              subtitleStamp,
                              style: TextStyle(
                                fontSize: 12,
                                fontFeatures: const <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                                color: hasUnread ? Wa.accent : Wa.secondaryText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: <Widget>[
                            if (chat.lastMessageWasOutbound) ...<Widget>[
                              _StatusTick(status: chat.lastMessageStatus),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                chatPreview(chat.lastMessage),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Wa.secondaryText,
                                ),
                              ),
                            ),
                            if (hasUnread) ...<Widget>[
                              const SizedBox(width: 8),
                              _UnreadBadge(count: chat.unreadCount),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Turns a stored `last_message` into a one-line preview.
///
/// The backend stores attachments as `[attachment:image|<url>]`, which is
/// unreadable in a list, so it collapses to a short label.
String chatPreview(String? lastMessage) {
  final raw = lastMessage?.trim();
  if (raw == null || raw.isEmpty) return 'No messages yet';

  final labelled = raw.replaceAllMapped(
    RegExp(r'\[attachment:([a-zA-Z]+)\|[^\]]*\]'),
    (match) => '[${match.group(1)}]',
  );
  return labelled.replaceAll(RegExp(r'\s+'), ' ').trim();
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
