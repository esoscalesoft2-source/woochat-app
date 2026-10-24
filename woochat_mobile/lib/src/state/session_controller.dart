import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/account_store.dart';
import '../data/approved_templates_cache.dart';
import '../data/auth_repository.dart';
import '../data/tenant_repository.dart';
import '../models/tenant_context.dart';

enum SessionStatus {
  /// Before the first auth check has completed.
  unknown,
  signedOut,

  /// Signed in; resolving tenant + role.
  resolving,

  /// Signed in with a resolved tenant.
  ready,

  /// Signed in but the tenant could not be resolved.
  failed,
}

/// Whether an auth event should change who the app thinks is signed in.
///
/// A null session only means "signed out" when Supabase says so explicitly.
/// A dropped or slow token refresh can surface as a null session on other
/// events — acting on those would throw away a perfectly good session and
/// bounce a signed-in user to the login screen mid-conversation. The web app
/// applies exactly this rule (`shouldApplyAuthEvent`).
bool shouldApplyAuthEvent(AuthChangeEvent event, Session? session) =>
    session != null || event == AuthChangeEvent.signedOut;

/// Single source of truth for "who is signed in and which tenant are they".
///
/// The router listens to this to decide where the user is allowed to be, and
/// the data screens read [tenantContext] from it.
class SessionController extends ChangeNotifier {
  SessionController({
    AuthRepository? auth,
    TenantRepository? tenants,
    AccountStore? accounts,
  }) : _auth = auth ?? const AuthRepository(),
       _tenants = tenants ?? const TenantRepository(),
       _accounts = accounts ?? AccountStore.instance;

  final AuthRepository _auth;
  final TenantRepository _tenants;
  final AccountStore _accounts;

  /// Every account signed in on this phone, the one in use among them.
  List<SavedAccount> _saved = const <SavedAccount>[];
  List<SavedAccount> get savedAccounts => _saved;

  /// True while the login screen is open to add another account; the
  /// router lets a signed-in user see it only then.
  bool _addingAccount = false;
  bool get addingAccount => _addingAccount;

  /// Set while one account signs out and the next takes over, so the gap
  /// between them shows a loader instead of the login screen.
  bool _handingOver = false;

  StreamSubscription<AuthState>? _subscription;
  String? _userId;

  SessionStatus _status = SessionStatus.unknown;
  TenantContext? _tenantContext;
  String? _error;
  String? _signOutNotice;

  SessionStatus get status => _status;
  TenantContext? get tenantContext => _tenantContext;
  String? get error => _error;

  /// Why the user found themselves on the login screen without tapping Sign
  /// out — so an expired session says so instead of looking like a bug.
  /// Null after a deliberate sign-out or a fresh start.
  String? get signOutNotice => _signOutNotice;

  /// Reads the notice once, for the login screen to show, and clears it.
  String? takeSignOutNotice() {
    final notice = _signOutNotice;
    _signOutNotice = null;
    return notice;
  }

  bool get isSignedOut => _status == SessionStatus.signedOut;
  bool get isReady => _status == SessionStatus.ready;

  /// Begins watching Supabase auth. Call once, at app start.
  void start() {
    _subscription = _auth.onAuthStateChange.listen(
      _onAuthState,
      // A refresh that failed for a retryable reason (offline, 5xx) arrives
      // here as a stream error, not an event. The SDK keeps the session and
      // tries again on its next tick, so nothing changes on this side — but
      // without a handler the error is unhandled and the subscription dies.
      onError: (Object error, StackTrace stack) {
        debugPrint('Auth stream error (session kept): $error');
      },
    );

    final session = _auth.currentSession;
    _userId = session?.user.id;
    unawaited(_remember(session));
    if (session == null) {
      _set(SessionStatus.signedOut);
    } else {
      unawaited(_resolveTenant());
    }
  }

  void _onAuthState(AuthState state) {
    if (!shouldApplyAuthEvent(state.event, state.session)) return;

    // Every token event: keep this account's latest refresh token, so a
    // switch back to it later still works.
    unawaited(_remember(state.session));

    // Signing in to the account already in use, from Add account.
    if (_addingAccount && state.event == AuthChangeEvent.signedIn) {
      _addingAccount = false;
      notifyListeners();
    }

    final userId = state.session?.user.id;
    // Ignore token refreshes for the same user.
    if (userId == _userId && _status != SessionStatus.unknown) return;
    _userId = userId;

    // A different account: drop the old tenant at once, so no screen keeps
    // showing the last workspace while the new one resolves.
    _tenantContext = null;
    _error = null;

    if (userId == null) {
      if (_handingOver) {
        _set(SessionStatus.resolving);
        return;
      }
      _signOutNotice = _noticeFor(state.signOutReason);
      _set(SessionStatus.signedOut);
    } else {
      _signOutNotice = null;
      unawaited(_resolveTenant());
    }
  }

