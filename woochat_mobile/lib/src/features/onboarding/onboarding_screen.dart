import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routing/app_router.dart';
import '../../theme/wa_colors.dart';
import 'widgets/brand_bolt.dart';

/// The onboarding mockup's token names, resolved onto the app-wide WhatsApp
/// palette so the very first screen is the same black as the rest.
class _T {
  const _T._();
  static const Color accent = Wa.accent;
  static const Color background = Wa.chatBackground;
  static const Color text = Wa.title;
  static const Color dotInactive = Wa.secondaryText;

  /// The fade from the illustration down into the background.
  static const Color fade75 = Color(0xBF161717);
  static const Color fade45 = Color(0x73161717);
  static const Color fade70 = Color(0xB3161717);
  static const Color fade96 = Color(0xF5161717);
  static const Color fade100 = Wa.chatBackground;
  static const double hPadding = 24; // px-6
}

/// One carousel page.
class _Slide {
  const _Slide({
    required this.image,
    required this.titleLines,
    required this.accentLine,
    required this.quote,
  });

  final String image;

  /// Plain white lines of the headline.
  final List<String> titleLines;

  /// Final headline line, rendered in the accent colour.
  final String accentLine;

  final String quote;
}

/// Only one background image was supplied, so all three pages reuse it.
/// Drop `onboarding_2.jpg` / `onboarding_3.jpg` into `assets/images/` and
/// change the `image:` values below to give each page its own artwork.
const List<_Slide> _slides = <_Slide>[
  _Slide(
    image: 'assets/images/onboarding_1.jpg',
    titleLines: <String>['NO EXCUSES', 'CLOSE EVERY'],
    accentLine: 'LEAD',
    quote: 'Sales is not about waiting for the right moment. It is about '
        'reaching every customer before someone else does.',
  ),
  _Slide(
    image: 'assets/images/onboarding_1.jpg',
    titleLines: <String>['ONE INBOX', 'FOR YOUR WHOLE'],
    accentLine: 'TEAM',
    quote: 'Every conversation in one place, so nobody answers twice and '
        'nobody gets forgotten.',
  ),
  _Slide(
    image: 'assets/images/onboarding_1.jpg',
    titleLines: <String>['REPLY FAST', 'EVEN WHILE YOU'],
    accentLine: 'SLEEP',
    quote: 'Automations and smart routing keep every customer answered, '
        'around the clock.',
  ),
];

/// Full-screen onboarding carousel shown before the login screen.
///
/// Both SKIP and GET STARTED replace this route with the login screen, so the
/// back button never returns here.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onFinished});

  /// Overrides the default navigation. Only used by tests — in the app this
  /// stays null and both buttons replace the route with the login screen.
  final VoidCallback? onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Sends the user to `/login`. Once they sign in, the router's redirect
  /// moves them on to `/chats` on its own.
  void _goToLogin() {
    final override = widget.onFinished;
    if (override != null) {
      override();
      return;
    }
    // go() replaces the stack, so Back never returns to onboarding.
    context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _T.background,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) => _SlideView(
              slide: _slides[index],
              // Keep the headline clear of the fixed dots + button block.
              bottomInset: _BottomBar.height + bottomSafe,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _Header(onSkip: _goToLogin),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _BottomBar(
                pageCount: _slides.length,
                index: _index,
                onGetStarted: _goToLogin,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Background image plus the cinematic scrim and headline for one page.
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.bottomInset});

  final _Slide slide;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // filter: brightness(0.58) contrast(1.12) from the design.
        ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            1.12, 0, 0, 0, -15.3, //
            0, 1.12, 0, 0, -15.3, //
            0, 0, 1.12, 0, -15.3, //
            0, 0, 0, 1, 0, //
          ]),
          child: Image.asset(
            slide.image,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, _, _) => const ColoredBox(color: _T.background),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: <double>[0.0, 0.30, 0.60, 0.90, 1.0],
              colors: <Color>[
                _T.fade75,
                _T.fade45,
                _T.fade70,
                _T.fade96,
                _T.fade100,
              ],
            ),
          ),
          child: SizedBox.expand(),
        ),
        // bg-emerald-950/20 mix-blend-multiply
        const ColoredBox(color: Color(0x33022C22)),
        Padding(
          padding: EdgeInsets.fromLTRB(
            _T.hPadding,
            0,
            _T.hPadding,
            bottomInset,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: '${slide.titleLines.join('\n')}\n'),
                    TextSpan(
                      text: slide.accentLine,
                      style: const TextStyle(
                        color: _T.accent,
                        shadows: <Shadow>[
                          Shadow(
                            color: Color(0x7321C063),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                  letterSpacing: -0.75,
                  color: Colors.white,
                  shadows: const <Shadow>[
                    Shadow(color: Color(0x66000000), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FractionallySizedBox(
                widthFactor: 0.92,
                child: Text(
                  '“${slide.quote}”',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.625,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Brand mark on the left, SKIP on the right.
class _Header extends StatelessWidget {
  const _Header({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_T.hPadding, 28, _T.hPadding, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const BrandBolt(color: _T.accent, size: 24),
              const SizedBox(width: 8),
              Text(
                'WOO',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'CHAT',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: _T.text,
                ),
              ),
            ],
          ),
          _SkipButton(onPressed: onSkip),
        ],
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Skip to main screen',
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          foregroundColor: Colors.white,
        ),
        child: Text(
          'SKIP',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.6,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

/// Fixed pagination dots and the primary call to action.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.pageCount,
    required this.index,
    required this.onGetStarted,
  });

  /// Dots + gap + button + vertical padding, used to inset the headline above.
  static const double height = 130;

  final int pageCount;
  final int index;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_T.hPadding, 0, _T.hPadding, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            label: 'Onboarding slides',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < pageCount; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == pageCount - 1 ? 0 : 8),
                    child: _Dot(active: i == index),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onGetStarted,
              style: FilledButton.styleFrom(
                backgroundColor: _T.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 8,
                shadowColor: _T.accent.withValues(alpha: 0.4),
              ),
              child: Text(
                'GET STARTED',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? _T.accent : _T.dotInactive,
        boxShadow: active
            ? const <BoxShadow>[
                BoxShadow(color: _T.accent, blurRadius: 8),
              ]
            : null,
      ),
    );
  }
}
