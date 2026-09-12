import 'package:flutter/material.dart';

import '../../../data/chat_assignment_repository.dart';
import '../../../theme/wa_colors.dart';

/// The mobile form of the web header's "Assigned:" dropdown.
///
/// A dropdown in a phone app bar has nowhere to open, so the same choice is
/// made in a sheet that slides up — one team member, or nobody.
///
/// Returns the id that is now on the chat: null for Unassigned, or nothing at
/// all if the sheet was dismissed without choosing.
Future<({String? userId})?> showAssignChatSheet(
  BuildContext context, {
  required List<TeamMember> members,
  required String? assignedTo,
  required Future<bool> Function(String? userId) onAssign,
}) {
  return showModalBottomSheet<({String? userId})>(
    context: context,
    backgroundColor: Wa.sheet,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _AssignChatSheet(
      members: members,
      assignedTo: assignedTo,
      onAssign: onAssign,
    ),
  );
}

class _AssignChatSheet extends StatefulWidget {
  const _AssignChatSheet({
    required this.members,
    required this.assignedTo,
    required this.onAssign,
  });

  final List<TeamMember> members;
  final String? assignedTo;
  final Future<bool> Function(String? userId) onAssign;

  @override
  State<_AssignChatSheet> createState() => _AssignChatSheetState();
}

class _AssignChatSheetState extends State<_AssignChatSheet> {
  bool _busy = false;

  Future<void> _choose(String? userId) async {
    if (_busy) return;
    setState(() => _busy = true);

    final ok = await widget.onAssign(userId);

    if (!mounted) return;
    setState(() => _busy = false);
    // Only close on a write that landed; a failure keeps the sheet up with
    // the error visible behind it.
    if (ok) Navigator.of(context).pop((userId: userId));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Assigned to',
                style: TextStyle(
                  color: Thread.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1, color: Wa.divider),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: <Widget>[
                  _Row(
                    label: 'Unassigned',
                    selected: widget.assignedTo == null,
                    enabled: !_busy,
                    onTap: () => _choose(null),
                  ),
                  for (final member in widget.members)
                    _Row(
                      label: member.name,
                      selected: member.userId == widget.assignedTo,
                      enabled: !_busy,
                      onTap: () => _choose(member.userId),
                    ),
                  if (widget.members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Text(
                        'No other team members are visible from this account, '
                        'so there is nobody else to assign to yet.',
                        style: TextStyle(color: Thread.meta, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: enabled ? onTap : null,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Wa.chipInactiveBackground,
        child: Icon(
          label == 'Unassigned' ? Icons.person_off_outlined : Icons.person,
          size: 16,
          color: selected ? Wa.accent : Thread.meta,
        ),
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? Wa.accent : Thread.text,
          fontSize: 15,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, size: 18, color: Wa.accent)
          : null,
    );
  }
}
