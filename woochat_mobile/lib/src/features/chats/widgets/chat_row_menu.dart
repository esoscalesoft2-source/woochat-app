import 'package:flutter/material.dart';

import '../../../models/chat.dart';
import '../../../theme/wa_colors.dart';

/// What the row menu can do — the same set as the web sidebar's ⌄ dropdown.
enum ChatRowAction { archive, pin, unread, labels, categories, notes, products }

/// The long-press menu on a chat row. Mobile has no hover, so the web's
/// hidden ⌄ button becomes a bottom sheet.
///
/// Clearing unread is open to everyone; setting a chat back to unread is
/// gated by [canMarkUnread], which admins always hold and staff only when
/// their admin has delegated it.
Future<ChatRowAction?> showChatRowMenu(
  BuildContext context, {
  required Chat chat,
  required bool canMarkUnread,
}) {
  return showModalBottomSheet<ChatRowAction>(
    context: context,
    backgroundColor: Wa.sheet,
    // Seven rows outgrow the default half-screen sheet on a short phone.
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) =>
        _ChatRowMenu(chat: chat, canMarkUnread: canMarkUnread),
  );
}

class _ChatRowMenu extends StatelessWidget {
  const _ChatRowMenu({required this.chat, required this.canMarkUnread});

  final Chat chat;
  final bool canMarkUnread;

  @override
  Widget build(BuildContext context) {
    final showUnread = chat.isUnread || canMarkUnread;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    chat.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Wa.title,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _Item(
                icon: Icons.archive_outlined,
                label: chat.isArchived ? 'Unarchive' : 'Archive chat',
                action: ChatRowAction.archive,
              ),
              _Item(
                icon: Icons.push_pin_outlined,
                label: chat.isPinned ? 'Unpin' : 'Pin chat',
                action: ChatRowAction.pin,
              ),
              if (showUnread)
                _Item(
                  icon: chat.isUnread
                      ? Icons.drafts_outlined
                      : Icons.mail_outline,
                  label: chat.isUnread ? 'Mark as read' : 'Mark as unread',
                  action: ChatRowAction.unread,
                ),
              const Divider(height: 8, color: Wa.divider),
              const _Item(
                icon: Icons.label_outline,
                label: 'Labels',
                action: ChatRowAction.labels,
              ),
              const _Item(
                icon: Icons.account_tree_outlined,
                label: 'Categories',
                action: ChatRowAction.categories,
              ),
              const _Item(
                icon: Icons.sticky_note_2_outlined,
                label: 'Notes',
                action: ChatRowAction.notes,
              ),
              const _Item(
                icon: Icons.inventory_2_outlined,
                label: 'Products',
                action: ChatRowAction.products,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label, required this.action});

  final IconData icon;
  final String label;
  final ChatRowAction action;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Wa.icon, size: 22),
      title: Text(label, style: const TextStyle(color: Wa.title, fontSize: 15)),
      onTap: () => Navigator.of(context).pop(action),
    );
  }
}
