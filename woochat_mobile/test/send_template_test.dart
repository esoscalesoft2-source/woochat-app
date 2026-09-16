import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/messages_repository.dart';
import 'package:woochat_mobile/src/data/templates_repository.dart';
import 'package:woochat_mobile/src/features/chat/widgets/send_template_sheet.dart';
import 'package:woochat_mobile/src/features/chat/widgets/templates_sheet.dart';

void main() {
  const shipped = MessageTemplate(
    id: 't1',
    name: 'vendor_order_shipped',
    language: 'en',
    body: '🚚 Order shipped\nOrder: {{1}} Courier: {{2}} Tracking: {{3}}',
  );
  const plain = MessageTemplate(
    id: 't2',
    name: 'deepan_test',
    language: 'en',
    body: 'Hlo sir',
  );

  group('MessageTemplate', () {
    test('finds the placeholder numbers in order, once each', () {
      expect(shipped.parameterNumbers, <int>[1, 2, 3]);
      expect(plain.parameterNumbers, isEmpty);
      const messy = MessageTemplate(
        id: 'x',
        name: 'x',
        body: '{{ 2 }} then {{1}} and {{2}} again',
      );
      expect(messy.parameterNumbers, <int>[1, 2]);
    });

    test('renders the values and leaves missing ones visible', () {
      expect(
        shipped.render(<int, String>{1: 'DTF00114', 2: 'DTDC', 3: ' X99 '}),
        '🚚 Order shipped\nOrder: DTF00114 Courier: DTDC Tracking: X99',
      );
      expect(
        shipped.render(<int, String>{1: 'DTF00114'}),
        '🚚 Order shipped\nOrder: DTF00114 Courier: {{2}} Tracking: {{3}}',
      );
    });

    test('maps the header format to the media kind WhatsApp uses', () {
      expect(
        const MessageTemplate(id: 'a', name: 'a', headerFormat: 'IMAGE')
            .headerMediaType,
        'image',
      );
      expect(
        const MessageTemplate(id: 'a', name: 'a', headerFormat: 'NONE')
            .headerMediaType,
        isNull,
      );
      expect(plain.headerMediaType, isNull);
    });
  });

  group('template duplicate guard', () {
    final now = DateTime(2026, 9, 12, 11, 0);
    Map<String, dynamic> row(String id, String status, Duration ago,
            {String content = 'same'}) =>
        <String, dynamic>{
          'id': id,
          'status': status,
          'content': content,
          'created_at': now.subtract(ago).toIso8601String(),
        };

    test('refuses while one is still sending', () {
      final plan = MessagesRepository.planTemplateSend(
        <Map<String, dynamic>>[row('m1', 'sending', const Duration(seconds: 5))],
        'same',
        now,
      );
      expect(plan, isA<TemplateSendBlocked>());
      expect(
        (plan as TemplateSendBlocked).reason,
        MessagesRepository.templateInFlight,
      );
    });

    test('refuses when it just went through', () {
      final plan = MessagesRepository.planTemplateSend(
        <Map<String, dynamic>>[row('m1', 'sent', const Duration(seconds: 40))],
        'same',
        now,
      );
      expect(plan, isA<TemplateSendBlocked>());
      expect(
        (plan as TemplateSendBlocked).reason,
        MessagesRepository.templateJustSent,
      );
    });

    test('reuses the failed row with the same content', () {
      final plan = MessagesRepository.planTemplateSend(
        <Map<String, dynamic>>[row('m1', 'failed', const Duration(minutes: 1))],
        'same',
        now,
      );
      expect(plan, isA<TemplateSendReuse>());
      expect((plan as TemplateSendReuse).id, 'm1');
    });

    test('inserts fresh when the old send is stale or different', () {
      expect(
        MessagesRepository.planTemplateSend(
          <Map<String, dynamic>>[row('m1', 'sent', const Duration(minutes: 5))],
          'same',
          now,
        ),
        isA<TemplateSendInsert>(),
      );
      expect(
        MessagesRepository.planTemplateSend(
          <Map<String, dynamic>>[
            row('m1', 'failed', const Duration(minutes: 1), content: 'other'),
          ],
          'same',
          now,
        ),
        isA<TemplateSendInsert>(),
      );
      expect(
        MessagesRepository.planTemplateSend(const [], 'same', now),
        isA<TemplateSendInsert>(),
      );
    });
  });

  group('Templates sheet', () {
    testWidgets('tapping a template hands it back', (tester) async {
      MessageTemplate? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showTemplatesSheet(
                    context,
                    load: () async => const <MessageTemplate>[shipped, plain],
                    chatName: 'Mahi',
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

      expect(find.text('Sending a template needs its parameter values and a '
          'separate call shape — not wired up yet.'), findsNothing);
      await tester.tap(find.text('deepan_test'));
      await tester.pumpAndSettle();

      expect(picked?.id, 't2');
    });
  });

  group('Send template sheet', () {
    /// Pumps the host, opens the sheet, and returns the sheet's own future so
    /// the test can read what Send handed back.
    Future<Future<Map<int, String>?>> open(
      WidgetTester tester,
      MessageTemplate template,
    ) async {
      Future<Map<int, String>?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showSendTemplateSheet(
                    context,
                    template: template,
                    chatName: 'Mahi',
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

    testWidgets('Send stays disabled until every value is filled',
        (tester) async {
      final result = await open(tester, shipped);

      FilledButton button() => tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Send template'),
          );
      expect(button().onPressed, isNull);
      expect(find.textContaining('Order: {{1}}'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('template-param-1')),
        'DTF00114',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('template-param-2')),
        'DTDC',
      );
      await tester.pump();
      expect(button().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey<String>('template-param-3')),
        'X99',
      );
      await tester.pump();
      expect(button().onPressed, isNotNull);
      expect(find.textContaining('Tracking: X99'), findsOneWidget);

      await tester.tap(find.text('Send template'));
      await tester.pumpAndSettle();
      expect(await result, <int, String>{1: 'DTF00114', 2: 'DTDC', 3: 'X99'});
    });

    testWidgets('a template with no placeholders can be sent straight away',
        (tester) async {
      final result = await open(tester, plain);

      expect(find.text('Fill in the values'), findsNothing);
      expect(find.text('Hlo sir'), findsOneWidget);
      await tester.tap(find.text('Send template'));
      await tester.pumpAndSettle();
      expect(await result, isEmpty);
    });
  });
}
