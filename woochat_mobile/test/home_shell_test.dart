import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/shell/home_nav_bar.dart';
import 'package:woochat_mobile/src/theme/wa_colors.dart';

void main() {
  Future<void> pumpBar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(bottomNavigationBar: HomeNavBar()),
      ),
    );
    await tester.pump();
  }

  test('Chats leads the destination list', () {
    expect(HomeNavBar.destinations.first.label, 'Chats');
    expect(HomeNavBar.destinations[1].label, 'Dashboard');
  });

  test('the active tab is derived from the enabled destination', () {
    expect(HomeNavBar.activeIndex, 0);
    expect(
      HomeNavBar.destinations[HomeNavBar.activeIndex].label,
      'Chats',
      reason: 'the highlight must follow Chats if the order changes',
    );
  });

  test('Chats is the only screen; More opens a sheet', () {
    final enabled = HomeNavBar.destinations
        .where((destination) => destination.enabled)
        .map((destination) => destination.label)
        .toList();

    expect(enabled, <String>['Chats', 'More']);
    expect(
      HomeNavBar.destinations.where((d) => d.opensSheet).map((d) => d.label),
      <String>['More'],
    );
    // More is never the highlighted tab — it opens over whatever is shown.
    expect(HomeNavBar.destinations[HomeNavBar.activeIndex].label, 'Chats');
  });

  testWidgets('Chats renders first and highlighted', (tester) async {
    await pumpBar(tester);

    expect(tester.takeException(), isNull);

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(labels.first, 'Chats');

    Color? colourOf(String label) =>
        tester.widget<Text>(find.text(label)).style?.color;

    expect(colourOf('Chats'), Wa.navActive);
    expect(colourOf('Dashboard'), isNot(Wa.navActive));
  });

  testWidgets('a disabled tab explains itself instead of navigating',
      (tester) async {
    await pumpBar(tester);

    await tester.tap(find.text('Dashboard'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Dashboard arrives in a later phase.'),
      findsOneWidget,
    );
  });
}
