import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/chat_filters_repository.dart';
import '../../data/chats_repository.dart';
import '../../data/schedules_repository.dart';
import '../../models/chat.dart';
import '../../models/chat_filters.dart';
import '../../models/tenant_context.dart';
import '../../routing/app_router.dart';
import '../../theme/wa_colors.dart';
import 'chat_filter_state.dart';
import 'widgets/chat_list_tile.dart';
import 'widgets/more_filters_sheet.dart';
import 'widgets/new_chat_dialog.dart';
import 'widgets/schedules_chip.dart';

/// Live list of the tenant's WhatsApp conversations.
class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({
    super.key,
    required this.tenantContext,
    required this.onSignOut,
  });

  final TenantContext tenantContext;
  final Future<void> Function() onSignOut;

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _repository = const ChatsRepository();
  final _schedules = const SchedulesRepository();
  final _filtersRepository = const ChatFiltersRepository();
  final _searchController = TextEditingController();

  /// Bumped to force a fresh subscription when the user taps refresh.
  int _streamGeneration = 0;
  late Stream<List<Chat>> _chats = _createStream();

  ChatFilterState _filters = ChatFilterState.initial;
  ChatFilterData _filterData = ChatFilterData.empty;
  bool _filterDataLoading = true;

  String _query = '';
  DateTimeRange? _range;

  ScheduledChatIds _scheduled = ScheduledChatIds.empty;

  /// Null while the Schedules filter is off.
  ScheduleBucket? _scheduleBucket;
  Timer? _schedulePoll;

  // Archived rows are fetched too so the Archived filter has something to
  // show; the engine then applies the tab rules client-side.
  Stream<List<Chat>> _createStream() => _repository.watchChats(
        tenantAdminId: widget.tenantContext.tenantAdminId,
        includeArchived: true,
      );

  @override
  void initState() {
    super.initState();
    _loadScheduled();
    _loadFilterData();
    // Re-poll so the pending pulse clears once the last send goes out.
    _schedulePoll = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadScheduled(),
    );
  }

  @override
  void dispose() {
    _schedulePoll?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadScheduled() async {
    try {
      final scheduled = await _schedules.fetchScheduledChatIds();
      if (mounted) setState(() => _scheduled = scheduled);
    } catch (_) {
      // The chat list must keep working even if this RPC is unavailable.
    }
  }

  Future<void> _loadFilterData() async {
    try {
      final data = await _filtersRepository.load(
        funnelStart: _range?.start.toUtc().toIso8601String(),
        funnelEnd: _endOfDay(_range?.end)?.toUtc().toIso8601String(),
      );
      if (mounted) setState(() => _filterData = data);
    } catch (_) {
      // Leave the dropdown empty rather than blocking the list.
    } finally {
      if (mounted) setState(() => _filterDataLoading = false);
    }
  }

  /// "Replied" is scoped by the picked range, so the funnel sets are refetched
  /// whenever it changes. Nothing else in the reference data moves with it.
  Future<void> _reloadFunnel() async {
    try {
      final funnel = await _filtersRepository.refreshFunnel(
        start: _range?.start.toUtc().toIso8601String(),
        end: _endOfDay(_range?.end)?.toUtc().toIso8601String(),
      );
      if (!mounted) return;
      setState(() {
        _filterData = _filterData.withFunnel(
          failed: funnel.failed,
          replied: funnel.replied,
        );
      });
    } catch (_) {
      // Keep the previous sets.
    }
  }

  static DateTime? _endOfDay(DateTime? day) => day == null
      ? null
      : DateTime(day.year, day.month, day.day, 23, 59, 59, 999);

  DateTimeRangeMs? get _rangeMs {
    final range = _range;
    if (range == null) return null;
    return DateTimeRangeMs(
      DateTime(range.start.year, range.start.month, range.start.day)
          .millisecondsSinceEpoch,
      _endOfDay(range.end)!.millisecondsSinceEpoch,
    );
  }

  void _refresh() {
    setState(() {
      _streamGeneration++;
      _chats = _createStream();
    });
    _loadScheduled();
    _loadFilterData();
  }

  void _openChat(Chat chat) {
    // Nested route, so this pushes /chats/<id> onto /chats — the URL updates
    // and Back still returns to the list. `extra` skips the refetch, and
    // carries the directory photo so the thread header matches the list.
    context.go(
      Routes.chat(chat.id),
      extra: chat.withPhoto(_photoFor(chat)),
    );
  }

  String? _photoFor(Chat chat) =>
      _filterData.photoFor(chat.normalisedPhone, chat.profilePhotoUrl);

  Future<void> _startNewChat() async {
    final chat = await showNewChatDialog(
      context,
      ownerId: widget.tenantContext.authUserId,
    );
    if (chat != null && mounted) _openChat(chat);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Wa.accent,
            onPrimary: Wa.onAccent,
            surface: Wa.background,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _range = picked);
      await _reloadFunnel();
    }
  }

  Future<void> _openMoreFilters(List<Chat> scoped) async {
    final next = await showMoreFiltersSheet(
      context,
      scopedChats: scoped,
      data: _filterData,
      state: _filters,
      signedInUserId: widget.tenantContext.authUserId,
      signedInLabel: widget.tenantContext.email,
      range: _rangeMs,
    );
    if (next != null && mounted) {
      // Any dropdown filter takes over from the Schedules axis.
      setState(() {
        _filters = next;
        _scheduleBucket = null;
      });
    }
  }

  /// Plain taps toggle on and off; arriving on a failure bucket cycles down
  /// through it first.
  void _cycleSchedules() {
    setState(() {
      _scheduleBucket = switch (_scheduleBucket) {
        null => ScheduleBucket.all,
        ScheduleBucket.failedActive => ScheduleBucket.failed,
        ScheduleBucket.failed => ScheduleBucket.all,
        ScheduleBucket.all => null,
      };
    });
  }

  /// Free-text search, applied before everything else so the counts describe
  /// what tapping each filter will show.
  List<Chat> _searchScoped(List<Chat> chats) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return chats;
    final digits = Chat.normalisePhone(query);

    return chats.where((chat) {
      final haystack = <String>[
        chat.displayName,
        chat.contactPhone ?? '',
        chat.lastMessage ?? '',
      ].join(' ').toLowerCase();

      if (haystack.contains(query)) return true;
      return digits.isNotEmpty && chat.normalisedPhone.contains(digits);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Wa.background,
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        backgroundColor: Wa.accent,
        foregroundColor: Wa.onAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        tooltip: 'New chat',
        child: const Icon(Icons.add_comment, size: 24),
      ),
      body: StreamBuilder<List<Chat>>(
        key: ValueKey<int>(_streamGeneration),
        stream: _chats,
        builder: (context, snapshot) {
          final scoped = _searchScoped(snapshot.data ?? const <Chat>[]);
          final bucket = _scheduleBucket;

          // Schedules is its own axis: while it is on it replaces the tab and
          // dropdown selection rather than stacking with them.
          final visible = ChatFilterEngine.apply(
            chats: scoped,
            data: _filterData,
            state: bucket == null ? _filters : ChatFilterState.initial,
            range: _rangeMs,
            scheduleIds: bucket == null ? null : _scheduled.bucket(bucket),
          );

          int tabCount(ContactTab tab) => ChatFilterEngine.count(
                chats: scoped,
                data: _filterData,
                state: _filters.selectTab(tab),
                range: _rangeMs,
              );

          return Column(
            children: <Widget>[
              _Header(
                searchController: _searchController,
                onQueryChanged: (value) => setState(() => _query = value),
                range: _range,
                onPickRange: _pickDateRange,
                onClearRange: () async {
                  setState(() => _range = null);
                  await _reloadFunnel();
                },
                filters: _filters,
                scheduling: bucket != null,
                allCount: tabCount(ContactTab.all),
                unreadCount: tabCount(ContactTab.unread),
                onTabChanged: (tab) => setState(() {
                  _filters = _filters.selectTab(tab);
                  _scheduleBucket = null;
                }),
                scheduleBucket: bucket,
                schedulesHavePending: _scheduled.hasPending,
                scheduleFailedCount: _scheduled.failedCount,
                onScheduleTap: _cycleSchedules,
                onShowScheduleFailures: () => setState(
                  () => _scheduleBucket = ScheduleBucket.failedActive,
                ),
                onMoreFilters:
                    _filterDataLoading ? null : () => _openMoreFilters(scoped),
                tenantContext: widget.tenantContext,
                onRefresh: _refresh,
                onSignOut: widget.onSignOut,
              ),
              Expanded(child: _body(snapshot, visible)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(AsyncSnapshot<List<Chat>> snapshot, List<Chat> visible) {
    if (snapshot.hasError) {
      return _ChatsError(
        message: snapshot.error.toString(),
        onRetry: _refresh,
      );
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator(color: Wa.accent));
    }
    if (visible.isEmpty) {
      return _EmptyChats(
        filters: _filters,
        query: _query,
        range: _range,
        scheduleBucket: _scheduleBucket,
        onClearFilters: _filters.isNarrowed
            ? () => setState(() => _filters = _filters.clearAll())
            : null,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final chat = visible[index];
        return ChatListTile(
          chat: chat,
          subtitleStamp: TimeFormat.listStamp(chat.lastMessageAt),
          showDivider: index != visible.length - 1,
          photoUrl: _photoFor(chat),
          onTap: () => _openChat(chat),
        );
      },
    );
  }
}

/// Title row, search field, date range and the filter chips.
class _Header extends StatelessWidget {
  const _Header({
    required this.searchController,
    required this.onQueryChanged,
    required this.range,
    required this.onPickRange,
    required this.onClearRange,
    required this.filters,
    required this.scheduling,
    required this.allCount,
    required this.unreadCount,
    required this.onTabChanged,
    required this.scheduleBucket,
    required this.schedulesHavePending,
    required this.scheduleFailedCount,
    required this.onScheduleTap,
    required this.onShowScheduleFailures,
    required this.onMoreFilters,
    required this.tenantContext,
    required this.onRefresh,
    required this.onSignOut,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final DateTimeRange? range;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;
  final ChatFilterState filters;
  final bool scheduling;
  final int allCount;
  final int unreadCount;
  final ValueChanged<ContactTab> onTabChanged;
  final ScheduleBucket? scheduleBucket;
  final bool schedulesHavePending;
  final int scheduleFailedCount;
  final VoidCallback onScheduleTap;
  final VoidCallback onShowScheduleFailures;

  /// Null while the reference data is still loading.
  final VoidCallback? onMoreFilters;

  final TenantContext tenantContext;
  final VoidCallback onRefresh;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Wa.divider, width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'WOO Chats',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        height: 22 / 18,
                        fontWeight: FontWeight.w700,
                        color: Wa.title,
                      ),
                    ),
                  ),
                  _OverflowMenu(
                    tenantContext: tenantContext,
                    onRefresh: onRefresh,
                    onSignOut: onSignOut,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              // The date filter rides in the search bar rather than taking a
              // row of its own, which is what freed the space for more chats.
              child: _SearchField(
                controller: searchController,
                onChanged: onQueryChanged,
                rangeActive: range != null,
                onPickRange: onPickRange,
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                children: <Widget>[
                  if (range != null) ...<Widget>[
                    _DateRangeChip(
                      range: range!,
                      labelDated: filters.datesLabelAssignment,
                      onTap: onPickRange,
                      onClear: onClearRange,
                    ),
                    const SizedBox(width: 6),
                  ],
                  _Chip(
                    label: 'All ($allCount)',
                    active: !scheduling && filters.tab == ContactTab.all,
                    onTap: () => onTabChanged(ContactTab.all),
                  ),
                  const SizedBox(width: 6),
                  _Chip(
                    label: 'Unread ($unreadCount)',
                    active: !scheduling && filters.tab == ContactTab.unread,
                    onTap: () => onTabChanged(ContactTab.unread),
                  ),
                  const SizedBox(width: 6),
                  SchedulesChip(
                    bucket: scheduleBucket,
                    hasPending: schedulesHavePending,
                    onTap: onScheduleTap,
                  ),
                  const SizedBox(width: 6),
                  _MoreFiltersButton(
                    active: !scheduling && filters.isNarrowed,
                    scheduleFailedCount: scheduleFailedCount,
                    onOpen: onMoreFilters,
                    onShowScheduleFailures: onShowScheduleFailures,
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

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.rangeActive,
    required this.onPickRange,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool rangeActive;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Wa.title, fontSize: 14),
      cursorColor: Wa.accent,
      decoration: InputDecoration(
        hintText: 'Search or start new chat',
        hintStyle: const TextStyle(color: Wa.secondaryText, fontSize: 14),
        prefixIcon: const Icon(Icons.search, size: 18, color: Wa.secondaryText),
        prefixIconConstraints: const BoxConstraints(minWidth: 38),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : _SuffixIcon(
                      icon: Icons.close,
                      tooltip: 'Clear search',
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
            _SuffixIcon(
              icon: Icons.calendar_today_outlined,
              tooltip: 'Filter by date range',
              active: rangeActive,
              onPressed: onPickRange,
            ),
            const SizedBox(width: 4),
          ],
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0),
        filled: true,
        fillColor: Wa.chipInactiveBackground,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 9),
        border: _border,
        enabledBorder: _border,
        focusedBorder: _border,
      ),
    );
  }

  static final OutlineInputBorder _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide.none,
  );
}

class _SuffixIcon extends StatelessWidget {
  const _SuffixIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      color: active ? Wa.accent : Wa.secondaryText,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }
}

