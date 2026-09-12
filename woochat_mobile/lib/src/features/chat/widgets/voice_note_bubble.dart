import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../theme/wa_colors.dart';

/// A voice note, drawn the way WhatsApp draws one: the sender's picture with
/// a mic badge, a play button, a waveform that doubles as a scrubber, and the
/// running time underneath.
class VoiceNoteBubble extends StatefulWidget {
  const VoiceNoteBubble({
    super.key,
    required this.url,
    required this.outbound,
    this.avatar,
    this.playerBuilder,
  });

  final String url;
  final bool outbound;

  /// The sender's picture. A mic-badged placeholder stands in without one.
  final Widget? avatar;

  /// Overrides the player. Only tests use this — a real one would reach for
  /// a platform channel that never answers under test.
  final VoiceNotePlayer Function()? playerBuilder;

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

/// What the bubble needs from an audio player, so the widget can be driven
/// without one.
abstract class VoiceNotePlayer {
  Future<Duration?> load(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;
  Future<void> dispose();
}

/// The real player, backed by `package:just_audio`.
class JustAudioVoiceNotePlayer implements VoiceNotePlayer {
  JustAudioVoiceNotePlayer();

  final AudioPlayer _player = AudioPlayer();

  @override
  Future<Duration?> load(String url) => _player.setUrl(url);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Future<void> dispose() => _player.dispose();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  VoiceNotePlayer? _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  /// The clip is only fetched when it is first played, so a thread full of
  /// voice notes does not pull them all down at once.
  Future<void> _toggle() async {
    if (_loading) return;

    final existing = _player;
    if (existing != null) {
      if (_playing) {
        await existing.pause();
      } else {
        // Starting again from the end should replay, not sit there.
        if (_position >= _duration && _duration > Duration.zero) {
          await existing.seek(Duration.zero);
        }
        await existing.play();
      }
      return;
    }

    setState(() {
      _loading = true;
      _failed = false;
    });

    final player = widget.playerBuilder?.call() ?? JustAudioVoiceNotePlayer();
    try {
      final duration = await player.load(widget.url);
      if (!mounted) {
        await player.dispose();
        return;
      }

      player.positionStream.listen((position) {
        if (mounted) setState(() => _position = position);
      });
      player.playingStream.listen((playing) {
        if (mounted) setState(() => _playing = playing);
      });

      setState(() {
        _player = player;
        _duration = duration ?? Duration.zero;
        _loading = false;
      });
      await player.play();
    } catch (_) {
      await player.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _scrubTo(double fraction) async {
    final player = _player;
    if (player == null || _duration == Duration.zero) return;
    await player.seek(
      Duration(
        milliseconds: (_duration.inMilliseconds * fraction.clamp(0, 1)).round(),
      ),
    );
  }

  String get _clock {
    final shown = _playing || _position > Duration.zero ? _position : _duration;
    final minutes = shown.inMinutes;
    final seconds = (shown.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  double get _progress {
    if (_duration == Duration.zero) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final tint = Wa.accent;

    return SizedBox(
      width: 232,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _Avatar(avatar: widget.avatar),
          const SizedBox(width: 6),
          _PlayButton(
            playing: _playing,
            loading: _loading,
            failed: _failed,
            onPressed: _toggle,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _scrubTo(
                      details.localPosition.dx / constraints.maxWidth,
                    ),
                    onHorizontalDragUpdate: (details) => _scrubTo(
                      details.localPosition.dx / constraints.maxWidth,
                    ),
                    child: CustomPaint(
                      size: const Size(double.infinity, 26),
                      painter: _WaveformPainter(
                        progress: _progress,
                        played: tint,
                        unplayed: widget.outbound
                            ? const Color(0x66FFFFFF)
                            : Thread.meta,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _failed ? 'Tap to retry' : _clock,
                  style: TextStyle(
                    color: Thread.meta,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.avatar});

  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      width: 42,
      child: Stack(
        children: <Widget>[
          ClipOval(
            child: SizedBox(
              height: 40,
              width: 40,
              child: avatar ??
                  Container(
                    color: Wa.chipInactiveBackground,
                    child: const Icon(
                      Icons.person,
                      size: 22,
                      color: Thread.meta,
                    ),
                  ),
            ),
          ),
          // WhatsApp's little mic badge, which is what marks the bubble as a
          // voice note rather than a shared audio file.
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              height: 15,
              width: 15,
              decoration: const BoxDecoration(
                color: Wa.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic, size: 10, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.failed,
    required this.onPressed,
  });

  final bool playing;
  final bool loading;
  final bool failed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: playing ? 'Pause' : 'Play',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: loading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Thread.text,
              ),
            )
          : Icon(
              failed
                  ? Icons.refresh
                  : (playing ? Icons.pause : Icons.play_arrow),
              size: 28,
              color: Thread.text,
            ),
    );
  }
}

/// The bars behind the scrubber. The heights come from a fixed pattern rather
/// than the audio itself — decoding a clip to draw its real envelope would
/// mean downloading every voice note in the thread on sight.
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.progress,
    required this.played,
    required this.unplayed,
  });

  final double progress;
  final Color played;
  final Color unplayed;

  static const List<double> _pattern = <double>[
    0.30, 0.55, 0.85, 0.45, 0.70, 1.00, 0.60, 0.35, 0.80, 0.50,
    0.95, 0.40, 0.65, 0.90, 0.45, 0.75, 0.55, 0.30, 0.85, 0.60,
    0.40, 0.70, 0.95, 0.50, 0.35, 0.80, 0.45, 0.65, 0.55, 0.30,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 2.0;
    const gap = 2.0;
    final count = math.max(1, (size.width / (barWidth + gap)).floor());
    final playedUpTo = count * progress;

    for (var i = 0; i < count; i++) {
      final height = size.height * _pattern[i % _pattern.length];
      final left = i * (barWidth + gap);
      final top = (size.height - height) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          const Radius.circular(1),
        ),
        Paint()..color = i < playedUpTo ? played : unplayed,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.played != played ||
      old.unplayed != unplayed;
}
