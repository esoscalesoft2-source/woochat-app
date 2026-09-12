import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  SessionStatus get status => _status;
  TenantContext? get tenantContext => _tenantContext;
  String? get error => _error;

  bool get isSignedOut => _status == SessionStatus.signedOut;
  bool get isReady => _status == SessionStatus.ready;

  /// Begins watching Supabase auth. Call once, at app start.
  void start() {
    _subscription = _auth.onAuthStateChange.listen(_onAuthState);

    final session = _auth.currentSession;
    _userId = session?.user.id;
    if (session == null) {
      _set(SessionStatus.signedOut);
    } else {
      unawaited(_resolveTenant());
    }
  }

  void _onAuthState(AuthState state) {
    final userId = state.session?.user.id;
    // Ignore token refreshes for the same user.
    if (userId == _userId && _status != SessionStatus.unknown) return;
    _userId = userId;

    if (userId == null) {
      _tenantContext = null;
      _error = null;
      _set(SessionStatus.signedOut);
    } else {
      unawaited(_resolveTenant());
    }
  }

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
    // The auth stream drives the state change; this keeps the UI snappy when
    // the stream is slow to deliver.
    if (_status != SessionStatus.signedOut) {
      _userId = null;
      _tenantContext = null;
      _error = null;
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