/// The active date range, shown beside the tabs. Filters on `last_message_at`
/// — or on when the label went on, whenever a label is selected.
class _DateRangeChip extends StatelessWidget {
  const _DateRangeChip({
    required this.range,
    required this.labelDated,
    required this.onTap,
    required this.onClear,
  });

  final DateTimeRange range;
  final bool labelDated;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final format = DateFormat.MMMd();
    final label = '${format.format(range.start)} - '
        '${format.format(range.end)}${labelDated ? ' (label)' : ''}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: Wa.chipActiveBackground,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.calendar_today_outlined,
                size: 13, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 14),
              color: Colors.white,
              tooltip: 'Clear date range',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Wa.chipActiveBackground : Wa.chipInactiveBackground,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? Colors.white : Wa.secondaryText,
          ),
        ),
      ),
    );
  }
}

/// The chevron beside the chips. A long-press jumps straight to the scheduled
/// failures, which is the mobile stand-in for the web's dashboard alert.
class _MoreFiltersButton extends StatelessWidget {
  const _MoreFiltersButton({
    required this.active,
    required this.scheduleFailedCount,
    required this.onOpen,
    required this.onShowScheduleFailures,
  });

  final bool active;
  final int scheduleFailedCount;
  final VoidCallback? onOpen;
  final VoidCallback onShowScheduleFailures;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: onOpen == null ? 'Loading filters' : 'More filters',
      child: GestureDetector(
        onTap: onOpen,
        onLongPress: scheduleFailedCount > 0 ? onShowScheduleFailures : null,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Wa.chipActiveBackground : Wa.chipInactiveBackground,
            shape: BoxShape.circle,
          ),
          child: onOpen == null
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Wa.secondaryText,
                  ),
                )
              : Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: active ? Colors.white : Wa.secondaryText,
                ),
        ),
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.tenantContext,
    required this.onRefresh,
    required this.onSignOut,
  });

  final TenantContext tenantContext;
  final VoidCallback onRefresh;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      icon: const Icon(Icons.more_vert, size: 20, color: Wa.icon),
      color: Wa.rowHover,
      // The default 48px button set the whole title row's height.
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onSelected: (value) {
        switch (value) {
          case 'refresh':
            onRefresh();
          case 'sign_out':
            onSignOut();
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                tenantContext.email ?? 'Signed in',
                style: const TextStyle(color: Wa.title, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                tenantContext.role.label,
                style: const TextStyle(color: Wa.secondaryText, fontSize: 12),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'refresh',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.refresh, color: Wa.icon),
            title: Text('Refresh', style: TextStyle(color: Wa.title)),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'sign_out',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: Wa.icon),
            title: Text('Sign out', style: TextStyle(color: Wa.title)),
          ),
        ),
      ],
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({
    required this.filters,
    required this.query,
    required this.range,
    required this.scheduleBucket,
    required this.onClearFilters,
  });

  final ChatFilterState filters;
  final String query;
  final DateTimeRange? range;
  final ScheduleBucket? scheduleBucket;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final (String title, String body) = switch (true) {
      _ when scheduleBucket == ScheduleBucket.all => (
          'Nothing scheduled',
          'Chats with a scheduled send show here.',
        ),
      _ when scheduleBucket != null => (
          'No failed sends',
          'Scheduled sends that failed show here.',
        ),
      _ when query.trim().isNotEmpty => (
          'No matches',
          'Nothing matches "${query.trim()}".',
        ),
      _ when filters.isNarrowed => (
          'No chats match these filters',
          'Try widening or clearing the filters.',
        ),
      _ when range != null => (
          'Nothing in that range',
          'No conversations were active between those dates.',
        ),
      _ => switch (filters.tab) {
          ContactTab.unread => ('All caught up', 'No unread conversations.'),
          ContactTab.archived => (
              'Nothing archived',
              'Archived chats show here.',
            ),
          ContactTab.all => (
              'No conversations yet',
              'Chats appear here as soon as a contact messages your '
                  'WhatsApp Business number.',
            ),
        },
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.chat_outlined, size: 48, color: Wa.secondaryText),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Wa.title,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Wa.secondaryText, fontSize: 14),
            ),
            if (onClearFilters != null) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: onClearFilters,
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatsError extends StatelessWidget {
  const _ChatsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 48, color: Wa.error),
            const SizedBox(height: 16),
            const Text(
              'Could not load chats',
              style: TextStyle(
                color: Wa.title,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Wa.secondaryText, fontSize: 12),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
