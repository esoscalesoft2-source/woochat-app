import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'supabase_client.dart';

/// Email + password auth against the existing Supabase project.
class AuthRepository {
  const AuthRepository();

  Session? get currentSession => db.auth.currentSession;

  User? get currentUser => db.auth.currentUser;

  Stream<AuthState> get onAuthStateChange => db.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    await db.auth.signInWithPassword(email: email.trim(), password: password);
  }

  /// Creates a new account.
  ///
  /// Returns true when Supabase issued a session immediately. When it returns
  /// false the project has email confirmation enabled, so the user must click
  /// the link in their inbox before they can sign in.
  ///
  /// A brand new user has no row linking them to a tenant, so until an
  /// administrator assigns one they will land on the "no workspace" screen.
  /// [profile] is written to `auth.users.raw_user_meta_data` — Supabase's
  /// built-in place for profile fields, so no table or column is added.
  Future<bool> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? profile,
  }) async {
    final response = await db.auth.signUp(
      email: email.trim(),
      password: password,
      data: profile,
    );
    return response.session != null;
  }

  /// Sends the Supabase password recovery email.
  Future<void> sendPasswordReset(String email) =>
      db.auth.resetPasswordForEmail(email.trim());

  /// Signs THIS device out. Supabase's default scope is global — it revokes
  /// every session the user has, so a Sign out on the website was logging
  /// the phone out too, which the phone then reported as "your session
  /// expired". Local scope ends only this device's session.
  Future<void> signOut() => db.auth.signOut(scope: SignOutScope.local);

  /// Makes a saved account the one in use, from its refresh token. Supabase
  /// issues a fresh pair and emits a signed-in event for that user.
  Future<void> switchTo(String refreshToken) async {
    await db.auth.setSession(refreshToken);
  }

  /// Ends a saved account that is not the one in use, without touching the
  /// session that is: trade its refresh token for an access token, then sign
  /// that one out (this device only). Best effort — if it fails the token
  /// just lapses on its own.
  Future<void> revoke(String refreshToken) async {
    final base = Env.supabaseUrl;
    final headers = <String, String>{
      'apikey': Env.supabaseAnonKey,
      'Content-Type': 'application/json',
    };
    try {
      final token = await http.post(
        Uri.parse('$base/auth/v1/token?grant_type=refresh_token'),
        headers: headers,
        body: jsonEncode(<String, String>{'refresh_token': refreshToken}),
      );
      if (token.statusCode != 200) return;
      final access = (jsonDecode(token.body) as Map)['access_token'];
      if (access is! String) return;
      await http.post(
        Uri.parse('$base/auth/v1/logout?scope=local'),
        headers: <String, String>{
          ...headers,
          'Authorization': 'Bearer $access',
        },
      );
    } catch (_) {
      // Offline or refused: nothing more to do.
    }
  }
}
