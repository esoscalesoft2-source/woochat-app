import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/data/auth_repository.dart';
import 'package:woochat_mobile/src/data/tenant_repository.dart';
import 'package:woochat_mobile/src/models/tenant_context.dart';
import 'package:woochat_mobile/src/state/session_controller.dart';

/// A signed-in session for [id]. Only the user id is read.
Session sessionFor(String id) => Session(
      accessToken: 'token-$id',
      tokenType: 'bearer',
      user: User(
        id: id,
        appMetadata: const <String, dynamic>{},
        userMetadata: const <String, dynamic>{},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );

class FakeAuth extends AuthRepository {
  FakeAuth({this.session});

  Session? session;
  final events = StreamController<AuthState>.broadcast();
  int signOuts = 0;

  @override
  Session? get currentSession => session;

  @override
  Stream<AuthState> get onAuthStateChange => events.stream;

  @override
  Future<void> signOut() async {
    signOuts++;
    session = null;
  }
}

class FakeTenants extends TenantRepository {
  const FakeTenants();

  @override
  Future<TenantContext> resolveForCurrentUser() async => const TenantContext(
        authUserId: 'u1',
        email: 'a@b.c',
        tenantAdminId: 'u1',
        role: AppRole.admin,
      );
}

void main() {
  group('shouldApplyAuthEvent', () {
    test('a null session only counts when Supabase says signed out', () {
      expect(shouldApplyAuthEvent(AuthChangeEvent.signedOut, null), isTrue);
      expect(shouldApplyAuthEvent(AuthChangeEvent.tokenRefreshed, null), isFalse);
      expect(shouldApplyAuthEvent(AuthChangeEvent.userUpdated, null), isFalse);
      expect(shouldApplyAuthEvent(AuthChangeEvent.initialSession, null), isFalse);
    });

    test('any event with a session is applied', () {
      expect(
        shouldApplyAuthEvent(AuthChangeEvent.tokenRefreshed, sessionFor('u1')),
        isTrue,
      );
    });
  });

  group('SessionController', () {
    late FakeAuth auth;
    late SessionController controller;

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    setUp(() async {
      auth = FakeAuth(session: sessionFor('u1'));
      controller = SessionController(auth: auth, tenants: const FakeTenants());
      controller.start();
      await settle();
      expect(controller.status, SessionStatus.ready);
    });

    tearDown(() {
      controller.dispose();
      auth.events.close();
    });

    test('a null session on a refresh event does NOT sign the user out',
        () async {
      // What a dropped refresh used to look like from this side.
      auth.events.add(AuthState(AuthChangeEvent.tokenRefreshed, null));
      await settle();

      expect(controller.status, SessionStatus.ready);
      expect(controller.tenantContext, isNotNull);
    });

    test('a stream error keeps the session and the subscription alive',
        () async {
      auth.events.addError(AuthRetryableFetchException(
        message: 'offline',
      ));
      await settle();
      expect(controller.status, SessionStatus.ready);

      // Still listening: a real sign-out afterwards is honoured.
      auth.events.add(AuthState(
        AuthChangeEvent.signedOut,
        null,
        signOutReason: SignOutReason.userInitiated,
      ));
      await settle();
      expect(controller.status, SessionStatus.signedOut);
    });

    test('an explicit sign-out ends the session with no notice', () async {
      auth.events.add(AuthState(
        AuthChangeEvent.signedOut,
        null,
        signOutReason: SignOutReason.userInitiated,
      ));
      await settle();

      expect(controller.status, SessionStatus.signedOut);
      expect(controller.signOutNotice, isNull);
    });

    test('an expired session signs out AND says why', () async {
      auth.events.add(AuthState(
        AuthChangeEvent.signedOut,
        null,
        signOutReason: SignOutReason.sessionExpired,
      ));
      await settle();

      expect(controller.status, SessionStatus.signedOut);
      expect(controller.signOutNotice, contains('session expired'));

      // Read once, then gone — the login screen shows it a single time.
      expect(controller.takeSignOutNotice(), contains('session expired'));
      expect(controller.takeSignOutNotice(), isNull);
    });

    test('signing back in clears any earlier notice', () async {
      auth.events.add(AuthState(
        AuthChangeEvent.signedOut,
        null,
        signOutReason: SignOutReason.sessionExpired,
      ));
      await settle();
      auth.events.add(AuthState(AuthChangeEvent.signedIn, sessionFor('u1')));
      await settle();

      expect(controller.status, SessionStatus.ready);
      expect(controller.signOutNotice, isNull);
    });

    test('the Sign out button goes through the repository', () async {
      await controller.signOut();

      expect(auth.signOuts, 1);
      expect(controller.status, SessionStatus.signedOut);
      expect(controller.signOutNotice, isNull);
    });
  });
}
