import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/features/shell/settings_screen.dart';
import 'package:woochat_mobile/src/models/tenant_context.dart';

void main() {
  const owner = TenantContext(
    authUserId: 'u1',
    email: 'esoteam7@gmail.com',
    tenantAdminId: 'u1',
    role: AppRole.admin,
  );
  const staff = TenantContext(
    authUserId: 'u2',
    email: 'zakira@eso.in',
    tenantAdminId: 'u1',
    role: AppRole.user,
  );

  Future<List<int>> open(
    WidgetTester tester, {
    TenantContext tenant = owner,
  }) async {
    final signOuts = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSettingsScreen(
                context,
                tenantContext: tenant,
                onSignOut: () async => signOuts.add(1),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return signOuts;
  }

  testWidgets('opens as a page: the account, Storage and data, Sign out',
      (tester) async {
    await open(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('esoteam7@gmail.com'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('settings-storage')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('settings-sign-out')), findsOneWidget);
    // The earlier sections are gone.
    expect(find.text('Your workspace'), findsNothing);
    expect(find.text('Reload templates'), findsNothing);
    expect(find.textContaining('Version'), findsNothing);
  });

  testWidgets('a team member sees their own email and role', (tester) async {
    await open(tester, tenant: staff);
    expect(find.text('zakira@eso.in'), findsOneWidget);
  });

  testWidgets('Storage and data opens its own page', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey<String>('settings-storage')));
    await tester.pumpAndSettle();
    expect(find.text('Storage and data'), findsWidgets);
    expect(find.text('Manage storage'), findsOneWidget);
  });

  testWidgets('Sign out asks first; confirming leaves the page and signs out',
      (tester) async {
    final signOuts = await open(tester);

    await tester.tap(find.byKey(const ValueKey<String>('settings-sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(signOuts, isEmpty);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('settings-sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(signOuts, hasLength(1));
    expect(find.text('Settings'), findsNothing);
  });
}
