import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/image_viewer.dart';
import 'package:woochat_mobile/src/models/message.dart';

void main() {
  const shot = MessageAttachment(
    type: 'image',
    name: 'shot.png',
    url: 'https://x.test/shot.png',
  );

  Future<void> open(WidgetTester tester, {String caption = ''}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showImageViewer(
                context,
                attachment: shot,
                caption: caption,
                title: 'Mahi',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('opens inside the app with a zoomable picture and a close button',
      (tester) async {
    await open(tester);

    expect(find.byKey(const ValueKey<String>('image-viewer')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Mahi'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    // Nothing left the app: the launcher is not involved at all.
  });

  testWidgets('shows the caption along the bottom', (tester) async {
    await open(tester, caption: 'Size chart');
    expect(find.text('Size chart'), findsOneWidget);
  });

  testWidgets('a tap hides the chrome, another brings it back',
      (tester) async {
    await open(tester, caption: 'Size chart');

    await tester.tap(find.byKey(const ValueKey<String>('image-viewer')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.text('Size chart'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('image-viewer')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('✕ returns to the chat', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('image-viewer')), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
