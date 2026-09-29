import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// The microphone and the WebRTC connection behind a call — what the
/// session drives, and what a test replaces.
abstract class CallMedia {
  /// Opens the microphone, builds the connection and returns the SDP offer
  /// with its ICE candidates already in it. Meta takes one complete SDP
  /// (no trickle), so this waits for gathering to finish.
  Future<String> createOffer();

  /// The customer's SDP answer, from the `calls` row once they pick up.
  Future<void> acceptAnswer(String sdp);

  /// The other direction: the customer's SDP offer (they called us) in,
  /// our complete SDP answer out — microphone opened, ICE gathered.
  Future<String> createAnswer(String offerSdp);

  void setMuted(bool muted);

  Future<void> setSpeaker(bool on);

  Future<void> dispose();
}

/// The real thing, on flutter_webrtc.
class WebRtcCallMedia implements CallMedia {
  RTCPeerConnection? _pc;
  MediaStream? _mic;

  /// How long to wait for ICE gathering before sending what there is. A
  /// STUN round trip is a few hundred ms; three seconds is the cap so a
  /// blocked network still places the call rather than hanging here.
  static const Duration _gatherTimeout = Duration(seconds: 3);

  /// Microphone + connection, with a completer that fires when ICE is done.
  Future<(RTCPeerConnection, Completer<void>)> _open() async {
    _mic = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
      'audio': true,
      'video': false,
    });
    final pc = await createPeerConnection(<String, dynamic>{
      'iceServers': <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      ],
      // Meta's SDP is unified-plan; anything else is refused as invalid.
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;
    for (final track in _mic!.getAudioTracks()) {
      await pc.addTrack(track, _mic!);
    }
    final gathered = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !gathered.isCompleted) {
        gathered.complete();
      }
    };
    return (pc, gathered);
  }

  /// The local description once gathering has finished (or given up):
  /// that is the SDP with the candidates in it.
  Future<String> _localSdp(
    RTCPeerConnection pc,
    Completer<void> gathered,
    RTCSessionDescription fallback,
  ) async {
    await gathered.future.timeout(_gatherTimeout, onTimeout: () {});
    final local = await pc.getLocalDescription();
    final sdp = local?.sdp ?? fallback.sdp ?? '';
    if (sdp.isEmpty) throw StateError('No SDP was produced');
    return sdp;
  }

  @override
  Future<String> createOffer() async {
    final (pc, gathered) = await _open();
    final offer = await pc.createOffer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await pc.setLocalDescription(offer);
    return _localSdp(pc, gathered, offer);
  }

  @override
  Future<String> createAnswer(String offerSdp) async {
    final (pc, gathered) = await _open();
    await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    final answer = await pc.createAnswer(<String, dynamic>{});
    await pc.setLocalDescription(answer);
    return _localSdp(pc, gathered, answer);
  }

  @override
  Future<void> acceptAnswer(String sdp) async {
    final pc = _pc;
    if (pc == null) throw StateError('No connection to answer');
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  @override
  void setMuted(bool muted) {
    for (final track in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setSpeaker(bool on) => Helper.setSpeakerphoneOn(on);

  @override
  Future<void> dispose() async {
    for (final track in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _mic?.dispose();
    await _pc?.close();
    _mic = null;
    _pc = null;
  }
}
