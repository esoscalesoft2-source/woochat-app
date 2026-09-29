import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/calls_repository.dart';
import 'call_media.dart';

/// Where a call is, as the screen shows it.
enum CallPhase {
  /// Asking Meta whether the customer allows calls.
  checking,

  /// They have not allowed calls (or it lapsed): offer to ask.
  needsPermission,

  /// The "may we call you?" message went out; nothing more to do here.
  permissionRequested,

  /// A customer is calling: their phone is on, ours is ringing.
  incoming,

  /// Microphone opening, offer being built, Meta being asked.
  connecting,

  /// Meta accepted the request; the customer's phone is ringing.
  ringing,

  /// They picked up and the audio is flowing.
  connected,

  /// Over, for any reason — [CallSession.outcome] says which.
  ended,
}

/// One WhatsApp call, either direction, from the first moment to the end.
///
/// Owns the media, the row in `calls`, and the clock. The screen only
/// reads [phase] and calls [hangUp], [accept], [decline], [toggleMute],
/// [toggleSpeaker].
///
///   outbound:  checking → needsPermission → permissionRequested
///                       ↘ connecting → ringing → connected → ended
///                                     ↘ ended (declined / missed / failed)
///   incoming:  incoming → connecting → connected → ended
///                       ↘ ended (declined here, or the caller gave up)
class CallSession extends ChangeNotifier {
  /// A call we are placing.
  CallSession({
    required this.chatId,
    required this.repository,
    required this.media,
    this.ringTimeout = const Duration(seconds: 75),
  }) : _incoming = null;

  /// A call the customer is placing to us: [row] is their ringing call,
  /// with their SDP offer in it.
  CallSession.incoming({
    required CallRow row,
    required this.repository,
    required this.media,
    this.ringTimeout = const Duration(seconds: 45),
  })  : chatId = row.chatId,
        _incoming = row,
        _callId = row.id,
        _phase = CallPhase.incoming;

  final String chatId;
  final CallsRepository repository;
  final CallMedia media;
  final CallRow? _incoming;

  bool get isIncoming => _incoming != null;

  /// Meta ends an unanswered call at about a minute; this is the backstop
  /// should its terminate event never arrive.
  final Duration ringTimeout;

  CallPhase _phase = CallPhase.checking;
  CallPhase get phase => _phase;
  // (the incoming constructor starts at CallPhase.incoming instead)

  /// What the screen says when it is over: "Declined", "No answer", the
  /// error… Null while the call is live.
  String? _outcome;
  String? get outcome => _outcome;

  /// Whether the customer can be sent a permission request right now.
  bool _canRequest = false;
  bool get canRequest => _canRequest;

  String? _callId;
  bool _muted = false;
  bool _speaker = false;
  bool get muted => _muted;
  bool get speaker => _speaker;

  DateTime? _connectedAt;
  Timer? _clock;
  Timer? _ringGuard;
  StreamSubscription<CallRow>? _rowSub;
  bool _answered = false;
  bool _disposed = false;

  /// Seconds since the customer picked up; 0 before.
  int get elapsedSeconds {
    final at = _connectedAt;
    return at == null ? 0 : DateTime.now().difference(at).inSeconds;
  }

  /// Runs the whole thing. Safe to call once. For an incoming call this
  /// only starts following the row (the caller may hang up before we
  /// answer) and the ring guard; [accept] or [decline] does the rest.
  Future<void> begin() async {
    if (_incoming != null) {
      _watch(_incoming.id);
      _ringGuard = Timer(ringTimeout, () {
        // Meta gives 30–60 s. Past that the call is theirs to have missed.
        if (_phase == CallPhase.incoming) _end('Missed');
      });
      return;
    }
    try {
      final permission = await repository.permission(chatId);
      if (_disposed) return;
      if (!permission.granted) {
        _canRequest = permission.canRequest;
        _set(CallPhase.needsPermission);
        return;
      }
    } on CallException catch (error) {
      // Meta will say no again at start if permission really is the
      // problem; a failed lookup alone should not stop the call.
      debugPrint('call permission lookup: ${error.message}');
    }
    await _place();
  }

  /// Sends WhatsApp's "may we call you?" message and stops here.
  Future<void> requestPermission() async {
    try {
      await repository.requestPermission(chatId);
      if (!_disposed) _set(CallPhase.permissionRequested);
    } on CallException catch (error) {
      _end(error.message);
    }
  }

