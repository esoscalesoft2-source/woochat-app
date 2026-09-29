import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:woochat_mobile/src/features/auth/login_screen.dart';
import 'package:woochat_mobile/src/features/onboarding/onboarding_screen.dart';

/// These pump the screens at real phone and desktop sizes and fail on any
/// render exception — the class of bug that only shows up at runtime, such as
/// a `CrossAxisAlignment.stretch` row inside an unbounded scroll view.
void main() {
  setUpAll(() {
    // Never hit the network for fonts during tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Widget child,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pump();
  }

  /// The screens scroll, so a target can start below the fold.
  Future<void> tapAfterScroll(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('LoginScreen', () {
    testWidgets('lays out on a phone with no render exceptions',
        (tester) async {
      await pumpAt(tester, const LoginScreen(), const Size(390, 844));

      expect(tester.takeException(), isNull);
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(find.text('Shared Team Inbox'), findsOneWidget);
      expect(find.text('AI Auto-Replies'), findsOneWidget);
    });

    testWidgets('lays out on a wide desktop window', (tester) async {
      await pumpAt(tester, const LoginScreen(), const Size(1600, 900));

      expect(tester.takeException(), isNull);
      expect(find.text('Welcome Back'), findsOneWidget);
    });

    testWidgets('auth card sits above the marketing text', (tester) async {
      await pumpAt(tester, const LoginScreen(), const Size(390, 844));

      final cardTop = tester.getTopLeft(find.text('Welcome Back')).dy;
      final brandTop = tester.getTopLeft(find.text('WOO Chat')).dy;
      final featureTop = tester.getTopLeft(find.text('Shared Team Inbox')).dy;

      expect(cardTop, lessThan(brandTop));
      expect(cardTop, lessThan(featureTop));
    });

    testWidgets('shows no mock chat bubbles', (tester) async {
      await pumpAt(tester, const LoginScreen(), const Size(390, 844));

      // The mockup's sample conversation must not ship.
      expect(find.textContaining('How can I help you'), findsNothing);
      expect(find.textContaining('track my order'), findsNothing);
    });

    testWidgets('links out to the sign-up screen instead of toggling a mode',
        (tester) async {
      await pumpAt(tester, const LoginScreen(), const Size(390, 844));

      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      // Registration is its own screen now, not a mode on this card.
      expect(find.text('Create Account'), findsNothing);
    });

    testWidgets('empty submit shows validation instead of calling Supabase',
        (tester) async {
      await pumpAt(tester, const LoginScreen(), const Size(390, 844));
      await tapAfterScroll(tester, find.text('Sign In'));

      expect(tester.takeException(), isNull);
      expect(find.text('Enter your email address'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });
  });

  group('OnboardingScreen', () {
    testWidgets('lays out with both navigation actions present',
        (tester) async {
      await pumpAt(tester, const OnboardingScreen(), const Size(390, 844));

      expect(tester.takeException(), isNull);
      expect(find.text('GET STARTED'), findsOneWidget);
      expect(find.text('SKIP'), findsOneWidget);
      // The first poster is on screen, with its headline drawn by the app
      // below the artwork rather than printed across the top of it.
      expect(
        find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/images/onboarding_1.jpg'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No Ban Risk & Free Official Blue Tick'),
        findsOneWidget,
      );
    });

    testWidgets('the headline sits just above the dots, not floating',
        (tester) async {
      // Tall window: a two-line headline anchored to the top of its room
      // would leave a gap the size of two missing lines above the dots.
      await pumpAt(tester, const OnboardingScreen(), const Size(500, 1000));

      final headline = tester.getRect(
        find.textContaining('No Ban Risk & Free Official Blue Tick'),
      );
      final dots = tester.getRect(find.bySemanticsLabel('Onboarding slides'));

      final gap = dots.top - headline.bottom;
      expect(gap, greaterThanOrEqualTo(16));
      expect(gap, lessThanOrEqualTo(32), reason: 'headline floating above dots');
      // And on the same left edge as the dots.
      expect(headline.left, moreOrLessEquals(dots.left, epsilon: 1));
    });

    testWidgets('GET STARTED fires the finish action', (tester) async {
      var fired = 0;
      await pumpAt(
        tester,
        OnboardingScreen(onFinished: () => fired++),
        const Size(390, 844),
      );

      await tester.tap(find.text('GET STARTED'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(fired, 1);
    });

    testWidgets('SKIP fires the finish action', (tester) async {
      var fired = 0;
      await pumpAt(
        tester,
        OnboardingScreen(onFinished: () => fired++),
        const Size(390, 844),
      );

      await tester.tap(find.text('SKIP'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(fired, 1);
    });

    testWidgets('GET STARTED replaces the route rather than stacking on top',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final observer = _RouteLog();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: <NavigatorObserver>[observer],
          // A stand-in destination: the real one is AuthGate, which needs a
          // live Supabase client that a unit test has no business creating.
          home: OnboardingScreen(
            onFinished: () => _pushReplacementTo(tester, const _Destination()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(_Destination), findsOneWidget);
      // Onboarding is gone from the stack, so Back cannot return to it.
      expect(find.text('GET STARTED'), findsNothing);
      expect(observer.replacements, 1);
    });
  });
}

void _pushReplacementTo(WidgetTester tester, Widget destination) {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.pushReplacement(
    MaterialPageRoute<void>(builder: (_) => destination),
  );
}

class _Destination extends StatelessWidget {
  const _Destination();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('destination')));
}

class _RouteLog extends NavigatorObserver {
  int replacements = 0;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacements++;
  }
}
