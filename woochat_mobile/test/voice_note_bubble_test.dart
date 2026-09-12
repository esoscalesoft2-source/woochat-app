import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/voice_note_bubble.dart';

/// Stands in for just_audio so the card can be driven without a platform
/// channel or a network fetch.
class FakePlayer implements VoiceNotePlayer {
  FakePlayer({this.duration = const Duration(seconds: 5), this.fails = false});

  final Duration duration;
  final bool fails;

  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  int loads = 0;
  int plays = 0;
  int pauses = 0;
  Duration? seekedTo;

  @override
  Future<Duration?> load(String url) async {
    loads++;
    if (fails) throw Exception('404');
    return duration;
  }

  @override
  Future<void> play() async {
    plays++;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seekedTo = position;
    _position.add(position);
  }

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<void> dispose() async {
    await _position.close();
    await _playing.close();
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    FakePlayer player, {
    bool outbound = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VoiceNoteBubble(
              url: 'https://x.test/voice.m4a',
              outbound: outbound,
              playerBuilder: () => player,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('VoiceNoteBubble', () {
    testWidgets('shows a play button and a mic-badged avatar', (tester) async {
      await pump(tester, FakePlayer());

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      // Nothing is fetched until it is played.
      expect(find.byIcon(Icons.pause), findsNothing);
    });

    testWidgets('the clip is only loaded when play is tapped', (tester) async {
      final player = FakePlayer();
      await pump(tester, player);

      expect(player.loads, 0);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(player.loads, 1);
      expect(player.plays, 1);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('tapping again pauses rather than reloading', (tester) async {
      final player = FakePlayer();
      await pump(tester, player);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();

      expect(player.pauses, 1);
      expect(player.loads, 1);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('the clock follows the playhead', (tester) async {
      final player = FakePlayer(duration: const Duration(seconds: 5));
      await pump(tester, player);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      // Counts up from the start once it is running, as WhatsApp does.
      expect(find.text('0:00'), findsOneWidget);

      player.seek(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('0:02'), findsOneWidget);

      player.seek(const Duration(minutes: 1, seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('1:07'), findsOneWidget);
    });

    testWidgets('the waveform scrubs', (tester) async {
      final player = FakePlayer(duration: const Duration(seconds: 10));
      await pump(tester, player);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      final wave = tester.getRect(find.byType(CustomPaint).last);
      await tester.tapAt(Offset(wave.center.dx, wave.center.dy));
      await tester.pumpAndSettle();

      // Halfway along a ten second clip.
      expect(player.seekedTo!.inSeconds, closeTo(5, 1));
    });

    testWidgets('a clip that will not load offers a retry', (tester) async {
      await pump(tester, FakePlayer(fails: true));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('Tap to retry'), findsOneWidget);
    });
  });
}
