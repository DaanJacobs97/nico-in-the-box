import 'package:flutter/material.dart';

import 'clash_card.dart';

/// Card colors on screen.
Color colorOf(CardColor color) => switch (color) {
  CardColor.red => const Color(0xFFE53935),
  CardColor.yellow => const Color(0xFFFDD835),
  CardColor.green => const Color(0xFF43A047),
  CardColor.blue => const Color(0xFF1E88E5),
  CardColor.wild => const Color(0xFF212121),
};

/// One card, [width] wide and half again as tall. Wild cards are a grid of
/// the four colors (with "+4" on a Wild +4).
class ClashCardFace extends StatelessWidget {
  const ClashCardFace({
    super.key,
    required this.card,
    required this.width,
    this.activeColor,
    this.onTap,
  });

  final ClashCard card;
  final double width;

  /// For a wild on the discard pile, the color that was chosen: its square
  /// stays bright, the others fade, and the border takes the color.
  final CardColor? activeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ring = card.isWild && activeColor != null
        ? colorOf(activeColor!)
        : Colors.white;

    return Material(
      color: colorOf(card.color),
      elevation: onTap != null ? 6 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(width * 0.14),
        side: BorderSide(color: ring, width: width * 0.05),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: width * 1.5,
          child: card.isWild ? _wild() : _plain(),
        ),
      ),
    );
  }

  Widget _plain() {
    final symbol = switch (card.kind) {
      CardKind.number => '${card.value}',
      CardKind.skip => '⊘',
      CardKind.reverse => '⇄',
      _ => '+2',
    };
    return Center(
      child: Text(
        symbol,
        style: TextStyle(
          color: card.color == CardColor.yellow ? Colors.black87 : Colors.white,
          fontSize: width * 0.42,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _wild() {
    final gap = width * 0.04;
    Widget square(CardColor color) => Expanded(
      child: Padding(
        padding: EdgeInsets.all(gap / 2),
        child: DecoratedBox(
          key: ValueKey('wild-${color.name}'),
          decoration: BoxDecoration(
            color: activeColor == null || activeColor == color
                ? colorOf(color)
                : Color.lerp(colorOf(color), colorOf(CardColor.wild), 0.7),
            borderRadius: BorderRadius.circular(width * 0.06),
          ),
        ),
      ),
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: EdgeInsets.all(gap * 1.5),
          child: Column(
            children: [
              for (final row in [
                [CardColor.red, CardColor.yellow],
                [CardColor.green, CardColor.blue],
              ])
                Expanded(
                  child: Row(children: [for (final c in row) square(c)]),
                ),
            ],
          ),
        ),
        if (card.kind == CardKind.wildDrawFour)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: width * 0.08,
              vertical: width * 0.02,
            ),
            decoration: BoxDecoration(
              color: colorOf(CardColor.wild),
              borderRadius: BorderRadius.circular(width),
              border: Border.all(color: Colors.white, width: width * 0.03),
            ),
            child: Text(
              '+4',
              style: TextStyle(
                color: Colors.white,
                fontSize: width * 0.34,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ),
      ],
    );
  }
}
