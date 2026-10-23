import '../../net/protocol.dart';

enum Suit { spades, hearts, diamonds, clubs }

/// One card of a standard 52-card deck.
class PlayingCard {
  const PlayingCard(this.rank, this.suit);

  /// 1 = ace, 2–10, 11 = jack, 12 = queen, 13 = king.
  final int rank;
  final Suit suit;

  /// Unique within one deck, so views can key cards.
  int get id => suit.index * 13 + rank - 1;

  /// Blackjack value; an ace counts 1 here (see [handValue]).
  int get value => rank > 10 ? 10 : rank;

  bool get isAce => rank == 1;

  String get rankLabel => switch (rank) {
    1 => 'A',
    11 => 'J',
    12 => 'Q',
    13 => 'K',
    _ => '$rank',
  };

  Json toJson() => {'rank': rank, 'suit': suit.name};

  factory PlayingCard.fromJson(Json json) => PlayingCard(
    json['rank']! as int,
    Suit.values.byName(json['suit']! as String),
  );

  @override
  bool operator ==(Object other) =>
      other is PlayingCard && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => id;

  @override
  String toString() => '$rankLabel${suit.name[0]}';
}

/// All 52 cards, in order (shuffle before use).
List<PlayingCard> buildDeck() => [
  for (final suit in Suit.values)
    for (var rank = 1; rank <= 13; rank++) PlayingCard(rank, suit),
];

/// The best total of [cards] and whether it is soft (an ace counted as 11).
({int total, bool soft}) handValue(List<PlayingCard> cards) {
  var total = 0;
  var aces = false;
  for (final c in cards) {
    total += c.value;
    if (c.isAce) aces = true;
  }
  // One ace as 11 when it doesn't bust; two would be 22.
  if (aces && total + 10 <= 21) return (total: total + 10, soft: true);
  return (total: total, soft: false);
}

/// Two cards worth 21. A hand made by splitting never counts as one.
bool isNatural(List<PlayingCard> cards) =>
    cards.length == 2 && handValue(cards).total == 21;
