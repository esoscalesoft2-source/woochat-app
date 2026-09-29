import 'package:flutter/material.dart';

import '../../data/calls_repository.dart';
import '../../models/chat.dart';
import '../../theme/wa_colors.dart';
import '../chats/widgets/contact_avatar.dart';
import 'call_media.dart';
import 'call_session.dart';

/// WhatsApp's voice-call screen, for a call placed from a chat: the
/// contact large in the middle, the state under their name, mute /
/// speaker / hang up along the bottom. The call itself runs in
/// [CallSession]; this only draws it.
Future<void> showCallScreen(
  BuildContext context, {
  required Chat chat,
  required String name,
  String? photoUrl,
  CallSession? session,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => CallScreen(
        chat: chat,
        name: name,
        photoUrl: photoUrl,
        session: session ??
            CallSession(
              chatId: chat.id,
              repository: const CallsRepository(),
              media: WebRtcCallMedia(),
            ),
      ),
    ),
  );
}

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.chat,
    required this.name,
    required this.session,
    this.photoUrl,
  });

  final Chat chat;
  final String name;
  final String? photoUrl;
  final CallSession session;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _session.begin();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _session.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    setState(() {});
    // A finished call shows its outcome for a moment, then goes back to
    // the chat by itself — WhatsApp's own behaviour.
    if (_session.phase == CallPhase.ended) {
      Future<void>.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  String get _statusLine => switch (_session.phase) {
        CallPhase.checking => 'Checking…',
        CallPhase.incoming => 'Incoming WhatsApp call',
        CallPhase.needsPermission => 'Needs their permission to be called',
        CallPhase.permissionRequested => 'Permission request sent',
        CallPhase.connecting => 'Connecting…',
        CallPhase.ringing => 'Ringing…',
        CallPhase.connected => _clock(_session.elapsedSeconds),
        CallPhase.ended => _session.outcome ?? 'Call ended',
      };

  static String _clock(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final phase = _session.phase;
    final live = phase == CallPhase.ringing || phase == CallPhase.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const SizedBox(height: 24),
            Text(
              _session.isIncoming ? 'WhatsApp call' : 'WhatsApp voice call',
              style: const TextStyle(color: Wa.secondaryText, fontSize: 13),
            ),
            const Spacer(flex: 2),
            ContactAvatar(chat: widget.chat, radius: 64, photoUrl: widget.photoUrl),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Wa.title,
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusLine,
              key: const ValueKey<String>('call-status'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: phase == CallPhase.ended ? Wa.secondaryText : Wa.title,
                fontSize: 15,
              ),
            ),
            const Spacer(flex: 3),
            if (phase == CallPhase.incoming)
              // WhatsApp's own answer screen: decline on the left, answer
              // on the right, nothing else to press.
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    _RoundButton(
                      key: const ValueKey<String>('call-decline'),
                      icon: Icons.call_end,
                      label: 'Decline',
                      color: const Color(0xFFE53935),
                      onPressed: _session.decline,
                    ),
                    _RoundButton(
                      key: const ValueKey<String>('call-accept'),
                      icon: Icons.call,
                      label: 'Accept',
                      color: Wa.accent,
                      onPressed: _session.accept,
                    ),
                  ],
                ),
              )
            else if (phase == CallPhase.needsPermission)
              _PermissionPrompt(
                canRequest: _session.canRequest,
                onRequest: _session.requestPermission,
                onClose: () => Navigator.of(context).maybePop(),
              )
            else if (phase == CallPhase.permissionRequested)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: <Widget>[
                    const Text(
                      'When they tap Allow in WhatsApp, come back and call '
                      'again. Their permission lasts seven days.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Wa.secondaryText, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: Wa.input,
                        foregroundColor: Wa.title,
                        minimumSize: const Size(160, 44),
                      ),
                      child: const Text('Back to chat'),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _RoundButton(
                      key: const ValueKey<String>('call-speaker'),
                      icon: _session.speaker
                          ? Icons.volume_up
                          : Icons.volume_up_outlined,
                      label: 'Speaker',
                      active: _session.speaker,
                      onPressed: live ? _session.toggleSpeaker : null,
                    ),
                    const SizedBox(width: 28),
                    _RoundButton(
                      key: const ValueKey<String>('call-mute'),
                      icon: _session.muted ? Icons.mic_off : Icons.mic_none,
                      label: _session.muted ? 'Unmute' : 'Mute',
                      active: _session.muted,
                      onPressed: live ? _session.toggleMute : null,
                    ),
                    const SizedBox(width: 28),
                    _RoundButton(
                      key: const ValueKey<String>('call-end'),
                      icon: Icons.call_end,
                      label: 'End',
                      color: const Color(0xFFE53935),
                      onPressed: phase == CallPhase.ended
                          ? () => Navigator.of(context).maybePop()
                          : _session.hangUp,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What the screen offers when Meta says the customer has not allowed
/// calls: WhatsApp requires their okay before a business may ring them.
class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({
    required this.canRequest,
    required this.onRequest,
    required this.onClose,
  });

  final bool canRequest;
  final Future<void> Function() onRequest;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      child: Column(
        children: <Widget>[
          Text(
            canRequest
                ? 'WhatsApp needs the customer to allow calls from a '
                    'business first. Send them the request? They tap Allow '
                    'in WhatsApp and you can call for the next seven days.'
                : 'WhatsApp needs the customer to allow calls first, and a '
                    'request was already sent recently — Meta allows one a '
                    'day. Try again later, or message them instead.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Wa.secondaryText, fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextButton(
                onPressed: onClose,
                style: TextButton.styleFrom(foregroundColor: Wa.title),
                child: const Text('Not now'),
              ),
              const SizedBox(width: 12),
              if (canRequest)
                FilledButton(
                  key: const ValueKey<String>('call-request-permission'),
                  onPressed: onRequest,
                  style: FilledButton.styleFrom(
                    backgroundColor: Wa.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('Send request'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? (active ? Wa.title : Colors.white.withValues(alpha: 0.12));
    final ink = color != null
        ? Colors.white
        : active
            ? const Color(0xFF0B141A)
            : Wa.title;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: onPressed == null ? fill.withValues(alpha: 0.4) : fill,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: ink, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Wa.secondaryText, fontSize: 12)),
      ],
    );
  }
}
