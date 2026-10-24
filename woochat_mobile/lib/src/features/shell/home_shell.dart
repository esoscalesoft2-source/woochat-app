import 'package:flutter/material.dart';

import '../../models/tenant_context.dart';
import '../../theme/wa_colors.dart';
import '../chats/chats_list_screen.dart';
import '../monitor/chat_monitor_screen.dart';
import 'home_nav_bar.dart';
import 'more_sheet.dart';

/// The signed-in shell: Chats or Chat Monitor, plus the bottom navigation.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.tenantContext,
    required this.onSignOut,
  });

  final TenantContext tenantContext;
  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = HomeNavBar.activeIndex;

  /// Chat Monitor is built the first time it is opened, then kept, so its
  /// lists and the chats' scroll position both survive switching tabs.
  bool _monitorOpened = false;

  static final int _monitorTab = HomeNavBar.destinations.indexWhere(
    (destination) => destination.label == 'Monitor',
  );

  void _select(int index) => setState(() {
    _tab = index;
    if (index == _monitorTab) _monitorOpened = true;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Wa.background,
      body: IndexedStack(
        index: _tab == _monitorTab ? 1 : 0,
        children: <Widget>[
          ChatsListScreen(
            tenantContext: widget.tenantContext,
            onSignOut: widget.onSignOut,
          ),
          if (_monitorOpened)
            ChatMonitorScreen(tenantContext: widget.tenantContext)
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Builder(
        builder: (context) => HomeNavBar(
          currentIndex: _tab,
          onSelect: _select,
          onMore: () =>
              showMoreSheet(context, tenantContext: widget.tenantContext),
        ),
      ),
    );
  }
}
