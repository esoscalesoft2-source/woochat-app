import 'package:flutter/material.dart';

import '../../data/account_store.dart';
import '../../models/tenant_context.dart';
import '../../state/session_controller.dart';
import '../../state/session_scope.dart';
import '../../theme/wa_colors.dart';
import '../chat/widgets/confirm_dialog.dart';

/// What the nav bar's More tab opens: every account signed in on this phone
/// — the one in use first, ticked; tap another to switch to it — and Add
/// account. Signing the account in use out is in Settings.
Future<void> showMoreSheet(
  BuildContext context, {
  required TenantContext tenantContext,
}) {
  final session = SessionScope.of(context);
  return showModalBottomSheet<_After>(
    context: context,
    backgroundColor: Wa.sheet,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => _MoreSheet(
      session: session,
      tenantContext: tenantContext,
      // Messages show over the shell, not the sheet.
      shellContext: context,
    ),
  ).then((after) {
    // Only once the sheet is gone: the router moves to the login screen, and
    // a sheet still closing would be left stranded under it.
    if (after == _After.addAccount) session.beginAddAccount();
  });
}

/// What to do once the sheet has closed.
enum _After { addAccount }

class _MoreSheet extends StatefulWidget {
  const _MoreSheet({
    required this.session,
    required this.tenantContext,
    required this.shellContext,
  });

  final SessionController session;
  final TenantContext tenantContext;
  final BuildContext shellContext;

  @override
  State<_MoreSheet> createState() => _MoreSheetState();
}

class _MoreSheetState extends State<_MoreSheet> {
  String get _me => widget.tenantContext.authUserId;

  List<SavedAccount> get _others =>
      widget.session.savedAccounts.where((a) => a.userId != _me).toList();

  void _notify(String message) {
    final context = widget.shellContext;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _switchTo(SavedAccount account) async {
    Navigator.of(context).pop();
    try {
      await widget.session.switchTo(account.userId);
    } on SessionSwitchException catch (error) {
      _notify(error.message);
    } catch (error) {
      _notify('Could not switch accounts: $error');
    }
  }

  void _addAccount() => Navigator.of(context).pop(_After.addAccount);

  Future<void> _forget(SavedAccount account) async {
    final sure = await showConfirmDialog(
      context,
      title: 'Sign out ${account.email}?',
      message:
          'It leaves this phone. You will need its password to add it again.',
      confirmLabel: 'Sign out',
    );
    if (!sure || !mounted) return;
    await widget.session.forget(account.userId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final others = _others;
    final role = widget.tenantContext.role.label;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              KeyedSubtree(
                key: const ValueKey<String>('more-account-card'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                  child: Row(
                    children: <Widget>[
                      _Avatar(email: widget.tenantContext.email, active: true),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AccountText(
                          email: widget.tenantContext.email ?? 'Signed in',
                          detail: others.isEmpty
                              ? role
                              : '$role · ${others.length + 1} accounts',
                          bold: true,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.check_circle, color: Wa.accent),
                      ),
                    ],
                  ),
                ),
              ),
              for (final account in others)
                ListTile(
                  key: ValueKey<String>('more-account-${account.userId}'),
                  contentPadding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                  leading: _Avatar(email: account.email),
                  title: _AccountText(
                    email: account.email,
                    detail: account.roleLabel ?? 'Tap to switch',
                  ),
                  trailing: IconButton(
                    tooltip: 'Sign out ${account.email}',
                    icon: const Icon(Icons.logout, size: 20, color: Wa.icon),
                    onPressed: () => _forget(account),
                  ),
                  onTap: () => _switchTo(account),
                ),
              ListTile(
                key: const ValueKey<String>('more-add-account'),
                contentPadding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                leading: const CircleAvatar(
                  radius: 22,
                  backgroundColor: Wa.input,
                  child: Icon(Icons.person_add_alt_1, color: Wa.accent),
                ),
                title: const Text(
                  'Add account',
                  style: TextStyle(color: Wa.title, fontSize: 15),
                ),
                subtitle: const Text(
                  'Sign in to another WooChat account',
                  style: TextStyle(color: Wa.secondaryText, fontSize: 12.5),
                ),
                onTap: _addAccount,
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.email, this.active = false});

  final String? email;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final trimmed = (email ?? '').trim();
    return CircleAvatar(
      radius: 22,
      backgroundColor: active ? Wa.accentSoft : Wa.input,
      child: trimmed.isEmpty
          ? const Icon(Icons.person, color: Wa.icon)
          : Text(
              trimmed[0].toUpperCase(),
              style: TextStyle(
                color: active ? Wa.accent : Wa.title,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

class _AccountText extends StatelessWidget {
  const _AccountText({
    required this.email,
    required this.detail,
    this.bold = false,
  });

  final String email;
  final String detail;
  final bool bold;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Wa.title,
          fontSize: 15,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        detail,
        style: const TextStyle(color: Wa.secondaryText, fontSize: 13),
      ),
    ],
  );
}
