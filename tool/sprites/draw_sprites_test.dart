// Writes the Sea Siege ship sprites for the browser shared screen. After
// changing paintShip (packages/nico_shared/.../seasiege_sprites.dart), run:
//
//   flutter test tool/sprites/draw_sprites_test.dart
//
// test/games/seasiege_sprites_test.dart fails until you do.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/seasiege/seasiege_fleet.dart';

import 'ship_sprites.dart';

void main() {
  test('draw ship sprites', () async {
    Directory(spriteDir).createSync(recursive: true);
    for (final type in ShipType.values) {
      for (final sunk in [false, true]) {
        final image = await renderShip(type, sunk: sunk);
        File('$spriteDir/${spriteName(type, sunk: sunk)}')
            .writeAsBytesSync(await pngOf(image));
      }
    }
  });
}
