import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'edge_function_auth.dart';
import 'supabase_client.dart';

/// Raised when a call could not be placed, checked or ended. [code] is
/// Meta's error code when Meta was the one refusing.
class CallException implements Exception {
  const CallException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
}

/// Whether the business may ring this customer right now, per Meta.
class CallPermission {
  const CallPermission({
    required this.status,
    required this.canRequest,
    this.expiresAt,
  });

  /// `permanent`, `temporary`, `none`, or whatever Meta says.
  final String status;

  /// Whether a "may we call you?" message can be sent now (Meta allows one
  /// a day, two a week).
  final bool canRequest;
  final DateTime? expiresAt;

  bool get granted => status == 'permanent' || status == 'temporary';

  factory CallPermission.fromMap(Map<String, dynamic> map) {
    final exp = map['expires_at'];
    return CallPermission(
      status: (map['status'] ?? 'none').toString(),
      canRequest: map['can_request'] == true,
      expiresAt: exp is num
          ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000)
          : null,
    );
  }
}

/// A row of `calls`, as the app follows it.
class CallRow {
  const CallRow({
    required this.id,
    required this.status,
    this.chatId = '',
    this.direction = 'outbound',
    this.answerSdp,
    this.offerSdp,
    this.outcome,
    this.durationSeconds,
  });

  final String id;
  final String chatId;

  /// `inbound` when the customer called us.
  final String direction;

  /// ringing | pre_accepted | accepted | ended | declined | missed | failed
  final String status;

  /// Outbound: the customer's answer once they pick up.
  final String? answerSdp;

  /// Inbound: the customer's offer, to answer.
  final String? offerSdp;
  final String? outcome;
  final int? durationSeconds;

  bool get isInbound => direction == 'inbound';
  bool get isRinging => status == 'ringing';

  bool get isOver =>
      status == 'ended' ||
      status == 'declined' ||
      status == 'missed' ||
      status == 'failed';

  factory CallRow.fromMap(Map<String, dynamic> map) {
    final payload = map['raw_payload'];
    return CallRow(
      id: map['id'].toString(),
      chatId: (map['chat_id'] ?? '').toString(),
      direction: (map['direction'] ?? 'outbound').toString(),
      status: (map['status'] ?? 'ringing').toString(),
      answerSdp: payload is Map ? payload['answer_sdp'] as String? : null,
      offerSdp: payload is Map ? payload['offer_sdp'] as String? : null,
      outcome: map['outcome'] as String?,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt(),
    );
  }
}

/// The app's side of a WhatsApp call: everything goes through call-router,
/// which holds the WhatsApp token and talks to Meta. Audio never comes
/// this way — that is WebRTC between the device and WhatsApp.
class CallsRepository {
  const CallsRepository();

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final FunctionResponse response;
    try {
      response = await invokeEdgeFunction(Db.callRouterFn, body: body);
    } on EdgeFunctionAuthException catch (error) {
      throw CallException(error.message);
    } on FunctionException catch (error) {
      throw CallException(
        _reason(error.details) ?? 'call-router refused (${error.reasonPhrase}).',
        code: _code(error.details),
      );
    }
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const CallException('call-router returned nothing readable.');
    }
    if (data['error'] != null) {
      throw CallException(data['error'].toString(), code: _code(data));
    }
    return data;
  }

  static String? _reason(Object? data) {
    if (data is! Map) return null;
    final error = data['error'] ?? data['message'];
    return error is String && error.isNotEmpty ? error : null;
  }

  static int? _code(Object? data) =>
      data is Map ? (data['code'] as num?)?.toInt() : null;

  Future<CallPermission> permission(String chatId) async =>
      CallPermission.fromMap(
        await _call(<String, dynamic>{
          'action': 'permission_status',
          'chat_id': chatId,
        }),
      );

  /// Sends WhatsApp's "may we call you?" message. Needs the 24-hour window
  /// open, and Meta allows one a day.
  Future<void> requestPermission(String chatId, {String? text}) => _call(
        <String, dynamic>{
          'action': 'request_permission',
          'chat_id': chatId,
          'text': ?text,
        },
      );

  /// Places the call. Returns the `calls` row id to follow.
  Future<String> start({required String chatId, required String sdp}) async {
    final data = await _call(<String, dynamic>{
      'action': 'start',
      'chat_id': chatId,
      'sdp': sdp,
    });
    return data['call_id'].toString();
  }

  /// Answering a customer's call, in Meta's two steps: the answer goes up
  /// with pre_accept while it still rings (media path ready, no clipped
  /// first word), then accept.
  Future<void> preAccept({
    required String chatId,
    required String callId,
    required String sdp,
  }) =>
      _call(<String, dynamic>{
        'action': 'pre_accept',
        'chat_id': chatId,
        'call_id': callId,
        'sdp': sdp,
      });

  Future<void> accept({
    required String chatId,
    required String callId,
    required String sdp,
  }) =>
      _call(<String, dynamic>{
        'action': 'accept',
        'chat_id': chatId,
        'call_id': callId,
        'sdp': sdp,
      });

  Future<void> reject({required String chatId, required String callId}) =>
      _call(<String, dynamic>{
        'action': 'reject',
        'chat_id': chatId,
        'call_id': callId,
      });

  /// Every call that is ringing right now, as rows come and go — the
  /// customer-initiated ones are what the app rings on. RLS keeps it to
  /// chats the signed-in user can see.
  Stream<List<CallRow>> watchRinging() => db
      .from(Db.calls)
      .stream(primaryKey: <String>['id'])
      .eq('status', 'ringing')
      .map((rows) => rows.map(CallRow.fromMap).toList());

  Future<void> terminate({required String chatId, required String callId}) =>
      _call(<String, dynamic>{
        'action': 'terminate',
        'chat_id': chatId,
        'call_id': callId,
      });

  /// The row as it changes: ringing → accepted (with the SDP answer) → over.
  Stream<CallRow> watch(String callId) => db
      .from(Db.calls)
      .stream(primaryKey: <String>['id'])
      .eq('id', callId)
      .map((rows) => rows.map(CallRow.fromMap).toList())
      .where((rows) => rows.isNotEmpty)
      .map((rows) => rows.first);
}
