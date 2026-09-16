import 'package:flutter/material.dart';

import '../../../data/team_repository.dart';
import '../../../models/chat.dart';
import '../../../theme/wa_colors.dart';

/// The pseudo-user standing for "Me" in the Users filter: the admin's own
/// number — every chat on it, assigned or not. The web app uses the same
/// sentinel.
const String kMeUserId = '__me__';

/// Narrows [chats] to the picked users, the way the web app does.
///
/// A tenant admin's list names their STAFF, so the match is on who the chat
/// is assigned to. A super admin's list names chat OWNERS (one per WhatsApp
/// number), so the match is on the owner. "Me" is the admin's own chats —
/// owned by them, or not handed to anyone — because once the queue has dealt
/// the pool out, "unassigned" alone was empty.
List<Chat> applyUsersFilter(
  List<Chat> chats, {
  required Set<String> selected,
  required String authUserId,
  required bool isSuperAdmin,
}) {
  if (selected.isEmpty) return chats;
  final wantMine = selected.contains(kMeUserId);
  return <Chat>[
    for (final chat in chats)
      if ((wantMine && (chat.userId == authUserId || chat.assignedTo == null)) ||
          selected.contains(isSuperAdmin ? chat.userId : chat.assignedTo))
        chat,
  ];
}

/// The label the chip shows for the current pick.
String usersFilterLabel(Set<String> selected, List<TeamUser> options) {
  if (selected.isEmpty) return 'Users';
  if (selected.length == 1) {
    final id = selected.single;
    if (id == kMeUserId) return 'Me';
    for (final option in options) {
      if (option.userId == id) return option.name;
    }
    return 'Users';
  }
  return 'Users (${selected.length})';
}

/// The picker behind the Users chip: "Me", then the team, each with a tick.
/// Returns the new selection, or null when dismissed unchanged.
Future<Set<String>?> showUsersFilterSheet(
  BuildContext context, {
  required List<TeamUser> options,
  required Set<String> selected,
  required bool includeMe,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    backgroundColor: Wa.sheet,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _UsersFilterSheet(
      options: options,
      selected: selected,
      includeMe: includeMe,
    ),
  );
}

class _UsersFilterSheet extends StatefulWidget {
  const _UsersFilterSheet({
    required this.options,
    required this.selected,
    required this.includeMe,
  });

  final List<TeamUser> options;
  final Set<String> selected;
  final bool includeMe;

  @override
  State<_UsersFilterSheet> createState() => _UsersFilterSheetState();
}

class _UsersFilterSheetState extends State<_UsersFilterSheet> {
  late final Set<String> _picked = <String>{...widget.selected};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<TeamUser> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where((user) => user.name.toLowerCase().contains(query))
        .toList();
  }

  void _toggle(String id) {
    setState(() {
      if (!_picked.remove(id)) _picked.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showMe = widget.includeMe && _search.text.trim().isEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Team users',
                        style: TextStyle(
                          color: Wa.title,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_picked.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(_picked.clear),
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: Wa.accent, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  key: const ValueKey<String>('users-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Wa.title, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search users…',
                    hintStyle: const TextStyle(color: Wa.secondaryText),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: Wa.input,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: Wa.divider),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: <Widget>[
                    if (showMe)
                      _Row(
                        label: 'Me',
                        subtitle: 'My own chats, whoever is working them',
                        on: _picked.contains(kMeUserId),
                        onTap: () => _toggle(kMeUserId),
                      ),
                    for (final user in _visible)
                      _Row(
                        label: user.name,
                        subtitle: user.phone,
                        on: _picked.contains(user.userId),
                        onTap: () => _toggle(user.userId),
                      ),
                    if (_visible.isEmpty && !showMe)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No users match.',
                          style: TextStyle(color: Wa.secondaryText),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_picked),
                  style: FilledButton.styleFrom(
                    backgroundColor: Wa.accent,
                    foregroundColor: Wa.onAccent,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _picked.isEmpty
                        ? 'Show all chats'
                        : 'Show ${_picked.length} '
                            '${_picked.length == 1 ? 'user' : 'users'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.on,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Icon(
        on ? Icons.check_circle : Icons.circle_outlined,
        size: 22,
        color: on ? Wa.accent : Wa.icon,
      ),
      title: Text(label, style: const TextStyle(color: Wa.title, fontSize: 15)),
      subtitle: subtitle == null || subtitle!.isEmpty
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Wa.secondaryText, fontSize: 12),
            ),
    );
  }
}
