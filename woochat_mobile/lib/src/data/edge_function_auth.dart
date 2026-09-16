import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// What the server says when the session behind a token is gone for good.
const String kSessionEndedMessage =
    'Your session has ended, so you were signed out. Sign in again to '
    'continue.';

/// Raised when an edge function cannot be called because there is no usable
/// session to call it with.
class EdgeFunctionAuthException implements Exception {
  const EdgeFunctionAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Every JWT carries a `sub` claim naming the signed-in user; the anon key,
/// which is also a JWT, does not. `whatsapp-send` reads `sub` and answers
/// `{"error":"Unauthorized"}` when it is missing.
bool jwtHasSubject(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return false;
  try {
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    final decoded = String.fromCharCodes(base64Decode(payload));
    // Cheap enough to read without a JSON parse, and never throws on a
    // payload shaped unexpectedly.
    return RegExp(r'"sub"\s*:\s*"[^"]+"').hasMatch(decoded);
  } catch (_) {
    return false;
  }
}

/// The headers an edge-function call must carry.
///
/// The Supabase client builds its Authorization header ONCE, when it is
/// constructed — which is before sign-in — and hands that copy to the
/// functions client. `AuthHttpClient` only fills the header in when it is
/// absent (`putIfAbsent`), so it never corrects the stale one, and every
/// function call goes out signed with the anon key for the life of the app.
/// An anon-key JWT has no `sub`, which is exactly what the send function
/// rejects as Unauthorized.
///
/// Passing the header explicitly on each `invoke` overrides it, because
/// `invoke`'s own headers are merged over the client's.
Future<Map<String, String>> edgeFunctionHeaders() async {
  var session = db.auth.currentSession;

  // A session that has just expired is refreshed rather than failed — the
  // client does this on its own schedule, which a send can easily outrun.
  if (session != null && session.isExpired) {
    try {
      session = (await db.auth.refreshSession()).session;
    } on AuthException {
      session = null;
    }
  }

  final token = session?.accessToken;
  if (token == null || token.isEmpty || !jwtHasSubject(token)) {
    throw const EdgeFunctionAuthException(
      'Your session has expired. Sign out and sign in again, then retry.',
    );
  }

  return <String, String>{'Authorization': 'Bearer $token'};
}

/// Calls an edge function as the signed-in user, surviving the one thing
/// that used to surface as a mid-conversation "unauthorized".
///
/// The access token lives an hour, but the SESSION behind it can end sooner —
/// the server hard-stops every session at its timebox — and an edge function
/// checks the session, not just the token. So a 401 here does not mean the
/// call was wrong; it means the token is stale. The remedy is a refresh:
///
///   • the refresh works → the call is retried once with the new token,
///     and nobody notices;
///   • the refresh is refused (`session_expired`) → the SDK removes the
///     session and emits a signed-out event, the login screen says why, and
///     the message is marked with the same reason.
///
/// Every function call goes through here so the rule lives in one place.
Future<FunctionResponse> invokeEdgeFunction(
  String name, {
  required Map<String, dynamic> body,
}) async {
  Future<FunctionResponse> call() async => db.functions.invoke(
        name,
        headers: await edgeFunctionHeaders(),
        body: body,
      );

  try {
    return await call();
  } on FunctionException catch (error) {
    if (error.status != 401) rethrow;
  }

  // 401: the token no longer names a live session. A refresh either mends
  // it or ends it — and ending it here is the SDK's own signed-out path, so
  // the app leaves cleanly rather than failing send after send.
  try {
    await db.auth.refreshSession();
  } on AuthException {
    throw const EdgeFunctionAuthException(kSessionEndedMessage);
  }

  try {
    return await call();
  } on FunctionException catch (error) {
    if (error.status == 401) {
      throw const EdgeFunctionAuthException(kSessionEndedMessage);
    }
    rethrow;
  }
}
