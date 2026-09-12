// Builds the launcher icon from the Woo Chat wordmark.
//
// The wordmark is a 2:1 image with white "WOO" lettering on a transparent
// background — fine on the login screen, useless as a 48dp icon on a light
// home screen. So the icon is the wolf mark alone, cut from the left of the
// wordmark and set on the app's black.
//
//   dart run tool/make_app_icon.dart
//   dart run flutter_launcher_icons
//
// Writes:
//   assets/branding/app_icon.png             1024×1024, wolf on #161717
//   assets/branding/app_icon_foreground.png  1024×1024, wolf on transparent,
//                                            padded for Android's adaptive
//                                            safe zone

import 'dart:io';

import 'package:image/image.dart' as img;

const String source = 'assets/branding/app-logo.png';
const String iconOut = 'assets/branding/app_icon.png';
const String foregroundOut = 'assets/branding/app_icon_foreground.png';
const String faviconOut = 'web/favicon.png';

const int size = 1024;

/// The app's black — Wa.chatBackground.
final img.Color background = img.ColorRgb8(0x16, 0x17, 0x17);

void main() {
  final logo = img.decodePng(File(source).readAsBytesSync());
  if (logo == null) {
    stderr.writeln('Could not decode $source');
    exit(1);
  }

  // The wolf occupies the left of the wordmark, up to where the white "W"
  // begins. There is no fully clear column between them — the phone-frame
  // outline runs on into the lettering — but there is a pinch, the column
  // with the fewest visible pixels, and that is where the crop stops.
  final wolfRight = _narrowestColumn(
    logo,
    from: (logo.width * 0.2).round(),
    to: (logo.width * 0.4).round(),
  );
  var minX = logo.width, minY = logo.height, maxX = 0, maxY = 0;
  for (var y = 0; y < logo.height; y++) {
    for (var x = 0; x < wolfRight; x++) {
      if (logo.getPixel(x, y).a > 40) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  final wolf = img.copyCrop(
    logo,
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );

  File(iconOut).writeAsBytesSync(img.encodePng(_compose(wolf, 0.72, opaque: true)));
  // Android keeps only the central ~66% of an adaptive foreground, so the
  // mark is drawn smaller there than in the flat icon.
  File(foregroundOut)
      .writeAsBytesSync(img.encodePng(_compose(wolf, 0.52, opaque: false)));

  // flutter_launcher_icons writes a 16px favicon, which is too small for the
  // mark to read; browsers scale a 64px one down cleanly.
  File(faviconOut).writeAsBytesSync(
    img.encodePng(img.copyResize(
      _compose(wolf, 0.8, opaque: true),
      width: 64,
      height: 64,
      interpolation: img.Interpolation.cubic,
    )),
  );

  stdout.writeln(
    'wolf ${wolf.width}x${wolf.height} -> $iconOut, $foregroundOut, $faviconOut',
  );
}

/// The column in [from]..[to] with the fewest visible pixels.
int _narrowestColumn(img.Image image, {required int from, required int to}) {
  var best = from;
  var fewest = image.height + 1;
  for (var x = from; x < to; x++) {
    var visible = 0;
    for (var y = 0; y < image.height; y++) {
      if (image.getPixel(x, y).a > 128) visible++;
    }
    if (visible < fewest) {
      fewest = visible;
      best = x;
    }
  }
  return best;
}

/// Centres [mark] on a [size]² canvas, scaled so its longer side is
/// [fraction] of the canvas.
img.Image _compose(img.Image mark, double fraction, {required bool opaque}) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(
    canvas,
    color: opaque ? background : img.ColorRgba8(0, 0, 0, 0),
  );

  final target = (size * fraction).round();
  final scale = target / (mark.width > mark.height ? mark.width : mark.height);
  final scaled = img.copyResize(
    mark,
    width: (mark.width * scale).round(),
    height: (mark.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );

  img.compositeImage(
    canvas,
    scaled,
    dstX: (size - scaled.width) ~/ 2,
    dstY: (size - scaled.height) ~/ 2,
  );
  return canvas;
}
