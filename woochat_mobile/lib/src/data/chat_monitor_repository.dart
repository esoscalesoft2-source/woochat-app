import 'package:supabase_flutter/supabase_flutter.dart';

import 'edge_function_auth.dart';
import 'supabase_client.dart';

/// Raised when the Chat Monitor could not be read or a check not started.
class ChatMonitorException implements Exception {
  const ChatMonitorException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One of the business's monitor statuses: built in (renamable, can be off)
/// or its own. A [deadlineMinutes] makes it an issue someone has to fix.
class MonitorStatus {
  const MonitorStatus({
    required this.key,
    required this.name,
    required this.enabled,
    this.deadlineMinutes,
  });

  factory MonitorStatus.fromMap(Map<String, dynamic> map) => MonitorStatus(
    key: map['key'] as String,
    name: (map['name'] as String?) ?? map['key'] as String,
    enabled: map['enabled'] as bool? ?? true,
    deadlineMinutes: (map['deadline_minutes'] as num?)?.toInt(),
  );

  final String key;
  final String name;
  final bool enabled;
  final int? deadlineMinutes;
}

/// A check: started by the admin, followed while it works in the background.
class MonitorRun {
  const MonitorRun({
    required this.id,
    required this.startedAt,
    required this.finishedAt,
    required this.chatsTotal,
    required this.chatsChecked,
    this.issuesRaised,
    this.issuesFixed,
    this.issuesOpen,
    this.error,
  });

  factory MonitorRun.fromMap(Map<String, dynamic> map) => MonitorRun(
    id: map['id'] as String,
    startedAt: DateTime.parse(map['started_at'] as String),
    finishedAt: _time(map['finished_at']),
    chatsTotal: (map['chats_total'] as num?)?.toInt(),
    chatsChecked: (map['chats_checked'] as num?)?.toInt() ?? 0,
    issuesRaised: (map['issues_raised'] as num?)?.toInt(),
    issuesFixed: (map['issues_fixed'] as num?)?.toInt(),
    issuesOpen: (map['issues_open'] as num?)?.toInt(),
    error: map['error'] as String?,
  );

  final String id;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? chatsTotal;
  final int chatsChecked;
  final int? issuesRaised;
  final int? issuesFixed;
  final int? issuesOpen;
  final String? error;

  /// Still working — unless it has been "working" for 20 minutes, in which
  /// case it died and a new check may start, as on the web.
  bool get inProgress =>
      finishedAt == null &&
      DateTime.now().difference(startedAt) < const Duration(minutes: 20);
}

/// The monitor's latest read of one chat.
class MonitorChatRow {
  const MonitorChatRow({
    required this.chatId,
    required this.statuses,
    required this.severity,
    required this.name,
    this.reason,
    this.suggestion,
    this.score,
    this.mood,
    this.handledBy,
    this.analyzedAt,
  });

  factory MonitorChatRow.fromMap(Map<String, dynamic> map) => MonitorChatRow(
    chatId: map['chat_id'] as String,
    statuses: _strings(map['statuses']),
    severity: (map['severity'] as num?)?.toInt() ?? 0,
    name: _customer(map['chats']),
    reason: map['reason'] as String?,
    suggestion: map['suggestion'] as String?,
    score: (map['score'] as num?)?.toInt(),
    mood: map['mood'] as String?,
    handledBy: map['handled_by'] as String?,
    analyzedAt: _time(map['analyzed_at']),
  );

  final String chatId;
  final List<String> statuses;

  /// 0 fine · 1 worth a look · 2 today · 3 urgent.
  final int severity;
  final String name;
  final String? reason;
  final String? suggestion;

  /// The chance of a sale, in percent.
  final int? score;
  final String? mood;

