import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/data/chat_monitor_repository.dart';
import 'package:woochat_mobile/src/features/monitor/chat_monitor_screen.dart';
import 'package:woochat_mobile/src/models/tenant_context.dart';

const _admin = TenantContext(
  authUserId: 'u1',
  email: 'esoteam7@gmail.com',
  tenantAdminId: 'u1',
  role: AppRole.admin,
);

MonitorChatRow _row(String id, String name, List<String> statuses, int sev) =>
    MonitorChatRow(
      chatId: id,
      name: name,
      statuses: statuses,
      severity: sev,
      reason: 'Why $name',
    );

/// The monitor without the network; [rows] can change between loads.
class _Repo extends ChatMonitorRepository {
  _Repo();

  var rows = <MonitorChatRow>[
    _row('c1', 'Govinda rajan', ['no_response', 'complaint'], 3),
    _row('c2', 'ashok_i.a.s', ['complaint'], 3),
    _row('c3', 'Meena', ['dropped'], 1),
    _row('c4', 'Ravi', [], 0),
  ];

  @override
  Future<List<MonitorStatus>> statuses({
    required String ownerId,
    required bool isAdmin,
  }) async => const [
    MonitorStatus(
      key: 'no_response',
      name: 'No response from agent',
      enabled: true,
    ),
    MonitorStatus(key: 'dropped', name: 'Dropped by agent', enabled: true),
    MonitorStatus(
      key: 'improper',
      name: 'Improper response by agent',
      enabled: true,
    ),
    MonitorStatus(
      key: 'complaint',
      name: 'Complaint / escalation risk',
      enabled: true,
    ),
    MonitorStatus(key: 'old', name: 'Switched off', enabled: false),
  ];

  @override
  Future<List<MonitorChatRow>> chats(String ownerId) async => rows;

  @override
  Future<List<MonitorIssue>> issues(String ownerId, {String? me}) async =>
      const [];

  @override
  Future<MonitorRun?> lastRun(String ownerId) async => null;

  @override
  Future<List<TeammateAccess>> teammates() async => const [];

  @override
  Future<List<MonitorIssue>> issuesOf(String userId) async => const [];

  @override
  Future<Map<String, String>> names(Iterable<String> userIds) async => const {};
}

Future<_Repo> _openChats(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  await tester.pumpWidget(
    MaterialApp(
      home: ChatMonitorScreen(tenantContext: _admin, repository: repo),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Chats · 4'));
  await tester.pumpAndSettle();
  return repo;
}

/// Ends the monitor, so its refresh timer stops with the test.
Future<void> _close(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

void main() {
  testWidgets('the Chats tab lists every status, with its count', (
    tester,
  ) async {
    await _openChats(tester);
    expect(find.text('By status'), findsOneWidget);
    for (final name in [
      'All chats',
      'No response from agent',
      'Dropped by agent',
      'Improper response by agent',
      'Complaint / escalation risk',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Switched off'), findsNothing, reason: 'turned off');
    // How many are urgent, at a glance.
    expect(find.textContaining('2 urgent'), findsNWidgets(2));
    expect(find.textContaining('1 worth a look'), findsNWidgets(2));
    // The chats themselves are on the statuses' pages, not here.
    expect(find.text('Govinda rajan'), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets('a status opens its own page: its chats, search, Back', (
    tester,
  ) async {
    await _openChats(tester);
    await tester.tap(find.text('Complaint / escalation risk'));
    await tester.pumpAndSettle();
    expect(find.text('2 chats'), findsOneWidget);
    expect(find.text('Govinda rajan'), findsOneWidget);
    expect(find.text('ashok_i.a.s'), findsOneWidget);
    expect(find.text('Meena'), findsNothing);

    await tester.enterText(find.byType(TextField), 'GOV');
    await tester.pump();
    expect(find.text('Govinda rajan'), findsOneWidget);
    expect(find.text('ashok_i.a.s'), findsNothing);
    await tester.enterText(find.byType(TextField), 'nobody');
    await tester.pump();
    expect(find.text('No chats match.'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('By status'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('All chats, urgent only; a status with none stays shut', (
    tester,
  ) async {
    await _openChats(tester);
    await tester.tap(find.text('Improper response by agent'));
    await tester.pumpAndSettle();
    expect(find.text('By status'), findsOneWidget, reason: 'nothing to open');

    await tester.tap(find.text('All chats'));
    await tester.pumpAndSettle();
    expect(find.text('4 chats'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
    await tester.tap(find.text('All severities'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urgent only').last);
    await tester.pumpAndSettle();
    expect(find.text('Govinda rajan'), findsOneWidget);
    expect(find.text('ashok_i.a.s'), findsOneWidget);
    expect(find.text('Meena'), findsNothing);
    expect(find.text('Ravi'), findsNothing);
    await _close(tester);
  });

  testWidgets('an open status page takes in a refresh', (tester) async {
    final repo = await _openChats(tester);
    await tester.tap(find.text('Dropped by agent'));
    await tester.pumpAndSettle();
    expect(find.text('1 chat'), findsOneWidget);

    repo.rows = [
      ...repo.rows,
      _row('c5', 'Kavya', ['dropped'], 2),
    ];
    await tester.fling(find.text('Meena'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2 chats'), findsOneWidget);
    expect(find.text('Kavya'), findsOneWidget);
    await _close(tester);
  });
}
