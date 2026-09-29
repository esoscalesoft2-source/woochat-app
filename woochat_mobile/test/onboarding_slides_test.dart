import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/features/onboarding/onboarding_slides.dart';

/// Guards the one file the carousel's wording and posters are edited in, so
/// a change there fails here rather than showing up as a missing picture or
/// a headline that quietly lost its green.
void main() {
  group('onboardingSlides', () {
    test('every poster is a file that exists', () {
      for (final slide in onboardingSlides) {
        expect(
          File(slide.image).existsSync(),
          isTrue,
          reason: '${slide.image} is listed but not in the project',
        );
      }
    });

    test('every highlight is a run of its own title', () {
      for (final slide in onboardingSlides) {
        final highlight = slide.highlight;
        if (highlight == null) continue;
        expect(
          slide.title,
          contains(highlight),
          reason: 'the accent run "$highlight" is not in "${slide.title}", '
              'so the line would be drawn plain',
        );
      }
    });

    test('each headline is short enough for the four lines it is given', () {
      for (final slide in onboardingSlides) {
        // Roughly 30 characters fit a line at 24px on a 390pt phone.
        expect(slide.title.length, lessThanOrEqualTo(120));
      }
    });
  });
}
