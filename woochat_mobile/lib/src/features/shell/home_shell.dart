import 'package:flutter/material.dart';

import '../../models/tenant_context.dart';
import '../../theme/wa_colors.dart';
import '../chats/chats_list_screen.dart';
import 'home_nav_bar.dart';

/// The signed-in shell: the Chats screen plus the bottom navigation.
class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.tenantContext,
    required this.onSignOut,
  });

  final TenantContext tenantContext;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Wa.background,
      body: ChatsListScreen(
        tenantContext: tenantContext,
        onSignOut: onSignOut,
      ),
      bottomNavigationBar: const HomeNavBar(),
    );
  }
}
