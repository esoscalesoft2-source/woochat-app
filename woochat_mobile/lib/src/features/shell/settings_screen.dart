import 'package:flutter/material.dart';

import '../../models/tenant_context.dart';
import '../../theme/wa_colors.dart';
import '../chat/widgets/confirm_dialog.dart';
import 'storage_data_screen.dart';

/// The ⚙ beside Refresh: who is signed in, Storage and data, and the way
/// out — WhatsApp's settings, cut to what this app has.
Future<void> showSettingsScreen(
  BuildContext context, {
  required TenantContext tenantContext,
  required Future<void> Function() onSignOut,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => SettingsScreen(
        tenantContext: tenantContext,
        onSignOut: onSignOut,
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.tenantContext,
    required this.onSignOut,
  });

  final TenantContext tenantContext;
  final Future<void> Function() onSignOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _signOut() async {
    final sure = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need your password to sign in again.',
      confirmLabel: 'Sign out',
    );
    if (!sure || !mounted) return;
    Navigator.of(context).pop();
    await widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenantContext;
    return Scaffold(
      backgroundColor: Wa.background,
      appBar: AppBar(
        backgroundColor: Wa.background,
        foregroundColor: Wa.title,
        elevation: 0,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          // Who is signed in — the same card the nav bar's More shows.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: Wa.input,
                  child: Icon(Icons.person, color: Wa.icon, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        tenant.email ?? 'Signed in',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Wa.title,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tenant.role.label,
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

          _Row(
            key: const ValueKey<String>('settings-storage'),
            icon: Icons.data_usage_outlined,
            title: 'Storage and data',
            subtitle: 'Downloads, upload quality, auto-download',
            chevron: true,
            onTap: () => showStorageAndDataScreen(context),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1, color: Wa.divider),
          _Row(
            key: const ValueKey<String>('settings-sign-out'),
            icon: Icons.logout,
            iconColor: Wa.error,
            title: 'Sign out',
            titleColor: Wa.error,
            onTap: _signOut,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.iconColor = Wa.icon,
    this.titleColor = Wa.title,
    this.chevron = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color titleColor;

  /// Opens another page, so say so.
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: TextStyle(color: titleColor, fontSize: 15)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Wa.secondaryText, fontSize: 12.5),
            ),
      trailing: chevron ? const Icon(Icons.chevron_right, color: Wa.icon) : null,
    );
  }
}