  /// `sales_agent`, `chatbot` or `team`.
  final String? handledBy;
  final DateTime? analyzedAt;
}

enum IssueState { open, fixed, notNeeded }

/// Something the monitor raised that someone has to act on, by when.
class MonitorIssue {
  const MonitorIssue({
    required this.id,
    required this.chatId,
    required this.statusKeys,
    required this.state,
    required this.name,
    required this.raisedAt,
    this.assignee,
    this.suggestion,
    this.deadlineAt,
    this.fixedAt,
    this.checkedAt,
    this.verdict,
  });

  factory MonitorIssue.fromMap(Map<String, dynamic> map) {
    final keys = _strings(map['status_keys']);
    return MonitorIssue(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      // One issue per chat carries all its statuses; older rows only one.
      statusKeys: keys.isNotEmpty
          ? keys
          : <String>[map['status_key'] as String],
      state: switch (map['state']) {
        'fixed' => IssueState.fixed,
        'not_needed' => IssueState.notNeeded,
        _ => IssueState.open,
      },
      name: _customer(map['chats']),
      raisedAt: _time(map['raised_at']) ?? DateTime.now(),
      assignee: map['assignee'] as String?,
      suggestion: map['suggestion'] as String?,
      deadlineAt: _time(map['deadline_at']),
      fixedAt: _time(map['fixed_at']),
      checkedAt: _time(map['checked_at']),
      verdict: map['verdict'] as String?,
    );
  }

  final String id;
  final String chatId;
  final List<String> statusKeys;
  final IssueState state;
  final String name;
  final DateTime raisedAt;
  final String? assignee;
  final String? suggestion;
  final DateTime? deadlineAt;
  final DateTime? fixedAt;
  final DateTime? checkedAt;

  /// The AI's check of whether it was done.
  final String? verdict;

  bool isOverdue(DateTime now) =>
      state == IssueState.open &&
      deadlineAt != null &&
      !deadlineAt!.isAfter(now);
}

/// A teammate whose pending issues this person was given to see.
typedef TeammateAccess = ({String id, String name});

/// Reads the Chat Monitor the web app writes, and starts a check.
///
/// The same tables and functions as the website's Chat Monitor page; the
/// database decides how much of it each person sees (an admin all of it, a
/// team member the chats they hold and their own issues).
class ChatMonitorRepository {
  const ChatMonitorRepository();

  static const String _fn = 'chat-monitor';

  /// The admin's status list. The function makes the built-in ones the
  /// first time, so an admin goes through it; the team reads the table.
  Future<List<MonitorStatus>> statuses({
    required String ownerId,
    required bool isAdmin,
  }) async {
    try {
      if (isAdmin) {
        final response = await invokeEdgeFunction(
          _fn,
          body: <String, dynamic>{'action': 'init'},
        );
        final data = response.data;
        final list = data is Map ? data['statuses'] : null;
        return <MonitorStatus>[
          for (final row in (list as List? ?? const <dynamic>[]))
            if (row is Map)
              MonitorStatus.fromMap(Map<String, dynamic>.from(row)),
        ];
      }
      final rows =
          await db
                  .from('monitor_statuses')
                  .select('key, name, enabled, deadline_minutes')
                  .eq('owner_id', ownerId)
                  .order('sort')
              as List;
      return <MonitorStatus>[
        for (final row in rows.whereType<Map<String, dynamic>>())
          MonitorStatus.fromMap(row),
      ];
    } on FunctionException catch (error) {
      throw ChatMonitorException(_functionError(error));
    } on PostgrestException catch (error) {
      throw ChatMonitorException(error.message);
    }
  }

  Future<MonitorRun?> lastRun(String ownerId) async {
    final rows =
        await db
                .from('monitor_runs')
                .select(
                  'id, started_at, finished_at, chats_total, chats_checked, '
                  'issues_raised, issues_fixed, issues_open, error',
                )
                .eq('owner_id', ownerId)
                .order('started_at', ascending: false)
                .limit(1)
            as List;
    final row = rows.whereType<Map<String, dynamic>>().firstOrNull;
    return row == null ? null : MonitorRun.fromMap(row);
  }

