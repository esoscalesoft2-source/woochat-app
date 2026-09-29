import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../data/calls_repository.dart';
import '../../data/supabase_client.dart';
import '../../models/chat.dart';
import '../../models/tenant_context.dart';
import 'call_media.dart';
import 'call_screen.dart';
import 'call_session.dart';

/// How long after a customer starts calling this user's phone should
/// ring — or null for never.
///
/// The agent the chat is assigned to rings at once. The admin rings too,
/// but only after [adminBackupDelay], and only if the call is still
/// unanswered by then: they are the backup for an agent who is away, not
/// a second phone on every call. An unassigned chat is the admin's, so it
/// rings them at once. Other staff can see the row but stay quiet.
Duration? ringDelay({
  required TenantContext me,
  required String? assignedTo,
}) {
  final isAdmin = me.isTenantOwner ||
      me.role == AppRole.admin ||
      me.role == AppRole.superAdmin;
  if (assignedTo == null || assignedTo.isEmpty) {
    return isAdmin ? Duration.zero : null;
  }
  if (assignedTo == me.authUserId) return Duration.zero;
  return isAdmin ? adminBackupDelay : null;
}

/// Long enough for an agent at their desk to pick up; short enough that a
/// customer has not yet given up.
const Duration adminBackupDelay = Duration(seconds: 12);

/// Kept for callers that only need yes/no.
bool shouldRing({required TenantContext me, required String? assignedTo}) =>
    ringDelay(me: me, assignedTo: assignedTo) != null;

/// Makes the app ring. Sits above the signed-in screens and follows the
/// `calls` rows that are ringing; a customer-initiated one for a chat this
/// user should take opens the call screen on top of whatever they are
/// doing, with Accept and Decline. One at a time — a second caller while
/// one is on screen is left to ring out (they are told "missed").
///
/// Only while the app is open. Ringing a phone whose app is closed needs a
/// push notification, which is its own piece of work.
class IncomingCallWatcher extends StatefulWidget {
  const IncomingCallWatcher({
    super.key,
    required this.tenantContext,
    required this.child,
    this.repository = const CallsRepository(),
    this.loadChat,
    this.isRinging,
    this.mediaFactory,
  });

  final TenantContext tenantContext;
  final Widget child;
  final CallsRepository repository;

  /// Reads the chat a ringing row belongs to (name, assignment). Null uses
  /// the database; tests hand in their own.
  final Future<Chat?> Function(String chatId)? loadChat;

  /// Whether a call is still unanswered, asked before the backup rings.
  final Future<bool> Function(String callId)? isRinging;
  final CallMedia Function()? mediaFactory;

  @override
  State<IncomingCallWatcher> createState() => _IncomingCallWatcherState();
}

class _IncomingCallWatcherState extends State<IncomingCallWatcher> {
  StreamSubscription<List<CallRow>>? _sub;

  /// Rows already put on screen (or passed over), so a Realtime redraw of
  /// the same ringing row does not ring twice.
  final _seen = <String>{};
  bool _onScreen = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.repository.watchRinging().listen(_onRinging, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onRinging(List<CallRow> rows) async {
    for (final row in rows) {
      if (!row.isInbound || !row.isRinging || _seen.contains(row.id)) continue;
      _seen.add(row.id);
      if (_onScreen) continue;

      final chat = await (widget.loadChat ?? _loadChat)(row.chatId);
      if (!mounted || chat == null) continue;
      final delay = ringDelay(me: widget.tenantContext, assignedTo: chat.assignedTo);
      if (delay == null) continue;
      if (delay > Duration.zero) {
        // The backup: wait, then ring only if nobody has taken it.
        await Future<void>.delayed(delay);
        if (!mounted || _onScreen) continue;
        if (!await _stillRinging(row.id)) continue;
        if (!mounted) continue;
      }

      _onScreen = true;
      unawaited(HapticFeedback.vibrate());
      final session = CallSession.incoming(
        row: row,
        repository: widget.repository,
        media: (widget.mediaFactory ?? WebRtcCallMedia.new)(),
      );
      await showCallScreen(
        context,
        chat: chat,
        name: chat.displayName,
        session: session,
      );
      _onScreen = false;
    }
  }

  Future<bool> _stillRinging(String callId) async {
    final check = widget.isRinging ?? _isRinging;
    try {
      return await check(callId);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _isRinging(String callId) async {
    final row = await db
        .from(Db.calls)
        .select('status')
        .eq('id', callId)
        .maybeSingle();
    return row?['status'] == 'ringing';
  }

  static Future<Chat?> _loadChat(String chatId) async {
    final row = await db.from(Db.chats).select().eq('id', chatId).maybeSingle();
    return row == null ? null : Chat.fromMap(row);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
