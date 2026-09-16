import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/team_repository.dart';
import 'package:woochat_mobile/src/features/chats/widgets/users_filter.dart';
import 'package:woochat_mobile/src/models/chat.dart';

Chat chat(String id, {required String owner, String? assignedTo}) =>
    Chat(id: id, userId: owner, assignedTo: assignedTo);

void main() {
  const me = 'admin-1';
  final chats = <Chat>[
    chat('a', owner: me, assignedTo: 'vishva'),
    chat('b', owner: me, assignedTo: 'durga'),
    chat('c', owner: me), // unassigned
    chat('d', owner: 'admin-2', assignedTo: 'someone'),
  ];

  group('applyUsersFilter', () {
    test('nothing picked shows everything', () {
      expect(
        applyUsersFilter(chats, selected: const {}, authUserId: me, isSuperAdmin: false),
        chats,
      );
    });

    test('a tenant admin filters by who the chat is assigned to', () {
      final out = applyUsersFilter(
        chats,
        selected: const {'vishva', 'durga'},
        authUserId: me,
        isSuperAdmin: false,
      );
      expect(out.map((c) => c.id), <String>['a', 'b']);
    });

    test('"Me" is my own chats, assigned or not', () {
      final out = applyUsersFilter(
        chats,
        selected: const {kMeUserId},
        authUserId: me,
        isSuperAdmin: false,
      );
      // a, b, c are mine; d is another admin's but unassigned rule does not
      // apply since it IS assigned.
      expect(out.map((c) => c.id), <String>['a', 'b', 'c']);
    });

    test('a super admin filters by chat owner instead', () {
      final out = applyUsersFilter(
        chats,
        selected: const {'admin-2'},
        authUserId: 'super',
        isSuperAdmin: true,
      );
      expect(out.map((c) => c.id), <String>['d']);
    });
  });

  group('usersFilterLabel', () {
    const options = <TeamUser>[
      TeamUser(userId: 'vishva', name: 'Vishva Fanideaz'),
      TeamUser(userId: 'durga', name: 'Durga Fanideaz'),
    ];

    test('reads Users, a single name, or a count', () {
      expect(usersFilterLabel(const {}, options), 'Users');
      expect(usersFilterLabel(const {'vishva'}, options), 'Vishva Fanideaz');
      expect(usersFilterLabel(const {kMeUserId}, options), 'Me');
      expect(usersFilterLabel(const {'vishva', 'durga'}, options), 'Users (2)');
    });
  });

  group('Users filter sheet', () {
    const options = <TeamUser>[
      TeamUser(userId: 'vishva', name: 'Vishva Fanideaz', phone: '+91 1'),
      TeamUser(userId: 'durga', name: 'Durga Fanideaz'),
      TeamUser(userId: 'selva', name: 'Selva Fanideaz'),
    ];

    Future<Future<Set<String>?>> open(
      WidgetTester tester, {
      Set<String> selected = const {},
      bool includeMe = true,
    }) async {
      Future<Set<String>?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showUsersFilterSheet(
                    context,
                    options: options,
                    selected: selected,
                    includeMe: includeMe,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result!;
    }

    testWidgets('lists Me then the team, and hands back the ticks',
        (tester) async {
      final result = await open(tester);

      expect(find.text('Team users'), findsOneWidget);
      expect(find.text('Me'), findsOneWidget);
      expect(find.text('Vishva Fanideaz'), findsOneWidget);

      await tester.tap(find.text('Vishva Fanideaz'));
      await tester.tap(find.text('Selva Fanideaz'));
      await tester.pump();
      expect(find.text('Show 2 users'), findsOneWidget);

      await tester.tap(find.text('Show 2 users'));
      await tester.pumpAndSettle();
      expect(await result, <String>{'vishva', 'selva'});
    });

    testWidgets('search narrows the team and hides Me', (tester) async {
      await open(tester);

      await tester.enterText(
        find.byKey(const ValueKey<String>('users-search')),
        'durga',
      );
      await tester.pumpAndSettle();

      expect(find.text('Durga Fanideaz'), findsOneWidget);
      expect(find.text('Vishva Fanideaz'), findsNothing);
      expect(find.text('Me'), findsNothing);
    });

    testWidgets('a super admin gets no Me row', (tester) async {
      await open(tester, includeMe: false);
      expect(find.text('Me'), findsNothing);
    });

    testWidgets('Clear empties the pick and the button says so',
        (tester) async {
      final result = await open(tester, selected: const {'vishva'});

      expect(find.text('Show 1 user'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(find.text('Show all chats'), findsOneWidget);

      await tester.tap(find.text('Show all chats'));
      await tester.pumpAndSettle();
      expect(await result, isEmpty);
    });
  });
}
