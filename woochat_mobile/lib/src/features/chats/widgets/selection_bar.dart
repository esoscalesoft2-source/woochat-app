import 'package:flutter/material.dart';

import '../../../theme/wa_colors.dart';

/// What the selection bar can do to the picked chats.
enum SelectionAction { pin, archive, read, assign, more }

/// The bar that replaces the header after a long press, the way WhatsApp's
/// does: ✕ to leave, how many are picked, then the bulk actions. [more]
/// is offered only for a single chat, where it opens that row's own menu.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.total,
    required this.allPinned,
    required this.allArchived,
    required this.anyUnread,
    required this.onExit,
    required this.onSelectAll,
    required this.onAction,
    this.busy = false,
  });

  /// How many are picked, and how many the list is showing — Select all
  /// picks what is on screen, not the whole table.
  final int count;
  final int total;

  /// Whether every picked chat is pinned / archived, and whether any is
  /// unread — each button flips to the opposite of the current state.
  final bool allPinned;
  final bool allArchived;
  final bool anyUnread;

  final VoidCallback onExit;
  final VoidCallback onSelectAll;
  final ValueChanged<SelectionAction> onAction;

  /// True while a bulk write is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final allSelected = total > 0 && count >= total;
    final act = busy || count == 0 ? null : onAction;

    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.only(left: 4, right: 4),
        decoration: const BoxDecoration(
          color: Wa.header,
          border: Border(bottom: BorderSide(color: Wa.divider, width: 0.5)),
        ),
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: busy ? null : onExit,
              tooltip: 'Cancel selection',
              icon: const Icon(Icons.close, color: Wa.icon),
            ),
            Expanded(
              child: Text(
                '$count selected',
                style: const TextStyle(
                  color: Wa.title,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Wa.accent,
                  ),
                ),
              )
            else ...<Widget>[
              TextButton(
                onPressed: total == 0 ? null : onSelectAll,
                child: Text(
                  allSelected ? 'Clear' : 'All ($total)',
                  style: const TextStyle(color: Wa.accent, fontSize: 13),
                ),
              ),
              IconButton(
                onPressed: act == null ? null : () => act(SelectionAction.pin),
                tooltip: allPinned ? 'Unpin' : 'Pin',
                icon: Icon(
                  allPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: Wa.icon,
                ),
              ),
              IconButton(
                onPressed:
                    act == null ? null : () => act(SelectionAction.archive),
                tooltip: allArchived ? 'Unarchive' : 'Archive',
                icon: Icon(
                  allArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                  color: Wa.icon,
                ),
              ),
              IconButton(
                onPressed: act == null ? null : () => act(SelectionAction.read),
                tooltip: anyUnread ? 'Mark as read' : 'Mark as unread',
                icon: Icon(
                  anyUnread ? Icons.drafts_outlined : Icons.mail_outline,
                  color: Wa.icon,
                ),
              ),
              IconButton(
                onPressed:
                    act == null ? null : () => act(SelectionAction.assign),
                tooltip: 'Assign to',
                icon: const Icon(Icons.person_add_alt_outlined, color: Wa.icon),
              ),
              IconButton(
                onPressed: act == null || count != 1
                    ? null
                    : () => act(SelectionAction.more),
                tooltip: 'More',
                icon: const Icon(Icons.more_vert, color: Wa.icon),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