  /// Saves [session]'s account and latest refresh token, then reloads the
  /// list the switcher shows.
  Future<void> _remember(Session? session, {String? roleLabel}) async {
    try {
      if (session != null) {
        final token = session.refreshToken;
        if (token != null && token.isNotEmpty) {
          await _accounts.upsert(
            userId: session.user.id,
            refreshToken: token,
            email: session.user.email,
            roleLabel: roleLabel,
          );
        }
      }
      _saved = await _accounts.all();
    } catch (error) {
      // The switcher's list is a convenience; failing to keep it must never
      // get in the way of signing in.
      debugPrint('Saved accounts unavailable: $error');
      return;
    }
    notifyListeners();
  }

  /// What to tell the user about a sign-out they did not ask for.
  static String? _noticeFor(SignOutReason? reason) => switch (reason) {
        SignOutReason.sessionExpired =>
          'Your session expired, so you were signed out. Sign in again to '
              'continue.',
        SignOutReason.sessionMissing =>
          'Your saved sign-in could not be restored. Sign in again to '
              'continue.',
        // A deliberate Sign out, or one relayed from another browser tab.
        SignOutReason.userInitiated || null => null,
      };

  Future<void> _resolveTenant() async {
    _error = null;
    _set(SessionStatus.resolving);

    try {
      _tenantContext = await _tenants.resolveForCurrentUser();
      unawaited(
        _remember(_auth.currentSession, roleLabel: _tenantContext?.role.label),
      );
      _set(SessionStatus.ready);
    } on TenantResolutionException catch (error) {
      _error = error.message;
      _set(SessionStatus.failed);
    } catch (error) {
      _error = 'Could not load your workspace: $error';
      _set(SessionStatus.failed);
    }
  }

  /// Retries tenant resolution after a failure.
  Future<void> retry() => _resolveTenant();

  // ---- Accounts on this phone ---------------------------------------------

  /// Opens the login screen to sign in to one more account.
  void beginAddAccount() {
    _addingAccount = true;
    notifyListeners();
  }

  /// Back from the login screen without adding one.
  void cancelAddAccount() {
    if (!_addingAccount) return;
    _addingAccount = false;
    notifyListeners();
  }

  /// Makes a saved account the one in use. Throws when its sign-in has
  /// lapsed; that account is then forgotten, and the user adds it again.
  Future<void> switchTo(String userId) async {
    if (userId == _userId) return;
    final account = await _accounts.find(userId);
    if (account == null) return;
    _clearTenantCaches();
    try {
      await _auth.switchTo(account.refreshToken);
    } on AuthException {
      await _accounts.remove(userId);
      _saved = await _accounts.all();
      notifyListeners();
      throw const SessionSwitchException(
        'That account\'s sign-in has expired. Add it again with its password.',
      );
    }
  }

  /// Signs out a saved account that is not in use. The one in use goes
  /// through [signOut].
  Future<void> forget(String userId) async {
    if (userId == _userId) return signOut();
    final account = await _accounts.find(userId);
    await _accounts.remove(userId);
    _saved = await _accounts.all();
    notifyListeners();
    if (account != null) unawaited(_auth.revoke(account.refreshToken));
  }

  /// The saved accounts, or none when they can't be read — signing out
  /// must still work.
  Future<List<SavedAccount>> _savedOrNone() async {
    try {
      return await _accounts.all();
    } catch (_) {
      return const <SavedAccount>[];
    }
  }

  Future<void> _forgetQuietly(String userId) async {
    try {
      await _accounts.remove(userId);
    } catch (_) {
      // Nothing saved to forget.
    }
  }

  /// Per-tenant data kept on the phone; the next account may not share it.
  void _clearTenantCaches() {
    unawaited(ApprovedTemplatesCache.instance.clear());
  }

  /// Signs out the account in use. Another account signed in on this phone
  /// takes over; with none, the login screen.
  Future<void> signOut() async {
    final leaving = _userId;
    if (leaving != null) await _forgetQuietly(leaving);
    final next = (await _savedOrNone()).firstOrNull;
    var signedOut = false;
    if (next != null) {
      _handingOver = true;
      try {
        await _auth.signOut();
        signedOut = true;
        _clearTenantCaches();
        await _auth.switchTo(next.refreshToken);
        return;
      } on AuthException {
        // The next one's sign-in had lapsed: forget it, end up signed out.
        await _forgetQuietly(next.userId);
      } finally {
        _handingOver = false;
        _saved = await _savedOrNone();
        notifyListeners();
      }
    }

    if (!signedOut) await _auth.signOut();
    _saved = await _savedOrNone();
    // The saved template list is this tenant's; the next sign-in may not
    // be them.
    _clearTenantCaches();
    // The auth stream drives the state change; this keeps the UI snappy when
    // the stream is slow to deliver.
    if (_status != SessionStatus.signedOut) {
      _userId = null;
      _tenantContext = null;
      _error = null;
      _signOutNotice = null;
      _set(SessionStatus.signedOut);
    }
  }

  void _set(SessionStatus status) {
    if (status == SessionStatus.signedOut) _addingAccount = false;
    if (_status == status) {
      notifyListeners();
      return;
    }
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// A saved account could not be switched to.
class SessionSwitchException implements Exception {
  const SessionSwitchException(this.message);
  final String message;
  @override
  String toString() => message;
}
