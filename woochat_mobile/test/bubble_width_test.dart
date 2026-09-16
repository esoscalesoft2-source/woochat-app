import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chat/widgets/message_bubble.dart';
import 'package:woochat_mobile/src/models/message.dart';

Message msg(String content) => Message(
      id: 'm1',
      chatId: 'c1',
      userId: 'u1',
      direction: 'outbound',
      content: content,
    );

void main() {
  Future<Size> bubbleSize(WidgetTester tester, Message message, double screen) async {
    tester.view.physicalSize = Size(screen, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: <Widget>[MessageBubble(message: message)]),
        ),
      ),
    );
    await tester.pump();
    // The painted bubble, inside the margins.
    final align = find.byType(Align).first;
    final paint =
        find.descendant(of: align, matching: find.byType(CustomPaint)).first;
    return tester.getSize(paint);
  }

  testWidgets('on a wide browser a text bubble stops at the absolute cap',
      (tester) async {
    final size = await bubbleSize(
      tester,
      msg('x ' * 400),
      1900,
    );
    expect(size.width, lessThanOrEqualTo(kTextBubbleMaxWidth + 0.5));
  });

  testWidgets('a picture stops at the narrower image cap', (tester) async {
    final size = await bubbleSize(
      tester,
      msg(Message.attachmentMarker(
        type: 'image',
        name: 'shot.png',
        url: 'https://x.test/shot.png',
      )),
      1900,
    );
    expect(size.width, lessThanOrEqualTo(kImageBubbleMaxWidth + 0.5));
  });

  testWidgets('on a phone the 75% rule still wins', (tester) async {
    final size = await bubbleSize(tester, msg('x ' * 400), 400);
    expect(size.width, lessThanOrEqualTo(400 * 0.75 + 0.5));
  });
}
