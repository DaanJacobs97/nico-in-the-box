import 'dart:math';

import 'package:flutter/material.dart';

import 'seasiege_fleet.dart';

/// Ship colours, intact or burnt out.
class _Palette {
  const _Palette({
    required this.hull,
    required this.deck,
    required this.dark,
    required this.line,
  });

  final Color hull;
  final Color deck;
  final Color dark;
  final Color line;
}

const _intact = _Palette(
  hull: Color(0xFF90A4AE),
  deck: Color(0xFFCFD8DC),
  dark: Color(0xFF546E7A),
  line: Color(0xFF263238),
);

const _wreck = _Palette(
  hull: Color(0xFF6D4C41),
  deck: Color(0xFF8D6E63),
  dark: Color(0xFF4E342E),
  line: Color(0xFF1B0F0B),
);

/// Draws a top-down [type] ship, bow to the right, in a box `size` squares
/// long and one square high, where a square is 1×1 (scale the canvas first).
/// A [sunk] ship is a burnt-out wreck. Used by [ShipSprite] and, through
/// tool/sprites/, for the browser screen's PNGs, so both look the same.
void paintShip(Canvas canvas, ShipType type, {bool sunk = false}) {
  final p = sunk ? _wreck : _intact;
  final l = type.size.toDouble();
  final fill = Paint();
  final line = Paint()
    ..color = p.line
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.05
    ..strokeJoin = StrokeJoin.round;

  void shape(Path path, Color color) => canvas
    ..drawPath(path, fill..color = color)
    ..drawPath(path, line);

  void block(double x, double y, double w, double h, Color color) => shape(
    Path()..addRRect(
      RRect.fromLTRBR(x, y, x + w, y + h, const Radius.circular(0.08)),
    ),
    color,
  );

  void turret(double x, {bool aft = false}) {
    final dir = aft ? -1.0 : 1.0;
    for (final y in [0.45, 0.55]) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x + dir * 0.36, y),
        Paint()
          ..color = p.line
          ..strokeWidth = 0.06,
      );
    }
    shape(
      Path()..addOval(Rect.fromCircle(center: Offset(x, 0.5), radius: 0.15)),
      p.dark,
    );
  }

  void funnel(double x, [double y = 0.5, double r = 0.1]) => shape(
    Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r)),
    p.line,
  );

  switch (type) {
    case ShipType.carrier:
      shape(_hull(l, top: 0.1, bottom: 0.9, bow: 0.7), p.hull);
      // Flight deck with a dashed runway.
      block(0.25, 0.18, l - 0.85, 0.64, p.dark);
      final dash = Paint()
        ..color = p.deck
        ..strokeWidth = 0.05;
      for (var x = 0.45; x < l - 0.9; x += 0.4) {
        canvas.drawLine(Offset(x, 0.5), Offset(x + 0.22, 0.5), dash);
      }
      // Island on the side, and two parked planes.
      block(2.9, 0.06, 0.7, 0.2, p.hull);
      funnel(3.25, 0.16, 0.07);
      _plane(canvas, const Offset(1.1, 0.33), p.deck);
      _plane(canvas, const Offset(1.9, 0.67), p.deck);
    case ShipType.battleship:
      shape(_hull(l, top: 0.14, bottom: 0.86, bow: 0.9), p.hull);
      shape(_hull(l, top: 0.24, bottom: 0.76, bow: 0.8, inset: 0.15), p.deck);
      turret(0.75, aft: true);
      block(1.3, 0.3, 1.0, 0.4, p.hull);
      funnel(1.6);
      funnel(2.0);
      turret(2.75);
      turret(3.2);
    case ShipType.cruiser:
      shape(_hull(l, top: 0.18, bottom: 0.82, bow: 0.8), p.hull);
      shape(_hull(l, top: 0.27, bottom: 0.73, bow: 0.7, inset: 0.14), p.deck);
      turret(0.62, aft: true);
      block(1.05, 0.32, 0.75, 0.36, p.hull);
      funnel(1.35);
      turret(2.2);
    case ShipType.submarine:
      shape(_hull(l, top: 0.3, bottom: 0.7, bow: 0.65), p.dark);
      // Tail fins, then the conning tower with its periscope.
      shape(
        Path()
          ..moveTo(0.35, 0.5)
          ..lineTo(0.08, 0.2)
          ..lineTo(0.2, 0.5)
          ..lineTo(0.08, 0.8)
          ..close(),
        p.dark,
      );
      block(1.25, 0.38, 0.6, 0.24, p.hull);
      canvas.drawCircle(const Offset(1.7, 0.5), 0.05, fill..color = p.line);
    case ShipType.destroyer:
      shape(_hull(l, top: 0.22, bottom: 0.78, bow: 0.7), p.hull);
      shape(_hull(l, top: 0.31, bottom: 0.69, bow: 0.6, inset: 0.12), p.deck);
      block(0.45, 0.35, 0.45, 0.3, p.hull);
      funnel(0.68);
      turret(1.35);
  }

  if (sunk) _scorch(canvas, l);
}

