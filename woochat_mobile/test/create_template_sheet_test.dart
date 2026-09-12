import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/templates_repository.dart';
import 'package:woochat_mobile/src/features/chat/widgets/create_template_sheet.dart';
import 'package:woochat_mobile/src/features/chat/widgets/templates_sheet.dart';
import 'package:woochat_mobile/src/theme/app_theme.dart';

void main() {
  group('insertPlaceholder', () {
    test('numbers from the count already used', () {
      expect(
        insertPlaceholder('Hello ', const TextSelection.collapsed(offset: 6), 0)
            .$1,
        'Hello {{1}}',
      );
      expect(
        insertPlaceholder('Hi {{1}} ', const TextSelection.collapsed(offset: 9), 1)
            .$1,
        'Hi {{1}} {{2}}',
      );
    });

    test('appends when the field was never focused', () {
      final (text, caret) = insertPlaceholder('Order', const TextSelection.collapsed(offset: -1), 0);
      expect(text, 'Order{{1}}');
      expect(caret, text.length);
    });
  });

  group('Create Template sheet', () {
    /// The sheet is a lazy list taller than the test viewport, so anything
    /// near the bottom has to be scrolled into the tree before it is tapped.
    Future<void> reveal(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
    }

    /// A TextFormField wraps its own TextField, so `find.byType(TextField)`
    /// also matches the name and body fields; the hint pins this one down.
    final parameterField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'e.g. OTP Code, Tracking ID',
    );

    final saved = <SavedParameter>[
      const SavedParameter(id: 'p1', name: 'OTP Code'),
      const SavedParameter(id: 'p2', name: 'Tracking ID'),
    ];

    Future<({List<TemplateDraft> created, List<String> savedNames})> open(
      WidgetTester tester, {
      bool failCreate = false,
    }) async {
      final created = <TemplateDraft>[];
      final savedNames = <String>[];

      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCreateTemplateSheet(
                  context,
                  loadParameters: () async => saved,
                  saveParameter: (name) async {
                    savedNames.add(name);
                    return SavedParameter(id: 'new', name: name);
                  },
                  create: (draft) async {
                    if (failCreate) {
                      throw const TemplateException(
                        "Missing 'components' for create",
                      );
                    }
                    created.add(draft);
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (created: created, savedNames: savedNames);
    }

    testWidgets('slides up with every field the web dialog has',
        (tester) async {
      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Create Admin Template'), findsOneWidget);
      for (final label in <String>[
        'Template Name',
        'Language',
        'Category',
        'Parameters',
        'Header Media (optional)',
        'Body Text',
        'Create for My Users',
      ]) {
        await reveal(tester, find.text(label));
        expect(find.text(label), findsOneWidget, reason: '$label missing');
      }
      expect(find.text('English (US)'), findsOneWidget);
      expect(find.text('Marketing'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.text('OTP Code'), findsOneWidget);
    });

    testWidgets('rejects a name that is not lowercase_with_underscores',
        (tester) async {
      final result = await open(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Order Confirm');
      await tester.enterText(find.byType(TextFormField).last, 'Hello');
      await reveal(tester, find.text('Create for My Users'));
      await tester.tap(find.text('Create for My Users'));
      await tester.pumpAndSettle();

      expect(
        find.text('Lowercase letters, numbers and underscores only'),
        findsOneWidget,
      );
      expect(result.created, isEmpty);
    });

    testWidgets('tapping a saved parameter drops {{1}} into the body',
        (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextFormField).last, 'Your code: ');
      await reveal(tester, find.text('OTP Code'));
      await tester.tap(find.text('OTP Code'));
      await tester.pumpAndSettle();

      final body = tester.widget<TextFormField>(find.byType(TextFormField).last);
      expect(body.controller?.text, 'Your code: {{1}}');
      expect(find.text('{{1}} = OTP Code'), findsOneWidget);
    });

    testWidgets('submits the draft with the parameters in order',
        (tester) async {
      final result = await open(tester);

      await tester.enterText(find.byType(TextFormField).first, 'otp_login');
      await tester.enterText(find.byType(TextFormField).last, 'Code ');
      await reveal(tester, find.text('OTP Code'));
      await tester.tap(find.text('OTP Code'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Image'));
      await tester.tap(find.text('Image'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Create for My Users'));
      await tester.tap(find.text('Create for My Users'));
      await tester.pumpAndSettle();

      final draft = result.created.single;
      expect(draft.name, 'otp_login');
      expect(draft.language, 'en_US');
      expect(draft.category, 'MARKETING');
      expect(draft.headerFormat, 'IMAGE');
      expect(draft.bodyText, 'Code {{1}}');
      expect(draft.parameters, <String>['OTP Code']);
      // Closed on success.
      expect(find.text('Create Admin Template'), findsNothing);
    });

    testWidgets('a rejected create shows the function\'s own message',
        (tester) async {
      await open(tester, failCreate: true);

      await tester.enterText(find.byType(TextFormField).first, 'otp_login');
      await tester.enterText(find.byType(TextFormField).last, 'Hello');
      await reveal(tester, find.text('Create for My Users'));
      await tester.tap(find.text('Create for My Users'));
      await tester.pumpAndSettle();

      expect(find.text("Missing 'components' for create"), findsOneWidget);
      // Still open, so the user can fix and retry. (The title itself has
      // scrolled out of the lazy list by now, so check the sheet.)
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('a new parameter is saved for reuse', (tester) async {
      final result = await open(tester);

      await tester.enterText(parameterField, 'Delivery Date');
      await reveal(tester, find.text('Add'));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(result.savedNames, <String>['Delivery Date']);
      expect(find.text('Delivery Date'), findsOneWidget);
    });
  });

  group('Templates sheet', () {
    testWidgets('shows + only when creating is wired', (tester) async {
      Future<void> pump({required bool wired}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showTemplatesSheet(
                    context,
                    load: () async => const <MessageTemplate>[],
                    chatName: 'Asha',
                    loadParameters: wired ? () async => const [] : null,
                    saveParameter: wired
                        ? (name) async => SavedParameter(id: 'x', name: name)
                        : null,
                    create: wired ? (_) async {} : null,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      await pump(wired: true);
      expect(find.byTooltip('Create template'), findsOneWidget);

      await tester.tap(find.byTooltip('Create template'));
      await tester.pumpAndSettle();
      expect(find.text('Create Admin Template'), findsOneWidget);
    });
  });
}
