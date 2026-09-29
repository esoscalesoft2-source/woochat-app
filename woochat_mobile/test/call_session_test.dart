import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/calls_repository.dart';
import 'package:woochat_mobile/src/features/call/call_media.dart';
import 'package:woochat_mobile/src/features/call/call_screen.dart';
import 'package:woochat_mobile/src/features/call/call_session.dart';
import 'package:woochat_mobile/src/features/call/incoming_call_watcher.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/models/chat.dart';
import 'package:woochat_mobile/src/models/tenant_context.dart';

class FakeMedia implements CallMedia {
  bool offered = false;
  String? answered;
  bool? muted;
  bool disposed = false;
  Object? offerError;

  @override
  Future<String> createOffer() async {
    if (offerError != null) throw offerError!;
    offered = true;
    return 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n';
  }

  @override
  Future<void> acceptAnswer(String sdp) async => answered = sdp;

  String? offerSeen;
  @override
  Future<String> createAnswer(String offerSdp) async {
    if (offerError != null) throw offerError!;
    offerSeen = offerSdp;
    return 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n';
  }

  @override
  void setMuted(bool value) => muted = value;

  @override
  Future<void> setSpeaker(bool on) async {}

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeCalls extends CallsRepository {
  FakeCalls({this.permissionStatus = 'temporary', this.canRequest = true});

  String permissionStatus;
  bool canRequest;
  CallException? startError;
  final rows = StreamController<CallRow>.broadcast();
  final log = <String>[];

  @override
  Future<CallPermission> permission(String chatId) async {
    log.add('permission');
    return CallPermission(status: permissionStatus, canRequest: canRequest);
  }

  @override
  Future<void> requestPermission(String chatId, {String? text}) async {
    log.add('request');
  }

  @override
  Future<String> start({required String chatId, required String sdp}) async {
    log.add('start');
    if (startError != null) throw startError!;
    return 'call-1';
  }

  @override
  Future<void> terminate({required String chatId, required String callId}) async {
    log.add('terminate $callId');
  }

  @override
  Stream<CallRow> watch(String callId) => rows.stream;

  final ringing = StreamController<List<CallRow>>.broadcast();
  @override
  Stream<List<CallRow>> watchRinging() => ringing.stream;

  @override
  Future<void> preAccept({required String chatId, required String callId, required String sdp}) async {
    log.add('pre_accept $callId');
  }

  @override
  Future<void> accept({required String chatId, required String callId, required String sdp}) async {
    log.add('accept $callId');
  }

  @override
  Future<void> reject({required String chatId, required String callId}) async {
    log.add('reject $callId');
  }
}

void main() {
  late FakeMedia media;
  late FakeCalls calls;

  CallSession session() => CallSession(
        chatId: 'c1',
        repository: calls,
        media: media,
        ringTimeout: const Duration(seconds: 2),
      );

  setUp(() {
    media = FakeMedia();
    calls = FakeCalls();
  });

  Future<void> tick() => Future<void>.delayed(Duration.zero);

  group('CallSession', () {
    test('rings, connects on the answer, and ends on terminate', () async {
      final s = session();
      await s.begin();
      expect(s.phase, CallPhase.ringing);
      expect(media.offered, isTrue);
      expect(calls.log, <String>['permission', 'start']);

      calls.rows.add(const CallRow(id: 'call-1', status: 'accepted', answerSdp: 'ANSWER'));
      await tick();
      expect(s.phase, CallPhase.connected);
      expect(media.answered, 'ANSWER');

      calls.rows.add(const CallRow(id: 'call-1', status: 'ended', answerSdp: 'ANSWER', outcome: 'answered'));
      await tick();
      expect(s.phase, CallPhase.ended);
      expect(s.outcome, 'Call ended');
      expect(media.disposed, isTrue);
      s.dispose();
    });

    test('a declined call says so and frees the microphone', () async {
      final s = session();
      await s.begin();
      calls.rows.add(const CallRow(id: 'call-1', status: 'declined'));
      await tick();
      expect(s.phase, CallPhase.ended);
      expect(s.outcome, 'Declined');
      expect(media.disposed, isTrue);
      s.dispose();
    });

    test('hanging up while ringing tells Meta and is "Cancelled"', () async {
      final s = session();
      await s.begin();
      await s.hangUp();
      expect(s.phase, CallPhase.ended);
      expect(s.outcome, 'Cancelled');
      expect(calls.log.last, 'terminate call-1');
      s.dispose();
    });

    test('no permission stops before the microphone is touched', () async {
      calls.permissionStatus = 'none';
      final s = session();
      await s.begin();
      expect(s.phase, CallPhase.needsPermission);
      expect(s.canRequest, isTrue);
      expect(media.offered, isFalse);
      expect(calls.log, <String>['permission']);

      await s.requestPermission();
      expect(s.phase, CallPhase.permissionRequested);
      expect(calls.log.last, 'request');
      s.dispose();
    });

    test("Meta's refusal at start is shown in its own words", () async {
      calls.startError = const CallException('Recipient has not granted call permission', code: 138011);
      final s = session();
      await s.begin();
      expect(s.phase, CallPhase.ended);
      expect(s.outcome, 'Recipient has not granted call permission');
      expect(media.disposed, isTrue);
      s.dispose();
    });

    test('a refused microphone is explained, not thrown', () async {
      media.offerError = Exception('NotAllowedError: Permission denied');
      final s = session();
      await s.begin();
      expect(s.phase, CallPhase.ended);
      expect(s.outcome, contains('Microphone access was refused'));
      expect(calls.log, isNot(contains('start')));
      s.dispose();
    });

    test('mute reaches the microphone', () async {
      final s = session();
      await s.begin();
      s.toggleMute();
      expect(media.muted, isTrue);
      s.toggleMute();
      expect(media.muted, isFalse);
      s.dispose();
    });
  });

  group('CallSession.incoming', () {
    const ringingRow = CallRow(
      id: 'in-1',
      chatId: 'c1',
      direction: 'inbound',
      status: 'ringing',
      offerSdp: 'THEIR OFFER',
    );

    CallSession incoming() => CallSession.incoming(
          row: ringingRow,
          repository: calls,
          media: media,
          ringTimeout: const Duration(seconds: 2),
        );

    test('starts ringing; accept answers their offer in two steps', () async {
      final s = incoming();
      await s.begin();
      expect(s.phase, CallPhase.incoming);
      expect(media.offered, isFalse, reason: 'nothing until they accept');

      await s.accept();
      expect(media.offerSeen, 'THEIR OFFER');
      expect(calls.log, <String>['pre_accept in-1', 'accept in-1']);
      expect(s.phase, CallPhase.connected);

      calls.rows.add(const CallRow(id: 'in-1', chatId: 'c1', direction: 'inbound', status: 'ended'));
      await tick();
      expect(s.phase, CallPhase.ended);
      expect(s.outcome, 'Call ended');
      s.dispose();
    });

    test('decline rejects and never opens the microphone', () async {
      final s = incoming();
      await s.begin();
      await s.decline();
      expect(s.phase, CallPhase.ended);
      expect(s.outcome, 'Declined');
      expect(calls.log, <String>['reject in-1']);
      expect(media.offerSeen, isNull);
      s.dispose();
    });

    test('the caller giving up while it rings is "Missed"', () async {
      final s = incoming();
      await s.begin();
      calls.rows.add(const CallRow(id: 'in-1', chatId: 'c1', direction: 'inbound', status: 'missed'));
      await tick();
      expect(s.phase, CallPhase.ended);
      expect(s.outcome, 'Missed');
      s.dispose();
    });
  });

  group('shouldRing', () {
    const owner = TenantContext(authUserId: 'admin', email: 'a@x', tenantAdminId: 'admin', role: AppRole.admin);
    const staffA = TenantContext(authUserId: 'a', email: 'a@x', tenantAdminId: 'admin', role: AppRole.user);
    const staffB = TenantContext(authUserId: 'b', email: 'b@x', tenantAdminId: 'admin', role: AppRole.user);

    test('an assigned chat rings its agent at once, the admin as backup', () {
      expect(ringDelay(me: staffA, assignedTo: 'a'), Duration.zero);
      expect(ringDelay(me: staffB, assignedTo: 'a'), isNull);
      expect(ringDelay(me: owner, assignedTo: 'a'), adminBackupDelay);
    });

    test('an unassigned chat rings the admin at once, not the staff', () {
      expect(ringDelay(me: owner, assignedTo: null), Duration.zero);
      expect(ringDelay(me: staffA, assignedTo: null), isNull);
      expect(shouldRing(me: staffA, assignedTo: null), isFalse);
    });
  });

  group('IncomingCallWatcher', () {
    const me = TenantContext(authUserId: 'a', email: 'a@x', tenantAdminId: 'admin', role: AppRole.user);

    testWidgets('a ringing inbound row for my chat opens the call screen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: IncomingCallWatcher(
            tenantContext: me,
            repository: calls,
            loadChat: (id) async => Chat(id: id, userId: 'admin', contactName: 'Krishna', assignedTo: 'a'),
            mediaFactory: () => media,
            child: const Scaffold(body: Text('chats')),
          ),
        ),
      );
      calls.ringing.add(const <CallRow>[
        CallRow(id: 'in-1', chatId: 'c1', direction: 'inbound', status: 'ringing', offerSdp: 'O'),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Krishna'), findsOneWidget);
      expect(find.text('Incoming WhatsApp call'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('call-accept')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('call-decline')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('call-decline')));
      await tester.pumpAndSettle();
      expect(calls.log, <String>['reject in-1']);
      // The screen shows "Declined" briefly, then leaves on its own.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Incoming WhatsApp call'), findsNothing);
      expect(find.text('chats'), findsOneWidget);
    });

    testWidgets('the admin rings after the backup delay if nobody took it',
        (tester) async {
      const admin = TenantContext(authUserId: 'admin', email: 'a@x', tenantAdminId: 'admin', role: AppRole.admin);
      var stillRinging = true;
      await tester.pumpWidget(
        MaterialApp(
          home: IncomingCallWatcher(
            tenantContext: admin,
            repository: calls,
            loadChat: (id) async => Chat(id: id, userId: 'admin', contactName: 'Krishna', assignedTo: 'a'),
            isRinging: (_) async => stillRinging,
            mediaFactory: () => media,
            child: const Scaffold(body: Text('chats')),
          ),
        ),
      );
      calls.ringing.add(const <CallRow>[
        CallRow(id: 'in-3', chatId: 'c3', direction: 'inbound', status: 'ringing', offerSdp: 'O'),
      ]);
      await tester.pump();
      // Not yet: the agent gets the first 12 seconds.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Incoming WhatsApp call'), findsNothing);

      await tester.pump(adminBackupDelay);
      await tester.pumpAndSettle();
      expect(find.text('Incoming WhatsApp call'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('call-decline')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('the admin stays quiet when the agent already answered',
        (tester) async {
      const admin = TenantContext(authUserId: 'admin', email: 'a@x', tenantAdminId: 'admin', role: AppRole.admin);
      await tester.pumpWidget(
        MaterialApp(
          home: IncomingCallWatcher(
            tenantContext: admin,
            repository: calls,
            loadChat: (id) async => Chat(id: id, userId: 'admin', contactName: 'Krishna', assignedTo: 'a'),
            isRinging: (_) async => false, // taken by the agent meanwhile
            mediaFactory: () => media,
            child: const Scaffold(body: Text('chats')),
          ),
        ),
      );
      calls.ringing.add(const <CallRow>[
        CallRow(id: 'in-4', chatId: 'c4', direction: 'inbound', status: 'ringing', offerSdp: 'O'),
      ]);
      await tester.pump();
      await tester.pump(adminBackupDelay + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Incoming WhatsApp call'), findsNothing);
    });

    testWidgets('someone else\'s chat does not ring me', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: IncomingCallWatcher(
            tenantContext: me,
            repository: calls,
            loadChat: (id) async => Chat(id: id, userId: 'admin', contactName: 'Krishna', assignedTo: 'b'),
            mediaFactory: () => media,
            child: const Scaffold(body: Text('chats')),
          ),
        ),
      );
      calls.ringing.add(const <CallRow>[
        CallRow(id: 'in-2', chatId: 'c2', direction: 'inbound', status: 'ringing', offerSdp: 'O'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Incoming WhatsApp call'), findsNothing);
    });
  });

  group('CallScreen', () {
    final chat = Chat(id: 'c1', userId: 'u1', contactName: 'Mahi', contactPhone: '916381318192');

    testWidgets('shows Ringing, then the clock, then the outcome and leaves',
        (tester) async {
      final s = session();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCallScreen(context, chat: chat, name: 'Mahi', session: s),
              child: const Text('call'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('call'));
      await tester.pumpAndSettle();

      expect(find.text('Mahi'), findsOneWidget);
      expect(find.text('Ringing…'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('call-end')), findsOneWidget);

      calls.rows.add(const CallRow(id: 'call-1', status: 'accepted', answerSdp: 'A'));
      await tester.pump();
      await tester.pump();
      expect(find.text('00:00'), findsOneWidget);

      calls.rows.add(const CallRow(id: 'call-1', status: 'ended', answerSdp: 'A'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Call ended'), findsOneWidget);

      // Goes back to the chat by itself.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Call ended'), findsNothing);
      expect(find.text('call'), findsOneWidget);
    });

    testWidgets('offers the permission request when the customer has not allowed calls',
        (tester) async {
      calls.permissionStatus = 'none';
      final s = session();
      await tester.pumpWidget(MaterialApp(home: CallScreen(chat: chat, name: 'Mahi', session: s)));
      await tester.pumpAndSettle();

      expect(find.text('Needs their permission to be called'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('call-request-permission')));
      await tester.pumpAndSettle();
      expect(find.text('Permission request sent'), findsOneWidget);
      expect(calls.log.last, 'request');
    });
  });
}
