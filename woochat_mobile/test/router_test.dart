import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woochat_mobile/src/data/auth_repository.dart';
import 'package:woochat_mobile/src/routing/app_router.dart';
import 'package:woochat_mobile/src/state/session_controller.dart';

/// A signed-out auth source that never touches Supabase.
class _SignedOutAuth extends AuthRepository {
  const _SignedOutAuth();

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream<AuthState>.empty();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('router', () {
    testWidgets('starts at /welcome and keeps it in the URL', (tester) async {
      final session = SessionController(auth: const _SignedOutAuth())..start();
      addTearDown(session.dispose);

      final router = createRouter(session);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        Routes.welcome,
      );
    });

    testWidgets('signed out, a protected route redirects to /login',
        (tester) async {
      final session = SessionController(auth: const _SignedOutAuth())..start();
      addTearDown(session.dispose);

      final router = createRouter(session);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go(Routes.chats);
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        Routes.login,
      );
    });

    testWidgets('signed out, /login is reachable directly', (tester) async {
      final session = SessionController(auth: const _SignedOutAuth())..start();
      addTearDown(session.dispose);

      final router = createRouter(session);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go(Routes.login);
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        Routes.login,
      );
    });

    testWidgets('signed out, /signup is reachable', (tester) async {
      final session = SessionController(auth: const _SignedOutAuth())..start();
      addTearDown(session.dispose);

      final router = createRouter(session);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go(Routes.signup);
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        Routes.signup,
      );
      expect(find.text('Manage your WhatsApp admin access'), findsOneWidget);
    });

    test('chat detail path is built from the chat id', () {
      expect(Routes.chat('abc-123'), '/chats/abc-123');
    });
  });
}
