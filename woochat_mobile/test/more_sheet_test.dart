import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/features/shell/home_nav_bar.dart';
import 'package:woochat_mobile/src/features/shell/more_sheet.dart';
import 'package:woochat_mobile/src/models/tenant_context.dart';

void main() {
  const tenant = TenantContext(
    authUserId: 'u1',
    email: 'esoteam7@gmail.com',
    tenantAdminId: 'u1',
    role: AppRole.admin,
  );

  Future<int> openMore(WidgetTester tester) async {
    var signOuts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: Builder(
            builder: (context) => HomeNavBar(
              onMore: () => showMoreSheet(
                context,
                tenantContext: tenant,
                onSignOut: () async => signOuts++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    return signOuts;
  }

  testWidgets('More shows who is signed in and offers Sign out',
      (tester) async {
    await openMore(tester);

    expect(find.text('esoteam7@gmail.com'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('more-sign-out')), findsOneWidget);
  });

  testWidgets('Sign out asks first, and Cancel keeps you in', (tester) async {
    var signOuts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: Builder(
            builder: (context) => HomeNavBar(
              onMore: () => showMoreSheet(
                context,
                tenantContext: tenant,
                onSignOut: () async => signOuts++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('more-sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(signOuts, 0);

    await tester.tap(find.byKey(const ValueKey<String>('more-sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(signOuts, 1);
  });
}
