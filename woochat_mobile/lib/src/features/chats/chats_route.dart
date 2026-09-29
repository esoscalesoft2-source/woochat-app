import 'package:flutter/material.dart';

import '../../state/session_scope.dart';
import '../call/incoming_call_watcher.dart';
import '../shell/home_shell.dart';

/// `/chats` — waits for the tenant to resolve, then shows the app shell.
class ChatsRoute extends StatelessWidget {
  const ChatsRoute({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final tenantContext = session.tenantContext;

    if (tenantContext == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading your workspace...'),
            ],
          ),
        ),
      );
    }

    // The watcher sits here, under every signed-in screen: a customer's
    // call rings on top of whatever is open, an individual chat included,
    // since those routes stack on this one's navigator.
    return IncomingCallWatcher(
      tenantContext: tenantContext,
      child: HomeShell(
        tenantContext: tenantContext,
        onSignOut: session.signOut,
      ),
    );
  }
}
