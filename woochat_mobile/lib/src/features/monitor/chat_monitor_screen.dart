import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../data/chat_monitor_repository.dart';
import '../../models/tenant_context.dart';
import '../../theme/wa_colors.dart';
import '../chat/chat_route.dart';

/// Opens the Chat Monitor over the current screen.
Future<void> showChatMonitorScreen(
  BuildContext context, {
  required TenantContext tenantContext,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => ChatMonitorScreen(tenantContext: tenantContext),
    ),
  );
}

/// Chat Monitor, as on the website: an AI reviewer of the chats, run when the
/// admin taps Check chats. It gives each chat statuses with a reason and a
/// suggestion; a status with a deadline is an issue someone has to fix, by
/// when, with the AI's check of whether they did. It never messages anyone.
///
/// A team member sees the chats they hold and their own issues, read only —
/// plus a teammate's pending ones when the admin gave them that, with "Take
/// over". Settings stay on the website.
class ChatMonitorScreen extends StatefulWidget {
  const ChatMonitorScreen({
    super.key,
    required this.tenantContext,
    this.repository = const ChatMonitorRepository(),
  });

  final TenantContext tenantContext;
  final ChatMonitorRepository repository;

  @override
  State<ChatMonitorScreen> createState() => _ChatMonitorScreenState();
}

enum _IssueView { open, overdue, fixed }

class _ChatMonitorScreenState extends State<ChatMonitorScreen> {
  ChatMonitorRepository get _repo => widget.repository;

  bool get _isAdmin =>
      widget.tenantContext.role == AppRole.admin ||
      widget.tenantContext.role == AppRole.superAdmin;

  /// The admin's own monitor; a team member reads their admin's.
  String get _ownerId => _isAdmin
      ? widget.tenantContext.authUserId
      : widget.tenantContext.tenantAdminId;

  String? get _me => _isAdmin ? null : widget.tenantContext.authUserId;

  bool _loading = true;
  String? _error;
  List<MonitorStatus> _statuses = const [];
  List<MonitorChatRow> _rows = const [];
  List<MonitorIssue> _issues = const [];
  List<MonitorIssue> _theirIssues = const [];
  List<TeammateAccess> _access = const [];
  Map<String, String> _names = const {};
  MonitorRun? _run;

  bool _starting = false;
  String? _taking;
  _IssueView _view = _IssueView.open;
  String? _person;
  String? _statusFilter;
  int _minSeverity = 0;

  Timer? _poll;

