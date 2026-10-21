// Renders the Sea Siege ship sprites (paintShip in packages/nico_shared) as
// PNGs for the browser shared screen. Written by draw_sprites_test.dart and
// checked against the painter by test/games/seasiege_sprites_test.dart.
import 'dart:typed_data';
import 'dart:ui';

import 'package:nico_shared/games/seasiege/seasiege_fleet.dart';
import 'package:nico_shared/games/seasiege/seasiege_sprites.dart';

/// Where the browser screen loads them from.
const spriteDir = 'assets/display/games/seasiege';

/// Pixels per board square.
const spriteSquare = 64;

/// `carrier.png`, `carrier_sunk.png`, …
String spriteName(ShipType type, {required bool sunk}) =>
    '${type.name}${sunk ? '_sunk' : ''}.png';

/// One ship, bow to the right, `size` squares wide and one square high.
Future<Image> renderShip(ShipType type, {required bool sunk}) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)..scale(spriteSquare.toDouble());
  paintShip(canvas, type, sunk: sunk);
  return recorder.endRecording().toImage(
    spriteSquare * type.size,
    spriteSquare,
  );
}

Future<Uint8List> pngOf(Image image) async =>
    (await image.toByteData(format: ImageByteFormat.png))!.buffer.asUint8List();

Future<Uint8List> rgbaOf(Image image) async =>
    (await image.toByteData())!.buffer.asUint8List();
