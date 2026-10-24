import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/core/constants.dart';
import 'package:woochat_mobile/src/features/shell/home_nav_bar.dart';
import 'package:woochat_mobile/src/features/shell/more_sheet.dart';
import 'package:woochat_mobile/src/models/tenant_context.dart';
import 'package:woochat_mobile/src/state/session_controller.dart';
import 'package:woochat_mobile/src/state/session_scope.dart';

void main() {
  const tenant = TenantContext(
    authUserId: 'u1',
    email: 'esoteam7@gmail.com',
    tenantAdminId: 'u1',
    role: AppRole.admin,
  );

  Future<void> openMore(WidgetTester tester) async {
    await tester.pumpWidget(
      SessionScope(
        controller: SessionController(),
        child: MaterialApp(
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: Builder(
              builder: (context) => HomeNavBar(
                onMore: () => showMoreSheet(context, tenantContext: tenant),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
  }

  testWidgets('More lists the accounts at once, the one in use ticked', (
    tester,
  ) async {
    await openMore(tester);

    expect(find.text('esoteam7@gmail.com'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    // No arrow to open the list: it is already open.
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('more-add-account')),
      findsOneWidget,
    );
  });

  testWidgets('Sign out is not in More — it lives in Settings', (tester) async {
    await openMore(tester);

    expect(find.byKey(const ValueKey<String>('more-sign-out')), findsNothing);
    expect(find.text('Sign out'), findsNothing);
  });
}
