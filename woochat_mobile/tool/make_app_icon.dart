// Builds the launcher icons from the app icon artwork.
//
// The artwork is a finished square icon: the wolf, "WOO" and the speech
// bubble inside a glowing ring, on dark, filling the canvas edge to edge.
// So the flat icon is the artwork itself — shrinking it onto a background
// would only add a border around a design that already has one.
//
//   dart run tool/make_app_icon.dart
//   dart run flutter_launcher_icons
//
// Writes:
//   assets/branding/app_icon.png             1024×1024, the artwork
//   assets/branding/app_icon_foreground.png  1024×1024, the artwork inside
//                                            Android's adaptive safe zone
//   assets/branding/app_icon_round.png       1024×1024, the ring cut out
//                                            of its dark square, for the
//                                            logo shown over a photo
//   web/favicon.png                          64×64

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const String source = 'assets/branding/app_icon_source.png';
const String iconOut = 'assets/branding/app_icon.png';
const String foregroundOut = 'assets/branding/app_icon_foreground.png';
const String roundOut = 'assets/branding/app_icon_round.png';
const String faviconOut = 'web/favicon.png';

const int size = 1024;

void main() {
  final art = img.decodePng(File(source).readAsBytesSync());
  if (art == null) {
    stderr.writeln('Could not decode $source');
    exit(1);
  }

  final square = art.width == size && art.height == size
      ? art
      : img.copyResize(
          art,
          width: size,
          height: size,
          interpolation: img.Interpolation.cubic,
        );

  File(iconOut).writeAsBytesSync(img.encodePng(square));

  // Android keeps only the central ~66% of an adaptive foreground, and a
  // circular mask cuts that to a 676px circle. The ring runs right to the
  // artwork's edge, so it is scaled down to sit inside that circle; the
  // background colour behind fills the corners a square mask leaves.
  File(foregroundOut)
      .writeAsBytesSync(img.encodePng(_inset(square, 0.70)));

  // Beside the "WOO Chat" wordmark the icon sits over a photo, where the
  // artwork's dark square reads as a black tile stuck on the picture. This
  // is the same icon cut to its ring, so only the mark shows.
  File(roundOut).writeAsBytesSync(img.encodePng(_circle(square)));

  // flutter_launcher_icons writes a 16px favicon, too small to read.
  File(faviconOut).writeAsBytesSync(
    img.encodePng(img.copyResize(
      square,
      width: 64,
      height: 64,
      interpolation: img.Interpolation.cubic,
    )),
  );

  stdout.writeln(
    '$source -> $iconOut, $foregroundOut, $roundOut, $faviconOut',
  );
}

/// The artwork centred on a transparent canvas at [fraction] of its width.
img.Image _inset(img.Image art, double fraction) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final target = (size * fraction).round();
  final scaled = img.copyResize(
    art,
    width: target,
    height: target,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    scaled,
    dstX: (size - target) ~/ 2,
    dstY: (size - target) ~/ 2,
  );
  return canvas;
}

/// [art] cut to the ring, everything outside it transparent, then trimmed
/// to what is left.
///
/// The ring's outer glow sits at about 90% of the half-width, so the mask
/// is drawn just outside it — masking at the canvas edge would only have
/// taken the corners and left most of the dark square. The last few pixels
/// fade rather than step, so the edge does not look sawn off when the icon
/// is drawn small.
img.Image _circle(img.Image art) {
  // convert() returns a new image rather than mutating, and without the
  // alpha channel every write below would be discarded.
  final out = art.convert(numChannels: 4);
  final centre = (size - 1) / 2;
  const feather = 6.0;
  final radius = size * 0.455;

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x - centre;
      final dy = y - centre;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance <= radius - feather) continue;
      final pixel = out.getPixel(x, y);
      final alpha = distance >= radius
          ? 0.0
          : (radius - distance) / feather;
      out.setPixelRgba(
        x,
        y,
        pixel.r,
        pixel.g,
        pixel.b,
        (pixel.a * alpha).round(),
      );
    }
  }

  // Trim the transparent margin so the mark fills whatever box it is drawn
  // in rather than floating in the middle of one.
  final side = (radius * 2).round();
  return img.copyCrop(
    out,
    x: ((size - side) / 2).round(),
    y: ((size - side) / 2).round(),
    width: side,
    height: side,
  );
}
