import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/attach_menu.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_composer.dart';
import 'package:woochat_mobile/src/features/chat/widgets/voice_recorder.dart';
import 'package:woochat_mobile/src/features/chats/widgets/chat_list_tile.dart';
import 'package:woochat_mobile/src/features/chats/widgets/new_chat_dialog.dart';
import 'package:woochat_mobile/src/models/chat.dart';

/// Stands in for the microphone so the composer's record/stop/discard flow
/// can be driven without a platform channel.
class FakeRecorder implements VoiceRecorder {
  FakeRecorder({
    this.permitted = true,
    this.clip,
    this.failsToStart = false,
    this.permissionError,
  });

  final bool permitted;
  final bool failsToStart;

  /// Thrown from hasPermission, the way the browser guard does it.
  final String? permissionError;

  /// What [stop] hands back. Null means the take captured nothing.
  final VoiceClip? clip;

  int started = 0;
  int stopped = 0;
  int cancelled = 0;
  int disposed = 0;

  @override
  Future<bool> hasPermission() async {
    final error = permissionError;
    if (error != null) throw VoiceRecorderException(error);
    return permitted;
  }

  @override
  Future<void> start() async {
    if (failsToStart) {
      throw const VoiceRecorderException('The microphone could not start: x');
    }
    started++;
  }

  @override
  Future<VoiceClip?> stop() async {
    stopped++;
    return clip;
  }

  @override
  Future<void> cancel() async => cancelled++;

  @override
  Future<void> dispose() async => disposed++;
}

VoiceClip fakeClip() => VoiceClip(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      fileName: 'voice-1.m4a',
      contentType: 'audio/mp4',
      duration: const Duration(seconds: 3),
    );

Chat chatWithInbound(DateTime? lastInboundAt) => Chat(
      id: 'c1',
      userId: 'u1',
      contactName: 'Asha',
      lastInboundAt: lastInboundAt,
    );

