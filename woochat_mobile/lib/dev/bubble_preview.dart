import 'package:flutter/material.dart';

import '../src/core/constants.dart';
import '../src/features/chat/widgets/message_bubble.dart';
import '../src/models/message.dart';
import '../src/theme/app_theme.dart';

/// Dev-only entry point: a few bubbles under the real theme and fonts, for
/// checking the stamp placement in a browser.
///
///   flutter run -d chrome -t lib/dev/bubble_preview.dart
void main() {
  Message m(String id, String body, {bool out = true, int h = 10, int min = 24}) =>
      Message(
        id: id,
        chatId: 'c',
        userId: 'u',
        direction: out ? MessageDirection.outbound : MessageDirection.inbound,
        content: body,
        status: out ? MessageStatus.read : null,
        createdAt: DateTime(2026, 9, 11, h, min),
      );

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: Scaffold(
        backgroundColor: Thread.background,
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: <Widget>[
            MessageBubble(
              message: m('1', "Use 997296 Welcome to Vicky's TRX Family", min: 58, h: 9),
            ),
            MessageBubble(
              message: m('2', "Use 564073 Welcome to Vicky's TRX Family"),
              showTail: false,
            ),
            MessageBubble(message: m('3', 'Hlo', h: 12, min: 29)),
            MessageBubble(message: m('4', 'Hii', out: false, h: 16, min: 0)),
            MessageBubble(
              message: m(
                '6',
                '[attachment:audio|voice-1.m4a|https%3A%2F%2Fx.test%2Fv.m4a]',
                h: 16,
                min: 19,
              ),
            ),
            MessageBubble(
              message: m('5', 'Attendance: Not marked\nKeep it up! - Vickys TRX', h: 15, min: 28),
            ),
          ],
        ),
      ),
    ),
  );
}
