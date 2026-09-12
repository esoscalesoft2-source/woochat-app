import 'package:flutter/material.dart';

import '../../state/session_scope.dart';

/// Shown when the user is signed in but no tenant could be resolved for them.
class WorkspaceErrorScreen extends StatelessWidget {
  const WorkspaceErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.workspaces_outline, size: 48, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                session.error ?? 'No workspace is linked to this account.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: session.retry,
                child: const Text('Try again'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: session.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