void main() {
  group('24-hour customer window', () {
    test('a brand new chat starts closed', () {
      // New Chat writes no inbound message, so last_inbound_at is null.
      expect(chatWithInbound(null).isCustomerWindowOpen, isFalse);
    });

    test('open while the last inbound message is under 24 hours old', () {
      final recent = DateTime.now().subtract(const Duration(hours: 23));
      expect(chatWithInbound(recent).isCustomerWindowOpen, isTrue);
    });

    test('closed once 24 hours have passed', () {
      final stale = DateTime.now().subtract(const Duration(hours: 24, minutes: 1));
      expect(chatWithInbound(stale).isCustomerWindowOpen, isFalse);
    });
  });

  group('phone normalisation', () {
    test('compares on digits only so formatting does not create duplicates', () {
      expect(Chat.normalisePhone('+91 98765 43210'), '919876543210');
      expect(Chat.normalisePhone('91-98765-43210'), '919876543210');
      expect(
        Chat.normalisePhone('+91 98765 43210'),
        Chat.normalisePhone('919876543210'),
      );
    });

    test('empty and null are handled', () {
      expect(Chat.normalisePhone(null), '');
      expect(Chat.normalisePhone('  '), '');
    });
  });

  group('chat preview', () {
    test('collapses the raw attachment marker into a short label', () {
      const raw =
          '[attachment:image|https://spx.aurotec.in/storage/v1/object/public/'
          'chat-attachments/x/50_day_camp_intro_en.jpg] Exclusive Update!';

      expect(chatPreview(raw), '[image] Exclusive Update!');
    });

    test('collapses newlines and falls back when there is no message', () {
      expect(chatPreview('line one\nline two'), 'line one line two');
      expect(chatPreview(null), 'No messages yet');
      expect(chatPreview('   '), 'No messages yet');
    });
  });

  group('New Chat dialog', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNewChatDialog(context, ownerId: 'u1'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('matches the web dialog layout', (tester) async {
      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('New Chat'), findsOneWidget);
      expect(find.text('Contact Name'), findsOneWidget);
      expect(find.text('Phone Number'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsOneWidget);
      expect(find.text('Start Chat'), findsOneWidget);
      // Closing is the X, not a Cancel button.
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('validates before touching the database', (tester) async {
      await open(tester);

      await tester.tap(find.text('Start Chat'));
      await tester.pumpAndSettle();

      // Reaching Supabase would throw, so a clean run proves it was not called.
      expect(tester.takeException(), isNull);
      expect(find.text('Enter the contact name'), findsOneWidget);
      expect(find.text('Enter the phone number'), findsOneWidget);
    });

    testWidgets('a too-short number is rejected', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextFormField).at(1), '123');
      await tester.tap(find.text('Start Chat'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Enter a valid number'), findsOneWidget);
    });

    testWidgets('the close button dismisses without a result', (tester) async {
      await open(tester);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('New Chat'), findsNothing);
    });
  });

  group('MessageComposer', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool windowOpen,
      bool noticeHidden = false,
      VoidCallback? onTemplates,
      ValueChanged<AttachOption>? onAttach,
      VoidCallback? onBlocked,
      bool stubEmojiPicker = false,
      VoiceRecorder? recorder,
      Future<bool> Function(VoiceClip clip)? onVoiceNote,
      ValueChanged<String>? onRecorderProblem,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              onSend: (_) async => true,
              windowOpen: windowOpen,
              noticeHidden: noticeHidden,
              onTemplates: onTemplates ?? () {},
              onAttach: onAttach ?? (_) {},
              onVoiceNote: onVoiceNote ?? (_) async => true,
              onRecorderProblem: onRecorderProblem ?? (_) {},
              recorderBuilder: recorder == null ? null : () => recorder,
              onSchedule: (_) {},
              onBlocked: onBlocked ?? () {},
              // The real picker loads through a platform channel that never
              // settles in tests, so the panel itself is stubbed out.
              emojiPickerBuilder: stubEmojiPicker
                  ? (onPick) => GestureDetector(
                        onTap: () => onPick('😀'),
                        child: const Text('stub-picker'),
                      )
                  : null,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the input while the window is open', (tester) async {
      await pump(tester, windowOpen: true);

      expect(tester.takeException(), isNull);
      expect(find.text('Type a message'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Templates'), findsNothing);
    });

    testWidgets('carries every action in the bar', (tester) async {
      await pump(tester, windowOpen: true);

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      // Empty field shows the mic, not a send button.
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
    });

    testWidgets('document and camera live only in the + menu', (tester) async {
      await pump(tester, windowOpen: true);

      // Not repeated as standalone buttons in the bar.
      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Document'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
    });

    testWidgets('the input pill is filled, not outlined', (tester) async {
      await pump(tester, windowOpen: true);

      final pill = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = pill.decoration! as BoxDecoration;

      expect(decoration.border, isNull);
      expect(decoration.color, isNotNull);
      // Fully rounded at the bar's resting height.
      expect(
        decoration.borderRadius,
        BorderRadius.circular(24),
      );
    });

    testWidgets('the pill stands out against its surround', (tester) async {
      await pump(tester, windowOpen: true);

      final surround = tester.widget<Material>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(Material),
            )
            .last,
      );
      final pill = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(Container),
            )
            .first,
      );

      // Near-identical greys made the colour edge read as an outline, which
      // is the thing this is here to stop coming back.
      expect(
        (pill.decoration! as BoxDecoration).color,
        isNot(surround.color),
      );
    });

    testWidgets('the mic sits outside the pill as its own round button',
        (tester) async {
      await pump(tester, windowOpen: true);

      // A circular FilledButton beside the bar, not an icon inside it.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.style?.shape?.resolve(<WidgetState>{}), isA<CircleBorder>());
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byIcon(Icons.mic),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the mic swaps to send as soon as there is text',
        (tester) async {
      await pump(tester, windowOpen: true);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);
    });

    testWidgets('the mic starts recording and swaps the bar for the strip',
        (tester) async {
      final recorder = FakeRecorder(clip: fakeClip());
      await pump(tester, windowOpen: true, recorder: recorder);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      expect(recorder.started, 1);
      // The text pill gives way to the timer, and the mic becomes send.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Recording…'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('the timer counts up while recording', (tester) async {
      await pump(
        tester,
        windowOpen: true,
        recorder: FakeRecorder(clip: fakeClip()),
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('0:02'), findsOneWidget);
    });

    testWidgets('stopping hands the clip up and restores the bar',
        (tester) async {
      final recorder = FakeRecorder(clip: fakeClip());
      final sent = <VoiceClip>[];
      await pump(
        tester,
        windowOpen: true,
        recorder: recorder,
        onVoiceNote: (clip) async {
          sent.add(clip);
          return true;
        },
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(recorder.stopped, 1);
      expect(sent.single.fileName, 'voice-1.m4a');
      // Back to a normal composer once it is away.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Recording…'), findsNothing);
    });

    testWidgets('the bin discards the take without sending it', (tester) async {
      final recorder = FakeRecorder(clip: fakeClip());
      final sent = <VoiceClip>[];
      await pump(
        tester,
        windowOpen: true,
        recorder: recorder,
        onVoiceNote: (clip) async {
          sent.add(clip);
          return true;
        },
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(recorder.cancelled, 1);
      expect(recorder.stopped, 0);
      expect(sent, isEmpty);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a refused microphone explains itself and records nothing',
        (tester) async {
      final recorder = FakeRecorder(permitted: false);
      final problems = <String>[];
      await pump(
        tester,
        windowOpen: true,
        recorder: recorder,
        onRecorderProblem: problems.add,
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      expect(recorder.started, 0);
      expect(problems, <String>[kMicrophoneDeniedMessage]);
      expect(find.text('Recording…'), findsNothing);
    });

    testWidgets('a recorder that refuses up front explains itself',
        (tester) async {
      // How the browser guard surfaces: WhatsApp rejects what a browser
      // records, so it never opens the microphone at all.
      final problems = <String>[];
      await pump(
        tester,
        windowOpen: true,
        recorder: FakeRecorder(permissionError: kBrowserVoiceNoteMessage),
        onRecorderProblem: problems.add,
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      expect(problems, <String>[kBrowserVoiceNoteMessage]);
      expect(find.text('Recording…'), findsNothing);
    });

    testWidgets('a recorder that will not start reports why', (tester) async {
      final problems = <String>[];
      await pump(
        tester,
        windowOpen: true,
        recorder: FakeRecorder(failsToStart: true),
        onRecorderProblem: problems.add,
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      expect(problems.single, contains('could not start'));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('an empty take is reported rather than sent', (tester) async {
      final sent = <VoiceClip>[];
      final problems = <String>[];
      await pump(
        tester,
        windowOpen: true,
        recorder: FakeRecorder(),
        onVoiceNote: (clip) async {
          sent.add(clip);
          return true;
        },
        onRecorderProblem: problems.add,
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(sent, isEmpty);
      expect(problems.single, contains('empty'));
    });

    testWidgets('+ opens the attach menu with all seven options',
        (tester) async {
      await pump(tester, windowOpen: true);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in <String>[
        'Template Message',
        'Quick Replies',
        'Document',
        'Photos & Videos',
        'Audio',
        'Camera',
        'Contact',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
    });

    testWidgets('Template Message goes to the templates sheet, not onAttach',
        (tester) async {
      var templates = 0;
      final attached = <AttachOption>[];
      await pump(
        tester,
        windowOpen: true,
        onTemplates: () => templates++,
        onAttach: attached.add,
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Template Message'));
      await tester.pumpAndSettle();

      expect(templates, 1);
      expect(attached, isEmpty);
    });

    testWidgets('the other attach options report themselves', (tester) async {
      final attached = <AttachOption>[];
      await pump(tester, windowOpen: true, onAttach: attached.add);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos & Videos'));
      await tester.pumpAndSettle();

      expect(attached, <AttachOption>[AttachOption.photos]);
    });

    testWidgets('the clock opens the Schedule message dialog', (tester) async {
      await pump(tester, windowOpen: true);

      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Schedule message'), findsOneWidget);
      expect(find.text('Pick when this message should be sent.'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Schedule'), findsOneWidget);
    });

    testWidgets('Schedule stays disabled until something is typed',
        (tester) async {
      await pump(tester, windowOpen: true);

      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Schedule'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.textContaining('Type a message in the chat box'),
        findsOneWidget,
      );
    });

    testWidgets('the emoji button toggles the picker', (tester) async {
      await pump(tester, windowOpen: true, stubEmojiPicker: true);
      expect(find.text('stub-picker'), findsNothing);

      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pump();
      expect(find.text('stub-picker'), findsOneWidget);

      // The icon flips to a keyboard so the field can be got back to.
      await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await tester.pump();
      expect(find.text('stub-picker'), findsNothing);
    });

    testWidgets('the emoji panel sits below the bar, where the keyboard was',
        (tester) async {
      await pump(tester, windowOpen: true, stubEmojiPicker: true);

      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pump();

      final field = tester.getRect(find.byType(TextField));
      final panel = tester.getRect(find.text('stub-picker'));

      // Above the bar it covered the conversation and stacked on top of the
      // keyboard; WhatsApp swaps the keyboard for it, underneath.
      expect(panel.top, greaterThan(field.bottom));
    });

    testWidgets('opening the panel drops the keyboard', (tester) async {
      await pump(tester, windowOpen: true, stubEmojiPicker: true);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pump();

      // Both cannot be up at once.
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isFalse,
      );
    });

    testWidgets('the keyboard button hands focus back to the field',
        (tester) async {
      await pump(tester, windowOpen: true, stubEmojiPicker: true);

      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await tester.pump();

      expect(find.text('stub-picker'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue,
      );
    });

    testWidgets('tapping the field closes the panel', (tester) async {
      await pump(tester, windowOpen: true, stubEmojiPicker: true);

      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pump();
      expect(find.text('stub-picker'), findsOneWidget);

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(find.text('stub-picker'), findsNothing);
    });

    testWidgets('picking an emoji puts it in the field', (tester) async {
      await pump(tester, windowOpen: true, stubEmojiPicker: true);

      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pump();

      await tester.tap(find.text('stub-picker'));
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Hi😀',
      );
      // Text present, so the round button is now Send.
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('keeps the whole bar once the window closes', (tester) async {
      await pump(tester, windowOpen: false);

      expect(tester.takeException(), isNull);
      // The bar is never taken away — only composing is refused.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Type a message'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      // A thin strip explains why, rather than a blocking box.
      expect(find.textContaining('24-hour window expired'), findsOneWidget);
    });

    testWidgets('the field is inert while the window is closed',
        (tester) async {
      await pump(tester, windowOpen: false);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, isTrue);
    });

    testWidgets('hiding the notice leaves the bar in place', (tester) async {
      await pump(tester, windowOpen: false, noticeHidden: true);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('24-hour window expired'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('tapping the inert field reports the refusal', (tester) async {
      var blocked = 0;
      await pump(
        tester,
        windowOpen: false,
        noticeHidden: true,
        onBlocked: () => blocked++,
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(blocked, 1);
    });

    testWidgets('the mic is refused while the window is closed',
        (tester) async {
      var blocked = 0;
      final recorder = FakeRecorder(clip: fakeClip());
      await pump(
        tester,
        windowOpen: false,
        recorder: recorder,
        onBlocked: () => blocked++,
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      expect(blocked, 1);
      // The microphone is never even opened while the window is closed.
      expect(recorder.started, 0);
      expect(find.text('Recording…'), findsNothing);
    });

    testWidgets('Templates still works from the notice and the + menu',
        (tester) async {
      var taps = 0;
      await pump(tester, windowOpen: false, onTemplates: () => taps++);

      await tester.tap(find.text('Templates'));
      await tester.pump();
      expect(taps, 1);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Template Message'));
      await tester.pumpAndSettle();
      expect(taps, 2);
    });

    testWidgets('other attach options are refused while closed',
        (tester) async {
      var blocked = 0;
      final attached = <AttachOption>[];
      await pump(
        tester,
        windowOpen: false,
        onAttach: attached.add,
        onBlocked: () => blocked++,
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos & Videos'));
      await tester.pumpAndSettle();

      expect(blocked, 1);
      expect(attached, isEmpty);
    });

  });
}
