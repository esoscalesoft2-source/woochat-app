import 'package:flutter/material.dart';

import '../../../models/chat.dart';
import '../../../theme/wa_colors.dart';
import '../../chats/widgets/contact_avatar.dart';

/// Everything known about the contact behind a chat, in one sheet.
///
/// Reads only what the thread already loaded — no extra round trip when it
/// opens.
Future<void> showContactInfoSheet(
  BuildContext context, {
  required Chat chat,
  required String? assignedName,
  required List<String> labels,
  required List<String> categories,
  required VoidCallback onCopyNumber,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Wa.sheet,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ContactAvatar(chat: chat, radius: 36),
                    const SizedBox(height: 10),
                    Text(
                      chat.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Thread.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (chat.contactPhone != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        chat.contactPhone!,
                        style: const TextStyle(
                          color: Thread.meta,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (chat.contactPhone != null)
                _Row(
                  icon: Icons.copy_outlined,
                  label: 'Copy number',
                  value: chat.contactPhone!,
                  onTap: onCopyNumber,
                ),
              _Row(
                icon: Icons.person_outline,
                label: 'Assigned to',
                value: assignedName ?? 'Unassigned',
              ),
              _Row(
                icon: Icons.sell_outlined,
                label: 'Labels',
                value: labels.isEmpty ? 'None' : labels.join(', '),
              ),
              _Row(
                icon: Icons.account_tree_outlined,
                label: 'Categories',
                value: categories.isEmpty ? 'None' : categories.join(', '),
              ),
              _Row(
                icon: Icons.schedule,
                label: 'Last message',
                value: chat.lastMessageAt == null
                    ? 'No messages yet'
                    : _when(chat.lastMessageAt!),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _when(DateTime at) {
  final now = DateTime.now();
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  final time = TimeOfDay.fromDateTime(at);
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.period == DayPeriod.am ? 'AM' : 'PM';
  final clock = '$hour:$minute $suffix';
  return sameDay ? clock : '${at.day}/${at.month}/${at.year}, $clock';
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: Wa.icon),
      title: Text(
        label,
        style: const TextStyle(color: Thread.meta, fontSize: 12),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(color: Thread.text, fontSize: 14.5),
      ),
    );
  }
}
