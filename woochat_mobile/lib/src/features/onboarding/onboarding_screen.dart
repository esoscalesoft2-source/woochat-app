import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../routing/app_router.dart';
import '../../theme/wa_colors.dart';
import 'onboarding_slides.dart';

/// The onboarding mockup's token names, resolved onto the app-wide WhatsApp
/// palette so the very first screen is the same black as the rest.
class _T {
  const _T._();
  static const Color accent = Wa.accent;
  static const Color background = Wa.chatBackground;
  static const Color text = Wa.title;
  static const Color dotInactive = Wa.secondaryText;

  /// The fade from the illustration down into the background.
  static const Color fade70 = Color(0xB3161717);
  static const Color fade100 = Wa.chatBackground;
  static const double hPadding = 24; // px-6
}

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
            itemCount: onboardingSlides.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) => _SlideView(
              slide: onboardingSlides[index],
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
                pageCount: onboardingSlides.length,
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

/// One poster, whole, with its headline below the subject: the picture
/// fills the width from the top, its empty foot fades into the background,
/// and the words sit on that fade — over floor, never over the subject.
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.bottomInset});

  final OnboardingSlide slide;

  /// The dots + button block is fixed over this page, so the headline is
  /// kept clear of it.
  final double bottomInset;

  /// Every headline gets the same room, so the artwork above it is the same
  /// size on all three pages and nothing jumps as they swipe.
  static const double _titleHeight = 124;

  /// Between the last line of the headline and the dots. The headline is
  /// anchored to the BOTTOM of its room, so a two-line one sits this close
  /// to the dots rather than leaving a gap the size of its missing lines.
  static const double _titleToDots = 20;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // The poster exactly as delivered — the whole 9:16 picture at the
        // screen's width, from the top, nothing cut off. It runs behind the
        // header (its top is dark ceiling) and, on a phone, its foot runs
        // under the headline and the dots: that foot is empty marble floor,
        // which the fade below turns into the background the words sit on.
        Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(
                slide.image,
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: _T.background),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: <double>[0.0, 0.50, 0.72, 1.0],
                    colors: <Color>[
                      Color(0x00000000),
                      Color(0x00000000),
                      _T.fade70,
                      _T.fade100,
                    ],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomInset,
          height: _titleHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              _T.hPadding,
              0,
              _T.hPadding,
              _titleToDots,
            ),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: _Headline(slide: slide),
            ),
          ),
        ),
      ],
    );
  }
}

/// The page's promise, in the app's own type rather than the poster's.
///
/// Colour and font come from the theme — [Wa.title] for the line, the
/// accent green for the part of it the page is actually promising — so a
/// new poster in any lettering still reads as this app underneath.
class _Headline extends StatelessWidget {
  const _Headline({required this.slide});

  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.headlineSmall!.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.3,
          letterSpacing: -0.2,
        );

    final highlight = slide.highlight;
    final at = highlight == null || highlight.isEmpty
        ? -1
        : slide.title.indexOf(highlight);

    return Text.rich(
      at < 0
          // No highlight, or the wording changed and it no longer matches:
          // the line is simply drawn plain.
          ? TextSpan(text: slide.title)
          : TextSpan(
              children: <TextSpan>[
                TextSpan(text: slide.title.substring(0, at)),
                TextSpan(
                  text: highlight!,
                  style: const TextStyle(color: _T.accent),
                ),
                TextSpan(text: slide.title.substring(at + highlight.length)),
              ],
            ),
      style: base,
      // Four lines is every headline with room to spare; the cap only stops
      // a very narrow screen pushing words behind the button.
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
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
              // The app tile itself: its corners are transparent, so over
              // a photo it reads as the mark, not a box stuck on it.
              Image.asset(
                'assets/branding/app_icon_mark.png',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: 28, height: 28),
              ),
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

  /// Dots (10) + gap (24) + button (52) + bottom padding (24), used to inset
  /// the headline above. Must match the layout below exactly: any slack
  /// here is a gap between the headline and the dots.
  static const double height = 110;

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
