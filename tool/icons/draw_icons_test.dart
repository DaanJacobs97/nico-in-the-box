// Draws the app icons as PNGs in icons/, which flutter_launcher_icons turns
// into every platform's icon files. Change the art here, then run:
//
//   flutter test tool/icons/draw_icons_test.dart
//   dart run flutter_launcher_icons                       # app (repo root)
//   cd caster && dart run flutter_launcher_icons          # Caster
//   cd web_client && dart run flutter_launcher_icons      # browser client
//
// Drawn with plain shapes (no fonts), so it renders the same everywhere.
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

const _size = 1024.0;
const _purpleLight = Color(0xFF8B6CF0);
const _purpleDark = Color(0xFF3B2A8C);
const _gold = Color(0xFFFFC940);
const _goldDark = Color(0xFFD99A00);
const _white = Color(0xFFFFFFFF);
const _screen = Color(0xFF15121D);

/// The adaptive-icon background colour (Android), between the two purples.
const adaptiveBackground = '#5A3FC0';

void _background(Canvas canvas) {
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, _size, _size),
    Paint()
      ..shader = Gradient.linear(Offset.zero, const Offset(_size, _size), [
        _purpleLight,
        _purpleDark,
      ]),
  );
}

Path _star(Offset center, double outer, double inner) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final radius = i.isEven ? outer : inner;
    final angle = -pi / 2 + i * pi / 5;
    final point = center + Offset(cos(angle), sin(angle)) * radius;
    i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
  }
  return path..close();
}

/// An open box with a star springing out, in a 1024 square, scaled around
/// the centre by [scale].
void _boxAndStar(
  Canvas canvas, {
  double scale = 1,
  Offset shift = Offset.zero,
}) {
  canvas
    ..save()
    ..translate(_size / 2 + shift.dx, _size / 2 + shift.dy)
    ..scale(scale)
    ..translate(-_size / 2, -_size / 2);
  final stroke = Paint()
    ..color = _white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 34
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  // Spring from the box to the star.
  final spring = Path()..moveTo(512, 600);
  for (var i = 0; i < 4; i++) {
    spring.lineTo(i.isEven ? 452 : 572, 560 - i * 50);
  }
  spring.lineTo(512, 380);
  canvas.drawPath(spring, stroke);
  // Star.
  canvas.drawPath(
    _star(const Offset(512, 300), 170, 72),
    Paint()..color = _white,
  );
  // Open lid, tipped back to the left.
  canvas
    ..save()
    ..translate(300, 590)
    ..rotate(-0.55)
    ..drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-30, -60, 250, 60),
        const Radius.circular(18),
      ),
      Paint()..color = _goldDark,
    )
    ..restore();
  // Box body with a darker band, so it reads as a box at small sizes.
  canvas
    ..drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(292, 600, 440, 300),
        const Radius.circular(36),
      ),
      Paint()..color = _gold,
    )
    ..drawRect(
      const Rect.fromLTWH(292, 600, 440, 56),
      Paint()..color = _goldDark,
    )
    ..restore();
}

/// A TV showing the box, for the Caster.
void _tv(Canvas canvas, {double scale = 1}) {
  canvas
    ..save()
    ..translate(_size / 2, _size / 2)
    ..scale(scale)
    ..translate(-_size / 2, -_size / 2);
  final frame = RRect.fromRectAndRadius(
    const Rect.fromLTWH(152, 212, 720, 500),
    const Radius.circular(56),
  );
  canvas
    ..drawRRect(frame, Paint()..color = _white)
    ..drawRRect(frame.deflate(34), Paint()..color = _screen);
  // Stand.
  canvas.drawPath(
    Path()
      ..moveTo(442, 712)
      ..lineTo(582, 712)
      ..lineTo(642, 832)
      ..lineTo(382, 832)
      ..close(),
    Paint()..color = _white,
  );
  canvas.restore();
  // The box and star, small, on the screen.
  _boxAndStar(canvas, scale: 0.42 * scale, shift: Offset(0, -50 * scale));
}

Future<void> _write(String name, void Function(Canvas) paint) async {
  final recorder = PictureRecorder();
  paint(Canvas(recorder));
  final image = await recorder.endRecording().toImage(
    _size.toInt(),
    _size.toInt(),
  );
  final png = await image.toByteData(format: ImageByteFormat.png);
  File('icons/$name.png')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  // Android adaptive icons show only the middle ~66% of the foreground (and
  // crop it to a circle or squircle), so the art is scaled to fill about that.

  test('draw icons', () async {
    await _write('app_icon', (c) {
      _background(c);
      _boxAndStar(c, scale: 0.92);
    });
    await _write('app_icon_foreground', (c) => _boxAndStar(c, scale: 0.8));
    await _write('caster_icon', (c) {
      _background(c);
      _tv(c);
    });
    await _write('caster_icon_foreground', (c) => _tv(c, scale: 0.88));
  });
}
