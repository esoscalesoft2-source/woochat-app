import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/chats/chats_list_screen.dart';

void main() {
  Future<int> pump(WidgetTester tester, {required bool inArchive}) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArchivedRow(
            count: 4,
            inArchive: inArchive,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Archived'));
    return taps;
  }

  testWidgets('above the list: archive icon, the count, and it opens on tap',
      (tester) async {
    final taps = await pump(tester, inArchive: false);

    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(taps, 1);
  });

  testWidgets('inside the archive: a back arrow and no count', (tester) async {
    final taps = await pump(tester, inArchive: true);

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsNothing);
    expect(find.text('4'), findsNothing);
    expect(taps, 1);
  });
}