/// A hull from stern (left) to a pointed bow (right) between [top] and
/// [bottom]; [bow] is how long the pointed part is.
Path _hull(
  double l, {
  required double top,
  required double bottom,
  required double bow,
  double inset = 0.06,
}) {
  final mid = (top + bottom) / 2;
  final stern = inset;
  final round = (bottom - top) * 0.3;
  return Path()
    ..moveTo(stern + round, top)
    ..lineTo(l - bow, top)
    ..quadraticBezierTo(l - inset - bow * 0.3, top, l - inset, mid)
    ..quadraticBezierTo(l - inset - bow * 0.3, bottom, l - bow, bottom)
    ..lineTo(stern + round, bottom)
    ..quadraticBezierTo(stern, bottom, stern, mid)
    ..quadraticBezierTo(stern, top, stern + round, top)
    ..close();
}

/// A small plane, nose to the right.
void _plane(Canvas canvas, Offset at, Color color) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = 0.06
    ..strokeCap = StrokeCap.round;
  canvas
    ..drawLine(at + const Offset(-0.15, 0), at + const Offset(0.15, 0), paint)
    ..drawLine(
      at + const Offset(0.02, -0.13),
      at + const Offset(0.02, 0.13),
      paint,
    )
    ..drawLine(
      at + const Offset(-0.13, -0.06),
      at + const Offset(-0.13, 0.06),
      paint,
    );
}

/// Soot and a few embers over a wreck. Fixed spots, so every wreck of a
/// type looks the same (and the PNGs are reproducible).
void _scorch(Canvas canvas, double l) {
  final random = Random(l.toInt());
  for (var i = 0; i < l * 2; i++) {
    final x = 0.3 + random.nextDouble() * (l - 0.8);
    final y = 0.3 + random.nextDouble() * 0.4;
    canvas.drawCircle(
      Offset(x, y),
      0.1 + random.nextDouble() * 0.1,
      Paint()..color = const Color(0x99000000),
    );
  }
  for (var i = 0; i < l; i++) {
    final x = 0.4 + random.nextDouble() * (l - 1);
    final y = 0.35 + random.nextDouble() * 0.3;
    canvas.drawCircle(
      Offset(x, y),
      0.05,
      Paint()..color = const Color(0xFFFF7043),
    );
  }
}

/// A [ship] drawn across the squares it covers; size it to the ship's
/// squares (`size` × 1, or 1 × `size` when vertical).
class ShipSprite extends StatelessWidget {
  const ShipSprite({super.key, required this.ship, this.sunk = false});

  final Ship ship;
  final bool sunk;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ShipPainter(ship.type, ship.vertical, sunk));
}

class _ShipPainter extends CustomPainter {
  _ShipPainter(this.type, this.vertical, this.sunk);

  final ShipType type;
  final bool vertical;
  final bool sunk;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (vertical) {
      // Turn a quarter clockwise: the stern goes to the top.
      canvas
        ..translate(size.width, 0)
        ..rotate(pi / 2);
    }
    final square = vertical ? size.width : size.height;
    canvas.scale(square);
    paintShip(canvas, type, sunk: sunk);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShipPainter old) =>
      old.type != type || old.vertical != vertical || old.sunk != sunk;
}