  Future<void> _place() async {
    _set(CallPhase.connecting);
    final String sdp;
    try {
      sdp = await media.createOffer();
    } catch (error) {
      _end(_micProblem(error));
      return;
    }
    if (_disposed) return;

    final String callId;
    try {
      callId = await repository.start(chatId: chatId, sdp: sdp);
    } on CallException catch (error) {
      _end(error.message);
      return;
    }
    if (_disposed) return;
    _callId = callId;
    _set(CallPhase.ringing);

    _ringGuard = Timer(ringTimeout, () {
      if (_phase == CallPhase.ringing) hangUp();
    });
    _watch(callId);
  }

  void _watch(String callId) {
    _rowSub = repository.watch(callId).listen(
      _onRow,
      onError: (Object error) => _end('Lost track of the call: $error'),
    );
  }

  /// Picks up a customer's call: answer built from their offer, sent as
  /// pre_accept (media path ready while it still rings) then accept.
  Future<void> accept() async {
    final row = _incoming;
    if (row == null || _phase != CallPhase.incoming) return;
    _ringGuard?.cancel();
    _set(CallPhase.connecting);

    final offer = row.offerSdp;
    if (offer == null || offer.isEmpty) {
      _end('The call carried no offer to answer');
      return;
    }
    final String sdp;
    try {
      sdp = await media.createAnswer(offer);
    } catch (error) {
      _end(_micProblem(error));
      return;
    }
    if (_disposed) return;
    try {
      await repository.preAccept(chatId: chatId, callId: row.id, sdp: sdp);
      await repository.accept(chatId: chatId, callId: row.id, sdp: sdp);
    } on CallException catch (error) {
      _end(error.message);
      return;
    }
    if (_disposed) return;
    _answered = true;
    _connectedAt = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    _set(CallPhase.connected);
  }

  /// Sends a customer's call away.
  Future<void> decline() async {
    final row = _incoming;
    if (row == null || _phase != CallPhase.incoming) return;
    _end('Declined');
    try {
      await repository.reject(chatId: chatId, callId: row.id);
    } on CallException catch (error) {
      debugPrint('reject: ${error.message}');
    }
  }

  Future<void> _onRow(CallRow row) async {
    if (_disposed) return;
    if (!isIncoming && !_answered && row.answerSdp != null) {
      _answered = true;
      try {
        await media.acceptAnswer(row.answerSdp!);
      } catch (error) {
        _end('Could not connect the audio: $error');
        return;
      }
      _ringGuard?.cancel();
      _connectedAt = DateTime.now();
      _clock = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
      _set(CallPhase.connected);
    }
    if (row.isOver && _phase != CallPhase.ended) {
      _end(switch (row.status) {
        'declined' => 'Declined',
        // Theirs to have missed when we placed it; ours when they did.
        'missed' => isIncoming ? 'Missed' : 'No answer',
        'failed' => 'Call failed',
        _ => 'Call ended',
      });
    }
  }

  /// The red button. Also what the ring guard presses. On a call that is
  /// still incoming this is [decline].
  Future<void> hangUp() async {
    if (_phase == CallPhase.ended) return;
    if (_phase == CallPhase.incoming) return decline();
    final wasConnected = _phase == CallPhase.connected;
    final callId = _callId;
    _end(wasConnected ? 'Call ended' : 'Cancelled');
    if (callId != null) {
      try {
        await repository.terminate(chatId: chatId, callId: callId);
      } on CallException catch (error) {
        debugPrint('terminate: ${error.message}');
      }
    }
  }

  void toggleMute() {
    _muted = !_muted;
    media.setMuted(_muted);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    notifyListeners();
    try {
      await media.setSpeaker(_speaker);
    } catch (_) {
      // Not every platform routes audio; the toggle still shows intent.
    }
  }

  void _end(String outcome) {
    if (_phase == CallPhase.ended) return;
    _outcome = outcome;
    _clock?.cancel();
    _ringGuard?.cancel();
    _rowSub?.cancel();
    unawaited(media.dispose());
    _set(CallPhase.ended);
  }

  void _set(CallPhase phase) {
    _phase = phase;
    if (!_disposed) notifyListeners();
  }

  static String _micProblem(Object error) {
    final text = error.toString();
    if (text.contains('NotAllowed') || text.contains('Permission')) {
      return 'Microphone access was refused. Allow it in settings and try again.';
    }
    return 'Could not open the microphone: $text';
  }

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    _ringGuard?.cancel();
    _rowSub?.cancel();
    unawaited(media.dispose());
    super.dispose();
  }
}
