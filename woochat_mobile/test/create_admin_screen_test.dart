import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:woochat_mobile/src/features/auth/create_admin_screen.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: CreateAdminScreen()));
    await tester.pump();
  }

  Future<void> tapCreate(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Create Admin');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('CreateAdminScreen', () {
    testWidgets('renders every field with no render exceptions',
        (tester) async {
      await pump(tester);

      expect(tester.takeException(), isNull);
      for (final hint in <String>[
        'First Name',
        'Last Name',
        'WhatsApp Number',
        'Phone Number',
        'Password',
        'Confirm',
        'Email Address',
        'Address',
        'City',
        'State',
        'Pincode',
      ]) {
        expect(find.text(hint), findsOneWidget, reason: 'missing field: $hint');
      }
      expect(find.text('Manage your WhatsApp admin access'), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('ships none of the mockup placeholder values', (tester) async {
      await pump(tester);

      for (final mock in <String>[
        'Vicky',
        'Kumar',
        '+91 98765 43210',
        'vickystrxclub@gmail.com',
        'supersecretpwd',
      ]) {
        expect(find.text(mock), findsNothing, reason: 'mock data shipped: $mock');
      }
    });

    testWidgets('required fields are validated before any Supabase call',
        (tester) async {
      await pump(tester);
      await tapCreate(tester);

      // Reaching Supabase in a test would throw, so a clean run also proves
      // the network call never happened.
      expect(tester.takeException(), isNull);
      expect(find.text('Enter the first name'), findsOneWidget);
      expect(find.text('Enter the last name'), findsOneWidget);
      expect(find.text('Enter the WhatsApp number'), findsOneWidget);
      expect(find.text('Enter a password'), findsOneWidget);
      expect(find.text('Enter the email address'), findsOneWidget);
    });

    testWidgets('confirm password must match', (tester) async {
      await pump(tester);

      // Field order matches the form: first, last, whatsapp, phone,
      // password, confirm, email, address, city, state, pincode.
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Asha');
      await tester.enterText(fields.at(1), 'Patel');
      await tester.enterText(fields.at(2), '+91 98765 43210');
      await tester.enterText(fields.at(4), 'secret123');
      await tester.enterText(fields.at(5), 'secret124');
      await tester.enterText(fields.at(6), 'asha@example.com');
      await tester.pump();

      await tapCreate(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('a short password is rejected', (tester) async {
      await pump(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(4), '123');
      await tester.pump();

      await tapCreate(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Use at least 6 characters'), findsOneWidget);
    });
  });
}
