import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  })  : _auth = auth ?? const AuthRepository(),
        _tenants = tenants ?? const TenantRepository();

  final AuthRepository _auth;
  final TenantRepository _tenants;

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
    if (session == null) {
      _set(SessionStatus.signedOut);
    } else {
      unawaited(_resolveTenant());
    }
  }

  void _onAuthState(AuthState state) {
    if (!shouldApplyAuthEvent(state.event, state.session)) return;

    final userId = state.session?.user.id;
    // Ignore token refreshes for the same user.
    if (userId == _userId && _status != SessionStatus.unknown) return;
    _userId = userId;

    if (userId == null) {
      _tenantContext = null;
      _error = null;
      _signOutNotice = _noticeFor(state.signOutReason);
      _set(SessionStatus.signedOut);
    } else {
      _signOutNotice = null;
      unawaited(_resolveTenant());
    }
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

  Future<void> signOut() async {
    await _auth.signOut();
    // The saved template list is this tenant's; the next sign-in may not
    // be them.
    unawaited(ApprovedTemplatesCache.instance.clear());
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
