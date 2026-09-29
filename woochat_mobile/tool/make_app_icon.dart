// Builds the launcher icons from the app icon artwork.
//
// The artwork is a finished app tile: the howling wolf, "WOO" and the
// speech bubble inside a green ring, on a green rounded square whose
// corners are already transparent. So the flat icon is the artwork itself,
// and so is the mark drawn beside "WOO Chat" — a tile with clear corners
// sits on a photo without a box around it.
//
//   dart run tool/make_app_icon.dart
//   dart run flutter_launcher_icons
//
// Writes:
//   assets/branding/app_icon.png             1024×1024, the artwork
//   assets/branding/app_icon_foreground.png  1024×1024, the artwork inside
//                                            Android's adaptive safe zone
//                                            (the background is a flat
//                                            green, set in
//                                            flutter_launcher_icons.yaml)
//   assets/branding/app_icon_mark.png        1024×1024, the artwork again,
//                                            under the name the screens
//                                            that show the mark load
//   web/favicon.png                          64×64

import 'dart:io';

import 'package:image/image.dart' as img;

const String source = 'assets/branding/app_icon_source.png';
const String iconOut = 'assets/branding/app_icon.png';
const String foregroundOut = 'assets/branding/app_icon_foreground.png';
const String markOut = 'assets/branding/app_icon_mark.png';
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

  // Android's adaptive icon shows the central ~66% of a foreground over a
  // background, under the launcher's own mask. flutter_launcher_icons
  // ALREADY insets the foreground by 16% a side (see the generated
  // mipmap-anydpi-v26/ic_launcher.xml), i.e. to 68% — the safe zone. So
  // the foreground handed to it is the tile FULL-BLEED; every earlier
  // attempt insetted it here as well, and the tile came out at half size
  // inside the mask, with its own corners showing as a second box.
  //
  // At 68% the tile just covers a rounded-square mask, the ring sits well
  // inside a circle, and only the tip of the bubble's tail is lost to a
  // strict circle. The background is a flat green sampled from the band
  // of the tile a mask cuts through — never artwork, because the installer
  // dialog and app-info screens draw the layers unmasked.
  File(foregroundOut).writeAsBytesSync(img.encodePng(square));

  // Beside the "WOO Chat" wordmark, over a photo. The tile's own corners
  // are transparent, so it needs no cutting to sit there.
  File(markOut).writeAsBytesSync(img.encodePng(square));

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
    '$source -> $iconOut, $foregroundOut, $markOut, $faviconOut',
  );
}
