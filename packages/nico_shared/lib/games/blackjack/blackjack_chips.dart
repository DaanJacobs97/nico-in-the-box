import 'dart:math';

import 'package:flutter/material.dart';

/// Chip values, biggest first. Blackjack pays 3:2, so a 5 can turn up.
const chipValues = [500, 100, 50, 10, 5];

Color chipColor(int value) => switch (value) {
  500 => const Color(0xFF7B1FA2),
  100 => const Color(0xFF212121),
  50 => const Color(0xFFD32F2F),
  10 => const Color(0xFF1565C0),
  _ => const Color(0xFF2E7D32),
};

/// [amount] as the fewest chips: `{500: 1, 100: 2, …}`, biggest first.
Map<int, int> chipBreakdown(int amount) {
  final out = <int, int>{};
  var left = amount;
  for (final value in chipValues) {
    if (left >= value) {
      out[value] = left ~/ value;
      left %= value;
    }
  }
  return out;
}

/// [amount] drawn as stacks of chips, one stack per value, biggest left.
class ChipStacks extends StatelessWidget {
  const ChipStacks({super.key, required this.amount, required this.size});

  final int amount;

  /// Width of one chip.
  final double size;

  /// Taller stacks are capped; the label says the exact amount anyway.
  static const maxPerStack = 8;

  @override
  Widget build(BuildContext context) {
    final stacks = chipBreakdown(amount);
    final step = size * 0.16;
    return Row(
      key: ValueKey('bj-chips-$amount'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final MapEntry(key: value, value: count) in stacks.entries)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.04),
            child: SizedBox(
              width: size,
              height: size + step * (min(count, maxPerStack) - 1),
              child: Stack(
                children: [
                  for (var i = 0; i < min(count, maxPerStack); i++)
                    Positioned(
                      left: 0,
                      bottom: step * i,
                      child: CasinoChip(value: value, size: size),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One casino chip seen from slightly above: a coloured disc with white
/// edge spots, an inner ring and its value.
class CasinoChip extends StatelessWidget {
  const CasinoChip({super.key, required this.value, required this.size});

  final int value;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _ChipPainter(chipColor(value), '$value'),
  );
}

class _ChipPainter extends CustomPainter {
  _ChipPainter(this.color, this.label);

  final Color color;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    canvas
      ..drawCircle(
        c.translate(0, r * 0.08),
        r,
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      )
      ..drawCircle(c, r, Paint()..color = color);
    // Six white spots around the edge.
    final spot = Paint()..color = Colors.white;
    for (var i = 0; i < 6; i++) {
      final a = i * pi / 3;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.84),
        a - 0.22,
        0.44,
        false,
        spot
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.3,
      );
    }
    canvas
      ..drawCircle(c, r * 0.62, Paint()..color = color)
      ..drawCircle(
        c,
        r * 0.62,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.06,
      );
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: r * (label.length > 2 ? 0.5 : 0.62),
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, c - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(_ChipPainter old) =>
      old.color != color || old.label != label;
}

/// "Bet: 100 chips" with the chips drawn beside it.
class BetChips extends StatelessWidget {
  const BetChips({
    super.key,
    required this.amount,
    required this.size,
    this.doubled = false,
  });

  final int amount;
  final double size;
  final bool doubled;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: size * 0.25,
    children: [
      ChipStacks(amount: amount, size: size),
      Text(
        'Bet: $amount chips${doubled ? ' (doubled)' : ''}',
        style: TextStyle(fontSize: size * 0.5),
      ),
    ],
  );
}

/// A subtle blackjack table behind [child]: dark green felt and a faint gold
/// arc for the table's edge, curving around the players.
class BlackjackFelt extends StatelessWidget {
  const BlackjackFelt({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The felt is dark in light mode too, so what's on it uses dark colours.
    final theme = Theme.of(context);
    final dark = ColorScheme.fromSeed(
      seedColor: theme.colorScheme.primary,
      brightness: Brightness.dark,
    );
    return CustomPaint(
      key: const ValueKey('bj-felt'),
      painter: _FeltPainter(),
      child: Theme(
        data: theme.copyWith(colorScheme: dark),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: dark.onSurface),
          child: child,
        ),
      ),
    );
  }
}

class _FeltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.topCenter,
          radius: 1.3,
          colors: [Color(0xFF0F4A37), Color(0xFF0A3326), Color(0xFF071F18)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
    // The lower half of a wide oval: the table's edge seen from the dealer.
    final edge = Rect.fromLTRB(
      -size.width * 0.1,
      -size.height * 0.55,
      size.width * 1.1,
      size.height * 0.45,
    );
    canvas.drawArc(
      edge,
      0,
      pi,
      false,
      Paint()
        ..color = const Color(0x2EFFD778)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FeltPainter old) => false;
}
