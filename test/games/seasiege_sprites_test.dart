// The browser screen's ship PNGs must match the Flutter painter, so the two
// screens can't drift apart. Regenerate with
// `flutter test tool/sprites/draw_sprites_test.dart`.
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/seasiege/seasiege_fleet.dart';

import '../../tool/sprites/ship_sprites.dart';

void main() {
  for (final type in ShipType.values) {
    for (final sunk in [false, true]) {
      final name = spriteName(type, sunk: sunk);
      test('$name is up to date', () async {
        final file = File('$spriteDir/$name');
        expect(file.existsSync(), isTrue, reason: 'run the sprite tool');
        final codec = await instantiateImageCodec(file.readAsBytesSync());
        final saved = (await codec.getNextFrame()).image;
        final fresh = await renderShip(type, sunk: sunk);
        expect(
          (saved.width, saved.height),
          (fresh.width, fresh.height),
          reason: 'run the sprite tool',
        );
        // Allow for anti-aliasing differences between machines.
        final a = await rgbaOf(saved);
        final b = await rgbaOf(fresh);
        var diff = 0;
        for (var i = 0; i < a.length; i++) {
          diff += (a[i] - b[i]).abs();
        }
        expect(diff / a.length, lessThan(2), reason: 'run the sprite tool');
      });
    }
  }
}
