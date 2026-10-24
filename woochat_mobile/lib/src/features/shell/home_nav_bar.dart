import 'package:flutter/material.dart';

import '../../theme/wa_colors.dart';

class NavDestination {
  const NavDestination(
    this.label,
    this.icon,
    this.selectedIcon, {
    this.enabled = false,
    this.opensSheet = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool enabled;

  /// True for a tab that opens something rather than switching screens.
  final bool opensSheet;
}

/// The app's bottom navigation.
///
/// Chats and Monitor are screens; the rest are disabled placeholders so the
/// final information architecture is visible, and More opens a sheet.
class HomeNavBar extends StatelessWidget {
  const HomeNavBar({
    super.key,
    this.onMore,
    this.currentIndex = 0,
    this.onSelect,
  });

  /// Opens the More sheet (accounts, Sign out).
  final VoidCallback? onMore;

  /// The screen showing, as an index into [destinations].
  final int currentIndex;

  /// Switches to another enabled screen.
  final ValueChanged<int>? onSelect;

  /// Chats leads: the router lands here after sign-in. Chat Monitor sits
  /// right beside it — the issues to fix are about those same chats.
  static const List<NavDestination> destinations = <NavDestination>[
    NavDestination('Chats', Icons.chat_bubble_outline, Icons.chat,
        enabled: true),
    NavDestination('Monitor', Icons.monitor_heart_outlined,
        Icons.monitor_heart, enabled: true),
    NavDestination('Dashboard', Icons.dashboard_outlined, Icons.dashboard),
    NavDestination('Enquiries', Icons.assignment_outlined, Icons.assignment),
    NavDestination('Contacts', Icons.contacts_outlined, Icons.contacts),
    NavDestination('More', Icons.more_horiz, Icons.more_horiz,
        enabled: true, opensSheet: true),
  ];

  /// Where the app opens: the first screen, derived rather than hardcoded
  /// so reordering can never leave the highlight on the wrong tab. More
  /// opens a sheet and is never "current".
  static int get activeIndex => destinations
      .indexWhere((destination) => destination.enabled && !destination.opensSheet);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Wa.surfaceContainer,
        border: Border(top: BorderSide(color: Wa.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _NavItem(
                    destination: destinations[i],
                    active: i == currentIndex,
                    onTap: () => _onTap(context, i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, int index) {
    final destination = destinations[index];
    if (destination.opensSheet) {
      onMore?.call();
      return;
    }
    if (destination.enabled) {
      if (index != currentIndex) onSelect?.call(index);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${destination.label} arrives in a later phase.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Wa.navActive
        : Wa.navInactive.withValues(alpha: destination.enabled ? 1 : 0.45);

    return Semantics(
      button: true,
      selected: active,
      enabled: destination.enabled,
      label: destination.enabled
          ? destination.label
          : '${destination.label}, coming soon',
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              active ? destination.selectedIcon : destination.icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              destination.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
