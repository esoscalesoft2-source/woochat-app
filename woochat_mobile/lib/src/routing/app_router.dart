import 'package:go_router/go_router.dart';

import '../features/auth/create_admin_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/workspace_error_screen.dart';
import '../features/chat/chat_route.dart';
import '../features/chats/chats_route.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../models/chat.dart';
import '../state/session_controller.dart';

/// Every URL the app can be at. Kept in one place so no screen hardcodes a
/// path string.
class Routes {
  const Routes._();

  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String noWorkspace = '/no-workspace';
  static const String chats = '/chats';

  static String chat(String chatId) => '$chats/$chatId';
}

/// Builds the router. [session] drives every redirect, and is also the
/// refresh signal — any auth or tenant change re-evaluates the current route.
GoRouter createRouter(SessionController session) {
  return GoRouter(
    initialLocation: Routes.welcome,
    refreshListenable: session,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final atWelcome = location == Routes.welcome;
      final atLogin = location == Routes.login;
      final atSignup = location == Routes.signup;
      final atError = location == Routes.noWorkspace;

      switch (session.status) {
        // First auth check has not finished; stay put rather than flashing
        // the login screen at someone who is already signed in.
        case SessionStatus.unknown:
        case SessionStatus.resolving:
          return null;

        case SessionStatus.signedOut:
          return (atWelcome || atLogin || atSignup) ? null : Routes.login;

        case SessionStatus.failed:
          return atError ? null : Routes.noWorkspace;

        case SessionStatus.ready:
          // Signed in: the auth screens are no longer reachable.
          return (atWelcome || atLogin || atSignup || atError)
              ? Routes.chats
              : null;
      }
    },
    routes: <RouteBase>[
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) =>
            LoginScreen(notice: session.takeSignOutNotice()),
      ),
      GoRoute(
        path: Routes.signup,
        builder: (context, state) => const CreateAdminScreen(),
      ),
      GoRoute(
        path: Routes.noWorkspace,
        builder: (context, state) => const WorkspaceErrorScreen(),
      ),
      GoRoute(
        path: Routes.chats,
        builder: (context, state) => const ChatsRoute(),
        routes: <RouteBase>[
          GoRoute(
            path: ':chatId',
            builder: (context, state) => ChatRoute(
              chatId: state.pathParameters['chatId']!,
              // Passed along when opening from the list so the conversation
              // renders instantly; a deep link has no extra and refetches.
              initialChat: state.extra is Chat ? state.extra! as Chat : null,
            ),
          ),
        ],
      ),
    ],
  );
}
