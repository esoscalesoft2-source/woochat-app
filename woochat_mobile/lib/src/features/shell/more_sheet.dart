import 'package:flutter/material.dart';

import '../../models/tenant_context.dart';
import '../../theme/wa_colors.dart';
import '../chat/widgets/confirm_dialog.dart';

/// What the nav bar's More tab opens: who is signed in, and Sign out.
///
/// Sign out asks first — on a phone it is one thumb-slip from Contacts, and
/// getting back in means the password again.
Future<void> showMoreSheet(
  BuildContext context, {
  required TenantContext tenantContext,
  required Future<void> Function() onSignOut,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Wa.sheet,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: Wa.input,
                  child: Icon(Icons.person, color: Wa.icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        tenantContext.email ?? 'Signed in',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Wa.title,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tenantContext.role.label,
                        style: const TextStyle(
                          color: Wa.secondaryText,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Wa.divider),
          ListTile(
            key: const ValueKey<String>('more-sign-out'),
            leading: const Icon(Icons.logout, color: Wa.error),
            title: const Text(
              'Sign out',
              style: TextStyle(color: Wa.title, fontSize: 15),
            ),
            onTap: () async {
              final sure = await showConfirmDialog(
                context,
                title: 'Sign out?',
                message: 'You will need your password to sign in again.',
                confirmLabel: 'Sign out',
              );
              if (!sure || !context.mounted) return;
              Navigator.of(context).pop();
              await onSignOut();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