  Future<List<MonitorChatRow>> chats(String ownerId) async {
    final rows =
        await db
                .from('monitor_chat_status')
                .select(
                  'chat_id, statuses, severity, reason, suggestion, score, mood, '
                  'handled_by, analyzed_at, chats(contact_name, contact_phone)',
                )
                .eq('owner_id', ownerId)
                .order('severity', ascending: false)
                .order('analyzed_at', ascending: false)
                .limit(500)
            as List;
    return <MonitorChatRow>[
      for (final row in rows.whereType<Map<String, dynamic>>())
        MonitorChatRow.fromMap(row),
    ];
  }

  /// Open issues, plus everything raised in the last 7 days. [me] narrows a
  /// team member to their own.
  Future<List<MonitorIssue>> issues(String ownerId, {String? me}) async {
    final since = DateTime.now()
        .subtract(const Duration(days: 7))
        .toUtc()
        .toIso8601String();
    var query = db
        .from('monitor_issues')
        .select(
          'id, chat_id, status_key, status_keys, assignee, suggestion, '
          'raised_at, deadline_at, state, checked_at, verdict, fixed_at, '
          'chats(contact_name, contact_phone)',
        )
        .eq('owner_id', ownerId);
    if (me != null) query = query.eq('assignee', me);
    final rows =
        await query
                .or('state.eq.open,raised_at.gte.$since')
                .order('raised_at', ascending: false)
                .limit(500)
            as List;
    return <MonitorIssue>[
      for (final row in rows.whereType<Map<String, dynamic>>())
        MonitorIssue.fromMap(row),
    ];
  }

  /// Teammates whose pending issues the admin let this person see.
  Future<List<TeammateAccess>> teammates() async {
    try {
      final rows = await db.rpc('monitor_my_access') as List? ?? const [];
      return <TeammateAccess>[
        for (final row in rows.whereType<Map<String, dynamic>>())
          (id: row['id'] as String, name: (row['name'] as String?) ?? '—'),
      ];
    } on PostgrestException {
      return const <TeammateAccess>[];
    }
  }

  Future<List<MonitorIssue>> issuesOf(String userId) async {
    final rows =
        await db.rpc('monitor_issues_of', params: {'p_user': userId})
            as List? ??
        const [];
    return <MonitorIssue>[
      for (final row in rows.whereType<Map<String, dynamic>>())
        MonitorIssue.fromMap(row),
    ];
  }

  /// Display names for the assignees an admin sees.
  Future<Map<String, String>> names(Iterable<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return const <String, String>{};
    try {
      final rows =
          await db
                  .from('profiles')
                  .select('user_id, first_name, last_name')
                  .inFilter('user_id', ids)
              as List;
      return <String, String>{
        for (final row in rows.whereType<Map<String, dynamic>>())
          row['user_id'] as String: <String?>[
            row['first_name'] as String?,
            row['last_name'] as String?,
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' '),
      };
    } on PostgrestException {
      return const <String, String>{};
    }
  }

  /// Starts a check in the background. False when one is already running.
  Future<bool> runNow() async {
    try {
      final response = await invokeEdgeFunction(
        _fn,
        body: <String, dynamic>{'action': 'run_now'},
      );
      final data = response.data;
      return !(data is Map && data['running'] == true);
    } on FunctionException catch (error) {
      throw ChatMonitorException(_functionError(error));
    }
  }

  /// "Take over": the chat and its issue become the caller's.
  Future<void> takeIssue(String issueId) async {
    try {
      await db.rpc('monitor_take_issue', params: {'p_issue': issueId});
    } on PostgrestException catch (error) {
      throw ChatMonitorException(error.message);
    }
  }

  static String _functionError(FunctionException error) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'The Chat Monitor did not answer (${error.status}).';
  }
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const <String>[];

String _customer(Object? chat) {
  if (chat is! Map) return 'Chat';
  final name = (chat['contact_name'] as String?)?.trim();
  if (name != null && name.isNotEmpty) return name;
  final phone = chat['contact_phone'] as String?;
  return phone == null || phone.isEmpty ? 'Chat' : '+$phone';
}