  /// The run being followed, so its result is reported once when it ends.
  String? _watchingRun;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _repo.statuses(ownerId: _ownerId, isAdmin: _isAdmin),
        _repo.chats(_ownerId),
        _repo.issues(_ownerId, me: _me),
        _repo.lastRun(_ownerId),
        _isAdmin
            ? Future<List<TeammateAccess>>.value(const [])
            : _repo.teammates(),
      ]);
      final issues = results[2]! as List<MonitorIssue>;
      final access = results[4]! as List<TeammateAccess>;
      final theirs = <MonitorIssue>[
        for (final teammate in access) ...await _repo.issuesOf(teammate.id),
      ];
      final names = _isAdmin
          ? await _repo.names(issues.map((i) => i.assignee).whereType<String>())
          : const <String, String>{};
      if (!mounted) return;
      setState(() {
        _statuses = results[0]! as List<MonitorStatus>;
        _rows = results[1]! as List<MonitorChatRow>;
        _issues = issues;
        _run = results[3] as MonitorRun?;
        _access = access;
        _theirIssues = theirs;
        _names = names;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
    _schedulePoll();
  }

  /// Every 2 s while a check works, else every minute, as on the web.
  void _schedulePoll() {
    _poll?.cancel();
    final busy = _starting || (_run?.inProgress ?? false);
    _poll = Timer(
      busy ? const Duration(seconds: 2) : const Duration(seconds: 60),
      busy ? _followRun : _loadAll,
    );
  }

  Future<void> _followRun() async {
    try {
      final run = await _repo.lastRun(_ownerId);
      if (!mounted) return;
      setState(() => _run = run);
      if (run != null && run.finishedAt == null) _watchingRun = run.id;
      if (run != null && run.finishedAt != null && _watchingRun == run.id) {
        _watchingRun = null;
        setState(() => _starting = false);
        if (run.error != null) _notify(run.error!);
        _notify(
          'Checked ${run.chatsChecked} — ${run.issuesRaised ?? 0} new '
          'issue(s), ${run.issuesFixed ?? 0} fixed, '
          '${run.issuesOpen ?? 0} still open',
        );
        await _loadAll();
        return;
      }
    } catch (_) {
      // Try again on the next tick.
    }
    _schedulePoll();
  }

  Future<void> _checkChats() async {
    setState(() => _starting = true);
    try {
      final started = await _repo.runNow();
      if (!started) _notify('A check is already running');
      await _followRun();
    } catch (error) {
      if (!mounted) return;
      setState(() => _starting = false);
      _notify('$error');
    }
  }

  Future<void> _takeOver(MonitorIssue issue) async {
    setState(() => _taking = issue.id);
    try {
      await _repo.takeIssue(issue.id);
      _notify("${issue.name} is yours now — answer it like any of your chats");
      await _loadAll();
      if (mounted) _openChat(issue.chatId);
    } catch (error) {
      _notify('$error');
    } finally {
      if (mounted) setState(() => _taking = null);
    }
  }

  void _openChat(String chatId) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => ChatRoute(chatId: chatId)),
    );
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _statusName(String key) =>
      _statuses.where((s) => s.key == key).firstOrNull?.name ?? key;

  String _who(String? id) {
    if (id == null) return '—';
    if (_me != null && id == _me) return 'You';
    if (id == _ownerId) return _me != null ? 'Admin' : 'You (admin)';
    final name =
        _names[id] ?? _access.where((a) => a.id == id).firstOrNull?.name;
    return (name == null || name.isEmpty) ? '—' : name;
  }

  @override
  Widget build(BuildContext context) {
    final openIssues = <MonitorIssue>[
      ..._issues,
      ..._theirIssues,
    ].where((i) => i.state == IssueState.open).length;
    Widget tab(List<Widget> children) => RefreshIndicator(
      color: Wa.accent,
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: children,
      ),
    );

    // Two tabs, so the chats aren't buried under hundreds of issues.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Wa.background,
        appBar: AppBar(
          backgroundColor: Wa.background,
          foregroundColor: Wa.title,
          elevation: 0,
          title: const Text('Chat Monitor'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _loadAll,
            ),
          ],
          bottom: TabBar(
            indicatorColor: Wa.accent,
            labelColor: Wa.accent,
            unselectedLabelColor: Wa.secondaryText,
            dividerColor: Wa.divider,
            tabs: <Widget>[
              Tab(text: 'Issues to fix · $openIssues'),
              Tab(text: 'Chats · ${_rows.length}'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Wa.accent))
            : Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_error != null) _ErrorBox(message: _error!),
                        _CheckBar(
                          isAdmin: _isAdmin,
                          run: _run,
                          starting: _starting,
                          onCheck: _checkChats,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        tab(_issuesSection()),
                        tab(_chatsSection()),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ---- Issues to fix ---------------------------------------------------

  List<Widget> _issuesSection() {
    final now = DateTime.now();
    final all = <MonitorIssue>[..._issues, ..._theirIssues];
    final shownFor = _person ?? _me;
    final scoped = shownFor == null
        ? all
        : all.where((i) => i.assignee == shownFor).toList();
    final viewingTeammate = _me != null && _person != null && _person != _me;
    final canPick = _me == null || _access.isNotEmpty;

    bool inView(MonitorIssue i, _IssueView view) => switch (view) {
      _IssueView.open => i.state == IssueState.open,
      _IssueView.overdue => i.isOverdue(now),
      _IssueView.fixed => i.state == IssueState.fixed,
    };
    final list = scoped.where((i) => inView(i, _view)).toList();
    final people =
        _tallies(all, now).entries
            .where((e) => e.value.open + e.value.onTime + e.value.late > 0)
            .toList()
          ..sort(
            (a, b) => b.value.overdue != a.value.overdue
                ? b.value.overdue - a.value.overdue
                : b.value.open - a.value.open,
          );

    final title = viewingTeammate
        ? "${_who(_person)}'s pending issues"
        : _me != null
        ? 'Your issues to fix'
        : _person != null
        ? 'Issues to fix — ${_who(_person)}'
        : 'Issues to fix';

    return <Widget>[
      _SectionTitle(title),
      const SizedBox(height: 4),
      Text(
        viewingTeammate
            ? 'Take over any you can finish: the chat becomes yours, and so '
                  'does the issue.'
            : 'What has to be acted on, by when (team hours). The AI checks '
                  "each one from the reply and the customer's last message.",
        style: const TextStyle(color: Wa.secondaryText, fontSize: 12.5),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final view in _IssueView.values)
            _Pill(
              label:
                  '${switch (view) {
                    _IssueView.open => 'Open',
                    _IssueView.overdue => 'Overdue',
                    _IssueView.fixed => 'Fixed (7 days)',
                  }} · ${scoped.where((i) => inView(i, view)).length}',
              active: _view == view,
              onTap: () => setState(() => _view = view),
            ),
        ],
      ),
      if (people.isNotEmpty) ...<Widget>[
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (final entry in people)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _TallyChip(
                    name: _who(entry.key.isEmpty ? null : entry.key),
                    tally: entry.value,
                    selected: canPick && shownFor == entry.key,
                    onTap: !canPick
                        ? null
                        : () => setState(() {
                            if (_me != null) {
                              _person = entry.key == _me ? null : entry.key;
                            } else {
                              _person = _person == entry.key ? null : entry.key;
                            }
                          }),
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 10),
      if (list.isEmpty)
        _Empty(switch (_view) {
          _IssueView.fixed => 'Nothing fixed in the last 7 days.',
          _IssueView.overdue => 'Nothing overdue.',
          _IssueView.open => 'No open issues.',
        })
      else
        for (final issue in list)
          _IssueCard(
            issue: issue,
            statuses: issue.statusKeys.map(_statusName).join(' · '),
            who: _who(issue.assignee),
            now: now,
            canTakeOver: _me != null && issue.assignee != _me,
            taking: _taking == issue.id,
            onOpen: () => _openChat(issue.chatId),
            onTakeOver: () => _takeOver(issue),
          ),
    ];
  }

  // ---- Chats by status ---------------------------------------------------

  List<Widget> _chatsSection() {
    final counts = <String, int>{};
    for (final row in _rows) {
      for (final key in row.statuses) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    final shown = _rows
        .where(
          (r) =>
              (_statusFilter == null || r.statuses.contains(_statusFilter)) &&
              r.severity >= _minSeverity,
        )
        .toList();

    return <Widget>[
      Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'By status',
              style: TextStyle(color: Wa.secondaryText, fontSize: 13),
            ),
          ),
          PopupMenuButton<int>(
            initialValue: _minSeverity,
            color: Wa.sheet,
            onSelected: (value) => setState(() => _minSeverity = value),
            itemBuilder: (_) => <PopupMenuEntry<int>>[
              for (final (value, label) in _severityFilters)
                PopupMenuItem<int>(
                  value: value,
                  child: Text(label, style: const TextStyle(color: Wa.title)),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _severityFilters.firstWhere((f) => f.$1 == _minSeverity).$2,
                  style: const TextStyle(color: Wa.accent, fontSize: 13),
                ),
                const Icon(Icons.arrow_drop_down, color: Wa.accent),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 54,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: <Widget>[
            _CountChip(
              count: _rows.length,
              label: 'All chats',
              selected: _statusFilter == null,
              onTap: () => setState(() => _statusFilter = null),
            ),
            for (final status in _statuses.where((s) => s.enabled))
              _CountChip(
                count: counts[status.key] ?? 0,
                label: status.name,
                selected: _statusFilter == status.key,
                onTap: () => setState(
                  () => _statusFilter = _statusFilter == status.key
                      ? null
                      : status.key,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      if (shown.isEmpty)
        _Empty(
          _rows.isNotEmpty
              ? 'No chats with this status.'
              : _isAdmin
              ? 'Nothing yet — tap Check chats to review the chats with new '
                    'messages.'
              : 'Nothing for your chats yet — it fills in when your admin '
                    'runs a check.',
        )
      else
        for (final row in shown)
          _ChatCard(
            row: row,
            statuses: row.statuses.map(_statusName).toList(),
            onOpen: () => _openChat(row.chatId),
          ),
    ];
  }
}

const List<(int, String)> _severityFilters = <(int, String)>[
  (0, 'All severities'),
  (1, 'Worth a look +'),
  (2, 'Needs attention today +'),
  (3, 'Urgent only'),
];

const List<String> _severityNames = <String>['Fine', 'Look', 'Today', 'Urgent'];
const List<Color> _severityColors = <Color>[
  Wa.mutedText,
  Color(0xFF38BDF8),
  Wa.warning,
  Wa.scheduleFailed,
];

const Map<String, String> _handledBy = <String, String>{
  'sales_agent': 'Sales Agent',
  'chatbot': 'ChatBot AI',
  'team': 'Team',
};

final DateFormat _when = DateFormat('d MMM, h:mm a');

String _span(Duration d) {
  final m = d.inMinutes.abs().clamp(1, 1 << 30);
  if (m < 60) return '$m min';
  final rest = m % 60;
  return '${m ~/ 60} h${rest == 0 ? '' : ' $rest min'}';
}

/// "in 25 min" / "overdue 1 h 10 min" / "fixed on time", as on the web.
({String text, bool late}) _due(MonitorIssue i, DateTime now) {
  if (i.state == IssueState.fixed) {
    final late =
        i.deadlineAt != null &&
        i.fixedAt != null &&
        i.fixedAt!.isAfter(i.deadlineAt!);
    return (
      text: late
          ? 'fixed ${_span(i.fixedAt!.difference(i.deadlineAt!))} late'
          : 'fixed on time',
      late: late,
    );
  }
  if (i.state == IssueState.notNeeded) {
    return (text: 'no longer needed', late: false);
  }
  if (i.deadlineAt == null) return (text: '—', late: false);
  final left = i.deadlineAt!.difference(now);
  return left > Duration.zero
      ? (text: 'in ${_span(left)}', late: false)
      : (text: 'overdue ${_span(left)}', late: true);
}

class _Tally {
  int open = 0;
  int overdue = 0;
  int onTime = 0;
  int late = 0;
}

/// Per person, last 7 days: open, overdue, fixed on time, fixed late.
Map<String, _Tally> _tallies(List<MonitorIssue> issues, DateTime now) {
  final t = <String, _Tally>{};
  for (final i in issues) {
    final r = t.putIfAbsent(i.assignee ?? '', _Tally.new);
    if (i.state == IssueState.open) {
      r.open++;
      if (i.isOverdue(now)) r.overdue++;
    } else if (i.state == IssueState.fixed &&
        i.fixedAt != null &&
        now.difference(i.fixedAt!) <= const Duration(days: 7)) {
      if (i.deadlineAt != null && i.fixedAt!.isAfter(i.deadlineAt!)) {
        r.late++;
      } else {
        r.onTime++;
      }
    }
  }
  return t;
}

class _CheckBar extends StatelessWidget {
  const _CheckBar({
    required this.isAdmin,
    required this.run,
    required this.starting,
    required this.onCheck,
  });

  final bool isAdmin;
  final MonitorRun? run;
  final bool starting;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final run = this.run;
    final inProgress = run?.inProgress ?? false;
    final busy = starting || inProgress;
    final status = inProgress
        ? 'Checking… ${run!.chatsChecked}'
              '${run.chatsTotal != null ? ' of ${run.chatsTotal}' : ''}'
        : run != null
        ? 'Last checked ${_when.format(run.startedAt)} · '
              '${run.chatsChecked} chats'
        : 'Not checked yet';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Wa.header,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Wa.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  status,
                  style: const TextStyle(color: Wa.title, fontSize: 13),
                ),
              ),
              if (isAdmin)
                FilledButton.icon(
                  onPressed: busy ? null : onCheck,
                  style: FilledButton.styleFrom(
                    backgroundColor: Wa.accent,
                    foregroundColor: Wa.onAccent,
                    // The theme makes buttons full width; this one sits in a row.
                    minimumSize: const Size(0, 40),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Wa.onAccent,
                          ),
                        )
                      : const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Check chats'),
                ),
            ],
          ),
          if (inProgress && (run!.chatsTotal ?? 0) > 0) ...<Widget>[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (run.chatsChecked / run.chatsTotal!).clamp(0.0, 1.0),
              color: Wa.accent,
              backgroundColor: Wa.input,
            ),
          ],
          if (isAdmin && !inProgress && run?.error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              run!.error!,
              style: const TextStyle(color: Wa.warning, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.issue,
    required this.statuses,
    required this.who,
    required this.now,
    required this.canTakeOver,
    required this.taking,
    required this.onOpen,
    required this.onTakeOver,
  });

  final MonitorIssue issue;
  final String statuses;
  final String who;
  final DateTime now;
  final bool canTakeOver;
  final bool taking;
  final VoidCallback onOpen;
  final VoidCallback onTakeOver;

  @override
  Widget build(BuildContext context) {
    final due = _due(issue, now);
    final dueColor = due.late
        ? Wa.scheduleFailed
        : issue.state == IssueState.fixed
        ? Wa.accent
        : Wa.title;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Wa.header,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: due.late
              ? Wa.scheduleFailed.withValues(alpha: 0.5)
              : Wa.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      issue.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Wa.title,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: statuses,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: ' · $who',
                            style: const TextStyle(color: Wa.secondaryText),
                          ),
                        ],
                      ),
                      style: const TextStyle(color: Wa.title, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (canTakeOver)
                OutlinedButton.icon(
                  onPressed: taking || issue.state != IssueState.open
                      ? null
                      : onTakeOver,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Wa.accent,
                    side: const BorderSide(color: Wa.accent),
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 34),
                  ),
                  icon: taking
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.pan_tool_outlined, size: 16),
                  label: const Text('Take over'),
                )
              else
                TextButton.icon(
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                    foregroundColor: Wa.accent,
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 34),
                  ),
                  icon: const Icon(Icons.chat_outlined, size: 16),
                  label: const Text('Open'),
                ),
            ],
          ),
          if (issue.suggestion != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '→ ${issue.suggestion}',
              style: const TextStyle(color: Wa.accent, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(
                issue.state == IssueState.fixed
                    ? Icons.check_circle_outline
                    : due.late
                    ? Icons.warning_amber_rounded
                    : Icons.schedule,
                size: 15,
                color: dueColor,
              ),
              const SizedBox(width: 4),
              Text(due.text, style: TextStyle(color: dueColor, fontSize: 12.5)),
              if (issue.deadlineAt != null)
                Text(
                  '  ·  by ${_when.format(issue.deadlineAt!)}',
                  style: const TextStyle(color: Wa.mutedText, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            issue.verdict ?? 'Not checked yet',
            style: TextStyle(
              color: issue.verdict == null ? Wa.mutedText : Wa.secondaryText,
              fontSize: 12.5,
            ),
          ),
          if (issue.checkedAt != null)
            Text(
              'checked ${_when.format(issue.checkedAt!)}',
              style: const TextStyle(color: Wa.mutedText, fontSize: 11.5),
            ),
        ],
      ),
    );
  }
}

