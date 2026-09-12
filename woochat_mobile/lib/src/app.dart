import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'config/env.dart';
import 'routing/app_router.dart';
import 'state/session_controller.dart';
import 'state/session_scope.dart';
import 'theme/app_theme.dart';

class WooChatApp extends StatefulWidget {
  const WooChatApp({super.key, required this.configured});

  /// False when SUPABASE_URL / SUPABASE_ANON_KEY were not supplied.
  final bool configured;

  @override
  State<WooChatApp> createState() => _WooChatAppState();
}

class _WooChatAppState extends State<WooChatApp> {
  SessionController? _session;
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    if (!widget.configured) return;

    // Supabase is only initialised when the app is configured, so the session
    // controller must not be started otherwise.
    final session = SessionController()..start();
    _session = session;
    _router = createRouter(session);
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    final session = _session;

    if (router == null || session == null) {
      return MaterialApp(
        title: 'WooChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        // WhatsApp dark, always — following the system left Material's
        // light defaults showing through on a light-mode machine.
        themeMode: ThemeMode.dark,
        home: const _MissingConfigScreen(),
      );
    }

    return SessionScope(
      controller: session,
      child: MaterialApp.router(
        title: 'WooChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        // WhatsApp dark, always — following the system left Material's
        // light defaults showing through on a light-mode machine.
        themeMode: ThemeMode.dark,
        routerConfig: router,
      ),
    );
  }
}

/// Shown instead of the app when the build is missing its Supabase config.
class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.settings_suggest_outlined,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Configuration missing', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                'Not set: ${Env.missingKeys.join(', ')}.\n\n'
                'Copy assets/env/env.example.json to assets/env/env.json and '
                'fill in your Supabase URL and anon key, then restart the app '
                '(a hot reload will not pick up a new asset).\n\n'
                'Alternatively pass them at build time:\n'
                'flutter run --dart-define-from-file=assets/env/env.json\n\n'
                'See README.md for details.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
