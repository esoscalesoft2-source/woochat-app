import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Email + password auth against the existing Supabase project.
class AuthRepository {
  const AuthRepository();

  Session? get currentSession => db.auth.currentSession;

  User? get currentUser => db.auth.currentUser;

  Stream<AuthState> get onAuthStateChange => db.auth.onAuthStateChange;

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await db.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
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
}
