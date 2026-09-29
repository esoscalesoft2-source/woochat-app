/// The onboarding carousel's content: the one file to edit when the posters
/// or their words change.
///
/// The headlines are app text, not part of the pictures: the posters are
/// delivered without words (1080×1920, shown whole). So a new poster means
/// two edits in the same place here: the image, and the line that goes with
/// it. Nothing about the wording lives in the screen itself.
///
/// The screen draws these in the app's own type and colours ([Wa.title],
/// with [highlight] in the accent green), so a replacement poster in any
/// style still reads as this app rather than as the picture's own lettering.
library;

/// One page of the carousel.
class OnboardingSlide {
  const OnboardingSlide({
    required this.image,
    required this.title,
    this.highlight,
  });

  /// Asset path of the poster, a wordless 9:16 picture.
  final String image;

  /// The headline, drawn under the poster and wrapped to the screen.
  final String title;

  /// A run of [title] to pick out in the accent green — the promise the page
  /// is making. Left null, the whole line is plain. It must appear in
  /// [title] word for word; if it does not, the line simply stays plain.
  final String? highlight;
}

/// The three marketing posters, in the order they are shown.
///
/// To add a page: drop the poster in `assets/images/` and add an entry
/// below. The dots count themselves.
const List<OnboardingSlide> onboardingSlides = <OnboardingSlide>[
  OnboardingSlide(
    image: 'assets/images/onboarding_1.jpg',
    title: 'One Upgrade, Two Benefits: '
        'No Ban Risk & Free Official Blue Tick.',
    highlight: 'Free Official Blue Tick.',
  ),
  OnboardingSlide(
    image: 'assets/images/onboarding_2.jpg',
    title: 'Run Your Business Without WhatsApp Ban Worries',
    highlight: 'Without WhatsApp Ban Worries',
  ),
  OnboardingSlide(
    image: 'assets/images/onboarding_3.jpg',
    title: 'One follow-up can turn a silent lead into a paying customer.',
    highlight: 'a paying customer.',
  ),
];
