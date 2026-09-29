import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../core/constants.dart';
import '../../data/chat_assignment_repository.dart';
import '../../data/chat_filters_repository.dart';
import '../../data/chat_tags_repository.dart';
import '../../data/chats_repository.dart';
import '../../data/customer_products_repository.dart';
import '../../data/notes_repository.dart';
import '../../data/schedules_repository.dart';
import '../../data/team_repository.dart';
import '../../models/chat.dart';
import '../../models/chat_filters.dart';
import '../../models/tenant_context.dart';
import '../../routing/app_router.dart';
import '../../theme/wa_colors.dart';
import '../chat/widgets/chat_tags_sheet.dart';
import '../shell/settings_screen.dart';
import 'chat_filter_state.dart';
import 'widgets/chat_list_tile.dart';
import 'widgets/chat_notes_sheet.dart';
import 'widgets/chat_row_menu.dart';
import 'widgets/more_filters_sheet.dart';
import 'widgets/new_chat_dialog.dart';
import 'widgets/schedules_chip.dart';
import 'widgets/selection_bar.dart';
import 'widgets/users_filter.dart';
import '../chat/widgets/assign_chat_sheet.dart';

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
  final _assignments = const ChatAssignmentRepository();
  final _tags = const ChatTagsRepository();
  final _products = const CustomerProductsRepository();
  final _notes = const NotesRepository();
  final _searchController = TextEditingController();

  /// Team member names by user id, for the 👤 line on each row.
  Map<String, String> _ownerNames = const <String, String>{};

  /// The Users filter: who it can name, and who is picked. Admins only —
  /// a plain user has no team to filter by, so the chip is not shown.
  final _team = const TeamRepository();
  List<TeamUser> _teamUsers = const <TeamUser>[];
  final _userFilter = <String>{};

  bool get _isAdmin =>
      widget.tenantContext.role == AppRole.admin ||
      widget.tenantContext.role == AppRole.superAdmin;
  bool get _isSuperAdmin => widget.tenantContext.role == AppRole.superAdmin;

  /// Whether the row menu may offer "Mark as unread" on a read chat.
  bool _canMarkUnread = false;

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

  /// Select mode, entered by a long press: the picked chat ids, and whether a
  /// bulk write is in flight. Empty means not selecting.
  final _selected = <String>{};
  bool _selecting = false;
  bool _bulkBusy = false;

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
    _loadTeam();
    _loadTeamUsers();
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

  /// Names for the owner / assignee line, plus whether this user may set a
  /// chat back to unread — admins always can, staff only when delegated.
  Future<void> _loadTeam() async {
    final role = widget.tenantContext.role;
    final isAdmin = role == AppRole.admin || role == AppRole.superAdmin;
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        _assignments.displayNames(),
        isAdmin
            ? Future<bool>.value(true)
            : _assignments.canMarkUnread(widget.tenantContext.authUserId),
      ]);
      if (!mounted) return;
      setState(() {
        _ownerNames = results[0] as Map<String, String>;
        _canMarkUnread = results[1] as bool;
      });
    } catch (_) {
      // The row simply shows short ids instead of names.
    }
  }

  /// The names the Users filter offers. A tenant admin's staff come from
  /// the database; a super admin's list is built from the chats themselves —
  /// one entry per owner — once they have loaded (see [_superAdminOwners]).
  Future<void> _loadTeamUsers() async {
    if (!_isAdmin || _isSuperAdmin) return;
    final users = await _team.myStaff();
    if (mounted) setState(() => _teamUsers = users);
  }

  List<TeamUser> _superAdminOwners(List<Chat> chats) {
    final ids = <String>{for (final chat in chats) chat.userId};
    return <TeamUser>[
      for (final id in ids) TeamUser(userId: id, name: _ownerName(id)),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _openUsersFilter(List<Chat> scoped) async {
    final options =
        _isSuperAdmin ? _superAdminOwners(scoped) : _teamUsers;
    final picked = await showUsersFilterSheet(
      context,
      options: options,
      selected: _userFilter,
      // "Me" only makes sense for a tenant admin with a number of their own.
      includeMe: !_isSuperAdmin,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _userFilter
        ..clear()
        ..addAll(picked);
    });
  }

  String _ownerName(String userId) {
    final known = _ownerNames[userId]?.trim();
    if (known != null && known.isNotEmpty && known != 'Unknown User') {
      return known;
    }
    if (userId == widget.tenantContext.authUserId) return 'You';
    return 'User ${userId.substring(0, userId.length.clamp(0, 8))}';
  }

  /// Mirrors the web sidebar: a super admin sees who owns the chat, an admin
  /// sees who it is assigned to, and everyone else gets no line.
  OwnerLine? _ownerLineFor(Chat chat) {
    switch (widget.tenantContext.role) {
      case AppRole.superAdmin:
        return OwnerLine(OwnerLineKind.owner, _ownerName(chat.userId));
      case AppRole.admin:
        final assignee = chat.assignedTo?.trim();
        if (assignee == null || assignee.isEmpty) {
          return const OwnerLine(OwnerLineKind.unassigned, 'Unassigned');
        }
        return OwnerLine(OwnerLineKind.assignee, _ownerName(assignee));
      case AppRole.moderator:
      case AppRole.user:
        return null;
    }
  }

  // ---- Select mode ------------------------------------------------------

  void _enterSelectMode(Chat chat) {
    setState(() {
      _selecting = true;
      _selected.add(chat.id);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selecting = false;
      _selected.clear();
      _bulkBusy = false;
    });
  }

  void _toggleSelected(Chat chat) {
    setState(() {
      if (!_selected.remove(chat.id)) _selected.add(chat.id);
      // Deselecting the last one leaves select mode, as WhatsApp does.
      if (_selected.isEmpty) _selecting = false;
    });
  }

  /// Select all picks what the list is showing, not the whole table — on
  /// Unread that is the unread ones, under a label the labelled ones.
  void _selectAllOrNone(List<Chat> visible) {
    setState(() {
      if (_selected.length >= visible.length) {
        _selected.clear();
        _selecting = false;
      } else {
        _selected.addAll(visible.map((chat) => chat.id));
      }
    });
  }

  List<Chat> _selectedChats(List<Chat> pool) => <Chat>[
    for (final chat in pool)
      if (_selected.contains(chat.id)) chat,
  ];

  Future<void> _onSelectionAction(
    SelectionAction action,
    List<Chat> visible,
  ) async {
    final chats = _selectedChats(visible);
    if (chats.isEmpty) return;
    final ids = chats.map((chat) => chat.id);

    if (action == SelectionAction.more) {
      // One chat: its own row menu, then back to a clean list.
      final chat = chats.single;
      _exitSelectMode();
      await _openRowMenu(chat);
      return;
    }

    setState(() => _bulkBusy = true);
    try {
      switch (action) {
        case SelectionAction.pin:
          final allPinned = chats.every((chat) => chat.isPinned);
          await _repository.setPinnedMany(ids, !allPinned);
        case SelectionAction.archive:
          final allArchived = chats.every((chat) => chat.isArchived);
          await _repository.setArchivedMany(ids, !allArchived);
        case SelectionAction.read:
          final anyUnread = chats.any(
            (chat) => chat.isUnread || chat.unreadCount > 0,
          );
          if (!anyUnread && !_canMarkUnread) {
            _showError('You are not allowed to mark chats as unread.');
            return;
          }
          await _repository.setUnreadMany(ids, !anyUnread);
        case SelectionAction.assign:
          final done = await _assignSelected(chats);
          if (!done) return;
        case SelectionAction.more:
          return;
      }
      if (mounted) _exitSelectMode();
    } catch (error) {
      _showError('Could not update the chats: $error');
    } finally {
      if (mounted && _selecting) setState(() => _bulkBusy = false);
    }
  }

  /// The same picker the thread uses, applied to every picked chat through
  /// the bulk RPC. False when the picker was dismissed.
  Future<bool> _assignSelected(List<Chat> chats) async {
    final members = await _assignments.members(
      alsoInclude: <String>{
        for (final chat in chats) chat.userId,
        for (final chat in chats) ?chat.assignedTo,
        widget.tenantContext.authUserId,
      },
      signedInUserId: widget.tenantContext.authUserId,
      signedInFallbackName: widget.tenantContext.email,
    );
    if (!mounted) return false;

    // A shared assignee is shown as current; a mixed selection shows none.
    final assignees = chats.map((chat) => chat.assignedTo).toSet();
    final current = assignees.length == 1 ? assignees.single : null;

    var moved = 0;
    final result = await showAssignChatSheet(
      context,
      members: members,
      assignedTo: current,
      onAssign: (userId) async {
        try {
          moved = await _assignments.assignMany(
            chats.map((chat) => chat.id),
            userId,
          );
          return true;
        } on ChatAssignmentException catch (error) {
          _showError(error.message);
          return false;
        }
      },
    );
    if (result == null) return false;
    _notify(
      '$moved chat${moved == 1 ? '' : 's'} '
      '${result.userId == null ? 'unassigned' : 'reassigned'}.',
    );
    return true;
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _openRowMenu(Chat chat) async {
    final action = await showChatRowMenu(
      context,
      chat: chat,
      canMarkUnread: _canMarkUnread,
    );
    if (action == null || !mounted) return;

    try {
      switch (action) {
        case ChatRowAction.archive:
          await _repository.setArchived(chat.id, !chat.isArchived);
        case ChatRowAction.pin:
          await _repository.setPinned(chat.id, !chat.isPinned);
        case ChatRowAction.unread:
          await _repository.setUnread(chat.id, !chat.isUnread);
        case ChatRowAction.labels:
          await _openTagPicker(
            chat,
            title: 'Labels',
            emptyMessage: 'No labels exist in this workspace yet.',
            options: <TagOption>[
              for (final label in _filterData.labels)
                TagOption(id: label.id, name: label.name, color: label.color),
            ],
            selected: (_filterData.labelIdsByChat[chat.id] ?? const <String>[])
                .toSet(),
            write: (id, on) => _tags.setLabel(
              chat.id,
              id,
              applied: on,
              chatOwnerId: chat.userId,
              authUserId: widget.tenantContext.authUserId,
            ),
            commit: (ids) => _filterData = _filterData.withChatTags(
              chatId: chat.id,
              labelIds: ids.toList(),
            ),
          );
        case ChatRowAction.notes:
          await _openNotes(chat);
        case ChatRowAction.products:
          await _openProducts(chat);
        case ChatRowAction.categories:
          await _openTagPicker(
            chat,
            title: 'Categories',
            emptyMessage: 'No categories exist in this workspace yet.',
            options: <TagOption>[
              for (final category in _filterData.categories)
                TagOption(
                  id: category.id,
                  name: category.name,
                  color: category.color,
                ),
            ],
            selected:
                (_filterData.categoryIdsByChat[chat.id] ?? const <String>[])
                    .toSet(),
            write: (id, on) => _tags.setCategory(
              chat.id,
              id,
              applied: on,
              chatOwnerId: chat.userId,
              authUserId: widget.tenantContext.authUserId,
            ),
            commit: (ids) => _filterData = _filterData.withChatTags(
              chatId: chat.id,
              categoryIds: ids.toList(),
            ),
          );
      }
    } catch (error) {
      _showError('Could not update chat: $error');
    }
  }

  /// The Products entry: one product per customer, so the sheet is a
  /// chooser — tapping the ticked one clears it.
  Future<void> _openProducts(Chat chat) async {
    final phone = chat.normalisedPhone;
    var current = _filterData.collectionProductIdByPhone[phone];

    await showChatTagsSheet(
      context,
      title: 'Products',
      emptyMessage: 'No products yet.',
      singleSelect: true,
      leadingIcon: Icons.inventory_2_outlined,
      options: <TagOption>[
        for (final product in _filterData.products)
          TagOption(id: product.id, name: product.title),
      ],
      selected: <String>{?current},
      onToggle: (id, on) async {
        try {
          if (on) {
            final product = _filterData.products.firstWhere((p) => p.id == id);
            await _products.assign(
              chatOwnerId: chat.userId,
              normalisedPhone: phone,
              productId: id,
              productTitle: product.title,
            );
            current = id;
          } else {
            await _products.remove(
              chatOwnerId: chat.userId,
              normalisedPhone: phone,
            );
            current = null;
          }
          return true;
        } on CustomerProductException catch (error) {
          _showError(error.message);
          return false;
        } catch (error) {
          _showError('Could not update the product: $error');
          return false;
        }
      },
    );

    if (mounted) {
      setState(() {
        _filterData = _filterData.withCollectionProduct(phone, current);
      });
    }
  }

  /// The Notes entry: the library with this customer's notes ticked, and a
  /// way to write a new one straight onto them.
  Future<void> _openNotes(Chat chat) async {
    final phone = chat.normalisedPhone;
    final contactId = _filterData.contactIdByPhone[phone];
    final authUserId = widget.tenantContext.authUserId;

    final result = await showChatNotesSheet(
      context,
      chatName: _filterData.nameFor(phone, chat.displayName),
      contactId: contactId,
      library: _filterData.notes,
      attached: contactId == null
          ? const <Note>[]
          : _filterData.notesByContactId[contactId] ?? const <Note>[],
      onToggle: (note, attach) async {
        try {
          if (attach) {
            await _notes.attach(
              authUserId: authUserId,
              contactId: contactId!,
              noteId: note.id,
            );
          } else {
            await _notes.detach(contactId: contactId!, noteId: note.id);
          }
          return true;
        } on NotesException catch (error) {
          _showError(error.message);
          return false;
        } catch (error) {
          _showError('Could not update the note: $error');
          return false;
        }
      },
      onCreate: () async {
        final draft = await showNewNoteSheet(
          context,
          suggestedTags: _filterData.noteTags,
        );
        if (draft == null) return null;
        try {
          return await _notes.create(
            authUserId: authUserId,
            text: draft.$1,
            tags: draft.$2,
            contactId: contactId,
          );
        } on NotesException catch (error) {
          _showError(error.message);
          return null;
        } catch (error) {
          _showError('Could not save the note: $error');
          return null;
        }
      },
    );

    if (result == null || !mounted) return;
    setState(() {
      var next = _filterData;
      if (result.created != null) next = next.withNote(result.created!);
      if (contactId != null) {
        next = next.withContactNotes(contactId, result.attached);
      }
      _filterData = next;
    });
  }

  /// Each toggle writes straight away; the row's dots follow only the rows
  /// that actually landed.
  Future<void> _openTagPicker(
    Chat chat, {
    required String title,
    required String emptyMessage,
    required List<TagOption> options,
    required Set<String> selected,
    required Future<void> Function(String id, bool applied) write,
    required void Function(Set<String> ids) commit,
  }) async {
    final applied = <String>{...selected};
    await showChatTagsSheet(
      context,
      title: title,
      emptyMessage: emptyMessage,
      options: options,
      selected: selected,
      onToggle: (id, on) async {
        try {
          await write(id, on);
          on ? applied.add(id) : applied.remove(id);
          return true;
        } on ChatTagException catch (error) {
          _showError(error.message);
          return false;
        } catch (error) {
          _showError('Could not update $title: $error');
          return false;
        }
      },
    );
    if (mounted) setState(() => commit(applied));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
      DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      ).millisecondsSinceEpoch,
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
    context.go(Routes.chat(chat.id), extra: chat.withPhoto(_photoFor(chat)));
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
    return PopScope(
      // Back leaves select mode before it leaves the screen.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelectMode();
      },
      child: Scaffold(
        backgroundColor: Wa.background,
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton(
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
            final visible = applyUsersFilter(
              ChatFilterEngine.apply(
                chats: scoped,
                data: _filterData,
                state: bucket == null ? _filters : ChatFilterState.initial,
                range: _rangeMs,
                scheduleIds: bucket == null ? null : _scheduled.bucket(bucket),
              ),
              selected: _isAdmin ? _userFilter : const <String>{},
              authUserId: widget.tenantContext.authUserId,
              isSuperAdmin: _isSuperAdmin,
            );

            int tabCount(ContactTab tab) => ChatFilterEngine.count(
              chats: scoped,
              data: _filterData,
              state: _filters.selectTab(tab),
              range: _rangeMs,
            );

            final picked = _selectedChats(visible);

            return Column(
              children: <Widget>[
                if (_selecting)
                  SelectionBar(
                    count: picked.length,
                    total: visible.length,
                    allPinned:
                        picked.isNotEmpty &&
                        picked.every((chat) => chat.isPinned),
                    allArchived:
                        picked.isNotEmpty &&
                        picked.every((chat) => chat.isArchived),
                    anyUnread: picked.any(
                      (chat) => chat.isUnread || chat.unreadCount > 0,
                    ),
                    busy: _bulkBusy,
                    onExit: _exitSelectMode,
                    onSelectAll: () => _selectAllOrNone(visible),
                    onAction: (action) => _onSelectionAction(action, visible),
                  )
                else
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
                    onMoreFilters: _filterDataLoading
                        ? null
                        : () => _openMoreFilters(scoped),
                    usersLabel: _isAdmin
                        ? usersFilterLabel(
                            _userFilter,
                            _isSuperAdmin
                                ? _superAdminOwners(scoped)
                                : _teamUsers,
                          )
                        : null,
                    usersActive: _userFilter.isNotEmpty,
                    onUsers:
                        _isAdmin ? () => _openUsersFilter(scoped) : null,
                    tenantContext: widget.tenantContext,
                    onRefresh: _refresh,
                    onSettings: () => showSettingsScreen(
                      context,
                      tenantContext: widget.tenantContext,
                      onSignOut: widget.onSignOut,
                    ),
                  ),
                Expanded(child: _body(snapshot, visible, scoped)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(
    AsyncSnapshot<List<Chat>> snapshot,
    List<Chat> visible,
    List<Chat> scoped,
  ) {
    final bucket = _scheduleBucket;
    if (snapshot.hasError) {
      return _ChatsError(message: snapshot.error.toString(), onRetry: _refresh);
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator(color: Wa.accent));
    }
    // WhatsApp's "Archived" row: on the plain All list it sits above the
    // first chat and opens the archive; inside the archive it becomes the way
    // back. It only appears when something is actually archived.
    final inArchive = _filters.tab == ContactTab.archived && bucket == null;
    final archivedCount = ChatFilterEngine.count(
      chats: scoped,
      data: _filterData,
      state: _filters.selectArchived(),
      range: _rangeMs,
    );
    final showArchiveRow =
        bucket == null &&
        _query.trim().isEmpty &&
        archivedCount > 0 &&
        (inArchive || (_filters.tab == ContactTab.all && !_filters.isNarrowed));
    final Widget? archiveRow = !showArchiveRow
        ? null
        : ArchivedRow(
            count: archivedCount,
            inArchive: inArchive,
            onTap: () => setState(() {
              _filters = inArchive
                  ? _filters.selectTab(ContactTab.all)
                  : _filters.selectArchived();
            }),
          );

    if (visible.isEmpty) {
      final empty = _EmptyChats(
        filters: _filters,
        query: _query,
        range: _range,
        scheduleBucket: _scheduleBucket,
        onClearFilters: _filters.isNarrowed
            ? () => setState(() => _filters = _filters.clearAll())
            : null,
      );
      if (archiveRow == null) return empty;
      return Column(
        children: <Widget>[
          archiveRow,
          Expanded(child: empty),
        ],
      );
    }

    final lead = archiveRow == null ? 0 : 1;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: visible.length + lead,
      itemBuilder: (context, index) {
        if (archiveRow != null && index == 0) return archiveRow;
        final chat = visible[index - lead];
        final phone = chat.normalisedPhone;
        return ChatListTile(
          chat: chat,
          subtitleStamp: TimeFormat.listStamp(chat.lastMessageAt),
          showDivider: index - lead != visible.length - 1,
          photoUrl: _photoFor(chat),
          name: _filterData.nameFor(phone, chat.displayName),
          labelColors: _filterData.labelColorsForChat(chat.id, phone),
          ownerLine: _ownerLineFor(chat),
          productName: _filterData.productNameForChat(
            phone,
            chat.lastAdHeadline,
          ),
          noteExcerpt: noteExcerpt(_filterData.latestNoteFor(phone)?.text),
          selecting: _selecting,
          selected: _selected.contains(chat.id),
          // In select mode a tap picks; otherwise it opens. A long press
          // starts selecting from that chat — the row menu now lives behind
          // the ⋮ in the selection bar.
          onTap: _selecting
              ? () => _toggleSelected(chat)
              : () => _openChat(chat),
          onLongPress: _selecting
              ? () => _toggleSelected(chat)
              : () => _enterSelectMode(chat),
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
    this.usersLabel,
    this.usersActive = false,
    this.onUsers,
    required this.tenantContext,
    required this.onRefresh,
    required this.onSettings,
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

  /// The Users chip — admins only, so null hides it.
  final String? usersLabel;
  final bool usersActive;
  final VoidCallback? onUsers;

  final TenantContext tenantContext;
  final VoidCallback onRefresh;

  /// The ⚙ beside Refresh: account, workspace, this device, sign out.
  final VoidCallback onSettings;

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
                  // The wordmark alone — it says "WOO Chat" itself, so the
                  // title beside it was saying it twice. 34px tall, which is
                  // the height the title line had.
                  Image.asset(
                    'assets/branding/app-logo.png',
                    height: 34,
                    fit: BoxFit.contain,
                    // The header still works without it.
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  const Spacer(),
                  // Users (admins only) and Refresh sit in the title row as
                  // plain icons; the account and Sign out moved to the nav
                  // bar's More, so nothing here needs a menu any more.
                  if (onUsers != null)
                    _HeaderIcon(
                      key: const ValueKey<String>('users-icon'),
                      icon: usersActive ? Icons.people : Icons.people_outline,
                      tooltip: usersLabel ?? 'Users',
                      active: usersActive,
                      onPressed: onUsers!,
                    ),
                  _HeaderIcon(
                    key: const ValueKey<String>('refresh-icon'),
                    icon: Icons.refresh,
                    tooltip: 'Refresh',
                    onPressed: onRefresh,
                  ),
                  _HeaderIcon(
                    key: const ValueKey<String>('settings-icon'),
                    icon: Icons.settings_outlined,
                    tooltip: 'Settings',
                    onPressed: onSettings,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
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
    final label =
        '${format.format(range.start)} - '
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
            const Icon(
              Icons.calendar_today_outlined,
              size: 13,
              color: Colors.white,
            ),
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
  const _Chip({required this.label, required this.active, required this.onTap});

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

/// One of the icons at the right of the title row, boxed at 36px so the
/// row keeps its height.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Drawn in the accent when the filter behind it is narrowing the list.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 22, color: active ? Wa.accent : Wa.icon),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp's Archived row. Above the list it opens the archive and shows how
/// many chats are in it; inside the archive it is the way back out.
class ArchivedRow extends StatelessWidget {
  const ArchivedRow({
    super.key,
    required this.count,
    required this.inArchive,
    required this.onTap,
  });

  final int count;
  final bool inArchive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Wa.divider, width: 0.5)),
          ),
          child: Row(
            children: <Widget>[
              // Centred under the 49px avatars so the label lines up with
              // the chat names beneath it.
              SizedBox(
                width: 49,
                child: Icon(
                  inArchive ? Icons.arrow_back : Icons.archive_outlined,
                  size: 24,
                  color: Wa.secondaryText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Archived',
                  style: TextStyle(
                    color: inArchive ? Wa.title : Wa.secondaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!inArchive)
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Wa.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