class _ChatCard extends StatelessWidget {
  const _ChatCard({
    required this.row,
    required this.statuses,
    required this.onOpen,
  });

  final MonitorChatRow row;
  final List<String> statuses;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final sev = row.severity.clamp(0, 3);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Wa.header,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Wa.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Wa.title,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _Badge(_severityNames[sev], _severityColors[sev]),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: <Widget>[
                  for (final status in statuses)
                    _Badge(status, Wa.secondaryText),
                ],
              ),
              if (row.reason != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  row.reason!,
                  style: const TextStyle(color: Wa.title, fontSize: 12.5),
                ),
              ],
              if (row.suggestion != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  '→ ${row.suggestion}',
                  style: const TextStyle(color: Wa.accent, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                <String>[
                  if (row.score != null) 'Chance ${row.score}%',
                  if (row.mood != null) row.mood!,
                  _handledBy[row.handledBy] ?? '—',
                  if (row.analyzedAt != null)
                    'checked ${_when.format(row.analyzedAt!)}',
                ].join('  ·  '),
                style: const TextStyle(color: Wa.mutedText, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Wa.title,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? Wa.chipActiveBackground : Wa.chipInactiveBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Wa.secondaryText,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

class _TallyChip extends StatelessWidget {
  const _TallyChip({
    required this.name,
    required this.tally,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final _Tally tally;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tally.overdue > 0
            ? Wa.scheduleFailed.withValues(alpha: 0.12)
            : Wa.header,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? Wa.accent
              : tally.overdue > 0
              ? Wa.scheduleFailed.withValues(alpha: 0.5)
              : Wa.divider,
          width: selected ? 2 : 1,
        ),
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: name,
              style: const TextStyle(
                color: Wa.title,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: '  ${tally.open} open',
              style: const TextStyle(color: Wa.secondaryText),
            ),
            if (tally.overdue > 0)
              TextSpan(
                text: '  ${tally.overdue} overdue',
                style: const TextStyle(color: Wa.scheduleFailed),
              ),
            TextSpan(
              text: '  ${tally.onTime} on time',
              style: const TextStyle(color: Wa.accent),
            ),
            if (tally.late > 0)
              TextSpan(
                text: '  ${tally.late} late',
                style: const TextStyle(color: Wa.warning),
              ),
          ],
        ),
        style: const TextStyle(fontSize: 12),
      ),
    ),
  );
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.count,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int count;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: count == 0 && !selected ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Wa.accentSoft : Wa.header,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Wa.accent : Wa.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '$count',
                style: const TextStyle(
                  color: Wa.title,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Wa.secondaryText, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Wa.secondaryText, fontSize: 13),
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Wa.warningBackground,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      message,
      style: const TextStyle(color: Wa.warning, fontSize: 12.5),
    ),
  );
}
