import 'package:flutter/material.dart';

import '../src/features/chat/widgets/message_composer.dart';
import '../src/theme/app_theme.dart';

/// Dev-only entry point: the composer on its own, under the real theme and
/// fonts, for checking pixel alignment in a browser.
///
///   flutter run -d chrome -t lib/dev/composer_preview.dart
void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B141A),
        body: Column(
          children: <Widget>[
            const Spacer(),
            MessageComposer(
              onSend: (_) async => true,
              windowOpen: true,
              onTemplates: () {},
              onAttach: (_) {},
              onSchedule: (_) {},
              onBlocked: () {},
              onVoiceNote: (_) async => true,
              onRecorderProblem: (_) {},
            ),
          ],
        ),
      ),
    ),
  );
}
