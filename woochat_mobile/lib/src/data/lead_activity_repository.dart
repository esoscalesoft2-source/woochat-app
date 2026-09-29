import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'supabase_client.dart';

/// One move of a lead between pipeline stages, as the contact page lists it.
///
/// Stages are already turned into their board labels ("Callback", not
/// "discussion") and the mover into a name, so the page has nothing to look
/// up — the same shape the web's Lead activity panel renders.
class LeadStageEvent {
  const LeadStageEvent({
    required this.id,
    required this.from,
    required this.to,
    required this.at,
    required this.by,
    required this.isBaseline,
  });

  final String id;

  /// The stage it left. Null on a baseline row, where nobody recorded it.
  final String? from;
  final String to;
  final DateTime at;

  /// Who moved it. Null when nothing was pressed — the callback cron
  /// returned it — which the page says outright as "automatic".
  final String? by;

  /// Seeded for a lead that moved before logging began: where it stood, as
  /// at roughly when, with no observed transition.
  final bool isBaseline;

  bool get isAutomatic => !isBaseline && by == null;
}

/// Raised when the history could not be read.
class LeadActivityException implements Exception {
  const LeadActivityException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The pipeline history behind a chat: `lead_stage_events` for its lead(s),
/// which a database trigger writes on every stage change — a drag on the
/// board, a dialog, a bulk action, the cron that returns due callbacks —
/// so it is the same history whichever screen made the move.
///
/// Read-only by design: there is no insert policy on that table, and history
/// nobody can edit is the point.
class LeadActivityRepository {
  const LeadActivityRepository();

  /// Newest first. Empty when the chat has no lead, or its lead has not
  /// moved since logging began.
  Future<List<LeadStageEvent>> forChat(String chatId) async {
    try {
      final leadIds = await _leadIdsFor(chatId);
      if (leadIds.isEmpty) return const <LeadStageEvent>[];

      final rows = await db
          .from(Db.leadStageEvents)
          .select(
            'id, from_status, to_status, changed_by, created_at, is_baseline',
          )
          .inFilter('lead_id', leadIds)
          .order('created_at', ascending: false) as List<dynamic>;
      final events = rows.whereType<Map<String, dynamic>>().toList();
      if (events.isEmpty) return const <LeadStageEvent>[];

      // Only fetched once there is something to label. Both are small and
      // independent, so they go out together.
      final (labels, names) = await (_stageLabels(), _memberNames()).wait;

      return <LeadStageEvent>[
        for (final row in events) ?_parse(row, labels: labels, names: names),
      ];
    } on PostgrestException catch (error) {
      throw LeadActivityException(
        'Could not load the lead activity: ${error.message}',
      );
    }
  }

  /// A chat normally has one lead; the unique key is (user_id, chat_id), so
  /// take every id rather than assume.
  Future<List<String>> _leadIdsFor(String chatId) async {
    final rows = await db
        .from(Db.leads)
        .select('id')
        .eq('chat_id', chatId) as List<dynamic>;
    return <String>[
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (row['id'] != null) row['id'].toString(),
    ];
  }

  /// Stage value → board label, from the tenant's own pipeline. Admins
  /// rename columns, so the stored value is not what the board calls it.
  Future<Map<String, String>> _stageLabels() async {
    final rows = await db
        .from(Db.leadPipelineStages)
        .select('value, label')
        .eq('pipeline_type', 'lead') as List<dynamic>;
    return <String, String>{
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (row['value'] != null)
          row['value'].toString(): (row['label'] as String? ?? '').trim(),
    };
  }

  /// user_id → display name for the tenant's members, the same RPC the web
  /// attributes a move with.
  Future<Map<String, String>> _memberNames() async {
    final rows = await db.rpc<dynamic>(Db.listTenantMemberNamesFn);
    if (rows is! List) return const <String, String>{};
    return <String, String>{
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (row['user_id'] != null)
          row['user_id'].toString(): (row['full_name'] as String? ?? '').trim(),
    };
  }

  static LeadStageEvent? _parse(
    Map<String, dynamic> row, {
    required Map<String, String> labels,
    required Map<String, String> names,
  }) {
    final at = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final to = row['to_status']?.toString();
    if (at == null || to == null) return null;

    final by = row['changed_by']?.toString();
    return LeadStageEvent(
      id: row['id'].toString(),
      from: row['from_status'] == null
          ? null
          : stageLabel(row['from_status'].toString(), labels),
      to: stageLabel(to, labels),
      at: at.toLocal(),
      // A mover with no name on file is still a person, not the cron.
      by: by == null ? null : (names[by]?.isNotEmpty ?? false ? names[by] : 'User'),
      isBaseline: row['is_baseline'] == true,
    );
  }

  /// The board's name for a stored stage value.
  ///
  /// 'new' is a real status but not a pipeline stage — the board folds it
  /// into the first column. It is kept as its own name rather than
  /// relabelled "Lead": they are different statuses, and a history that
  /// blurs them is not one. A stage since deleted falls back to its value.
  static String stageLabel(String value, Map<String, String> labels) {
    if (value == 'new') return 'New';
    final label = labels[value];
    return (label == null || label.isEmpty) ? value : label;
  }
}
