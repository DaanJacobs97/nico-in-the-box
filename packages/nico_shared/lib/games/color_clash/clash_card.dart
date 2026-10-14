import '../../net/protocol.dart';

enum CardColor { red, yellow, green, blue, wild }

enum CardKind { number, skip, reverse, drawTwo, wild, wildDrawFour }

/// The four colors a Wild can be set to.
const playableColors = [
  CardColor.red,
  CardColor.yellow,
  CardColor.green,
  CardColor.blue,
];

class ClashCard {
  const ClashCard({
    required this.id,
    required this.color,
    required this.kind,
    this.value,
  });

  /// Unique within a deck, so players refer to exact cards in actions.
  final int id;
  final CardColor color;
  final CardKind kind;

  /// 0–9 for number cards, otherwise null.
  final int? value;

  bool get isWild => kind == CardKind.wild || kind == CardKind.wildDrawFour;

  /// Whether this card may go on [top] when the active color is [color].
  bool canPlayOn(ClashCard top, CardColor color) {
    if (isWild) return true;
    if (this.color == color) return true;
    if (kind != top.kind) return false;
    return kind != CardKind.number || value == top.value;
  }

  Json toJson() => {
    'id': id,
    'color': color.name,
    'kind': kind.name,
    'value': value,
  };

  factory ClashCard.fromJson(Json json) => ClashCard(
    id: json['id']! as int,
    color: CardColor.values.byName(json['color']! as String),
    kind: CardKind.values.byName(json['kind']! as String),
    value: json['value'] as int?,
  );

  String get label => switch (kind) {
    CardKind.number => '$value',
    CardKind.skip => 'Skip',
    CardKind.reverse => 'Reverse',
    CardKind.drawTwo => '+2',
    CardKind.wild => 'Wild',
    CardKind.wildDrawFour => 'Wild +4',
  };

  @override
  String toString() => isWild
      ? label
      : '${color.name[0].toUpperCase()}${color.name.substring(1)} $label';
}

/// The standard 108-card deck: per color one 0, two each of 1–9, Skip,
/// Reverse and Draw Two; plus four Wild and four Wild Draw Four.
List<ClashCard> buildDeck() {
  final cards = <ClashCard>[];
  var id = 0;
  void add(CardColor color, CardKind kind, [int? value]) =>
      cards.add(ClashCard(id: id++, color: color, kind: kind, value: value));

  for (final color in playableColors) {
    add(color, CardKind.number, 0);
    for (var copy = 0; copy < 2; copy++) {
      for (var value = 1; value <= 9; value++) {
        add(color, CardKind.number, value);
      }
      add(color, CardKind.skip);
      add(color, CardKind.reverse);
      add(color, CardKind.drawTwo);
    }
  }
  for (var i = 0; i < 4; i++) {
    add(CardColor.wild, CardKind.wild);
    add(CardColor.wild, CardKind.wildDrawFour);
  }
  return cards;
}
