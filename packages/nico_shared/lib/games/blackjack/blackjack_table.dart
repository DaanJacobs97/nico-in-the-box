import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';
import 'blackjack_cards.dart';

/// Blackjack on the shared screen: dealer, every seat, whose turn.
class BlackjackTable extends StatelessWidget {
  const BlackjackTable({super.key, required this.ctx});

  final TableContext ctx;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => BlackjackTableArea(
      table: ctx.table,
      nameOf: ctx.nicknameOf,
      // Grow with the screen; a TV gets roughly double size.
      scale: (constraints.biggest.shortestSide / 450).clamp(1.0, 2.2),
    ),
  );
}

/// The public table: a header line, the dealer and every seat. Used on the
/// shared screen and inside a player's full view.
class BlackjackTableArea extends StatelessWidget {
  const BlackjackTableArea({
    super.key,
    required this.table,
    required this.nameOf,
    this.myId,
    this.scale = 1,
  });

  final Json table;
  final String Function(String id) nameOf;

  /// The viewer's seat is marked "You".
  final String? myId;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final seats = (table['seats']! as List<Object?>).cast<Json>();
    final turn = table['turn'] as Json?;
    return SingleChildScrollView(
      padding: EdgeInsets.all(12 * scale),
      child: Column(
        children: [
          Text(
            blackjackHeader(table),
            key: const ValueKey('bj-header'),
            style: TextStyle(fontSize: 14 * scale),
          ),
          SizedBox(height: 8 * scale),
          BlackjackDealer(dealer: table['dealer']! as Json, scale: scale),
          SizedBox(height: 12 * scale),
          Wrap(
            spacing: 10 * scale,
            runSpacing: 10 * scale,
            alignment: WrapAlignment.center,
            children: [
              for (final seat in seats)
                BlackjackSeat(
                  key: ValueKey('bj-seat-${seat['id']}'),
                  seat: seat,
                  name: seat['id'] == myId
                      ? 'You'
                      : nameOf(seat['id']! as String),
                  chipsMode: table['mode'] == 'chips',
                  turnHand: turn?['player'] == seat['id']
                      ? turn!['hand'] as int
                      : null,
                  between: table['playing'] != true,
                  scale: scale,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Most chips · 3 of 10 hands played · 31 cards left".
String blackjackHeader(Json table) {
  final x = table['hands']! as int;
  final played = table['handsPlayed']! as int;
  final mode = table['mode'] == 'chips'
      ? 'Most chips · $played of $x hands played'
      : 'First to $x wins · $played hands played';
  final reshuffled = table['reshuffled'] == true && table['playing'] == true
      ? ' (reshuffled)'
      : '';
  return '$mode · ${table['cardsLeft']} cards left$reshuffled';
}

class BlackjackDealer extends StatelessWidget {
  const BlackjackDealer({super.key, required this.dealer, this.scale = 1});

  final Json dealer;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final c in dealer['cards']! as List<Object?>)
        PlayingCard.fromJson(c! as Json),
    ];
    final hidden = dealer['hidden'] == true;
    return Column(
      key: const ValueKey('bj-dealer'),
      children: [
        Text(
          cards.isEmpty
              ? 'Dealer'
              : 'Dealer · ${dealer['total']}${hidden ? ' + ?' : ''}',
          style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 4 * scale),
        if (cards.isEmpty)
          SizedBox(height: 60 * scale)
        else
          CardRow(cards: cards, hidden: hidden ? 1 : 0, width: 44 * scale),
      ],
    );
  }
}

/// One player's seat: name, chips or wins, bet, and their hands.
class BlackjackSeat extends StatelessWidget {
  const BlackjackSeat({
    super.key,
    required this.seat,
    required this.name,
    required this.chipsMode,
    required this.between,
    this.turnHand,
    this.scale = 1,
  });

  final Json seat;
  final String name;
  final bool chipsMode;

  /// Between hands: show who is ready.
  final bool between;

  /// The hand being played, when it's this seat's turn.
  final int? turnHand;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hands = (seat['hands']! as List<Object?>).cast<Json>();
    final score = chipsMode ? '${seat['chips']} chips' : '${seat['wins']} wins';
    final extra = seat['out'] == true
        ? ' · out'
        : between && seat['ready'] == true
        ? ' · ready'
        : '';
    return Container(
      width: 170 * scale,
      padding: EdgeInsets.all(8 * scale),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(
          color: turnHand != null ? scheme.primary : Colors.transparent,
          width: 3,
        ),
      ),
      child: Column(
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.bold),
          ),
          Text('$score$extra', style: TextStyle(fontSize: 12 * scale)),
          for (var i = 0; i < hands.length; i++)
            BlackjackHand(
              hand: hands[i],
              active: turnHand == i,
              showBet: chipsMode,
              width: 30 * scale,
            ),
        ],
      ),
    );
  }
}

/// Cards, total and (once settled) the result of one hand.
class BlackjackHand extends StatelessWidget {
  const BlackjackHand({
    super.key,
    required this.hand,
    required this.width,
    this.active = false,
    this.showBet = false,
  });

  final Json hand;
  final double width;
  final bool active;
  final bool showBet;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final c in hand['cards']! as List<Object?>)
        PlayingCard.fromJson(c! as Json),
    ];
    final result = hand['result'] as String?;
    final total = hand['natural'] == true
        ? 'Blackjack'
        : '${hand['total']}${hand['total']! as int > 21 ? ' bust' : ''}';
    final bet = showBet
        ? ' · ${hand['bet']}${hand['doubled'] == true ? ' (x2)' : ''}'
        : '';
    return Padding(
      padding: EdgeInsets.only(top: width * 0.2),
      child: Column(
        children: [
          CardRow(cards: cards, width: width),
          Text(
            '$total$bet',
            style: TextStyle(
              fontSize: width * 0.42,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (result != null) _ResultBadge(result: result, size: width * 0.4),
        ],
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.result, required this.size});

  final String result;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (result) {
      'blackjack' => ('Blackjack!', const Color(0xFFFFB300)),
      'win' => ('Win', const Color(0xFF43A047)),
      'push' => ('Push', const Color(0xFF757575)),
      _ => ('Lose', const Color(0xFFE53935)),
    };
    return Container(
      margin: EdgeInsets.only(top: size * 0.3),
      padding: EdgeInsets.symmetric(horizontal: size * 0.6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Cards side by side, overlapping a little; the last [hidden] face down.
class CardRow extends StatelessWidget {
  const CardRow({
    super.key,
    required this.cards,
    required this.width,
    this.hidden = 0,
  });

  final List<PlayingCard> cards;
  final double width;
  final int hidden;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: width * 0.12,
    runSpacing: width * 0.12,
    children: [
      for (final c in cards) PlayingCardFace(card: c, width: width),
      for (var i = 0; i < hidden; i++) PlayingCardFace(width: width),
    ],
  );
}

/// A playing card, [width] wide; face down without a [card].
class PlayingCardFace extends StatelessWidget {
  const PlayingCardFace({super.key, this.card, required this.width});

  final PlayingCard? card;
  final double width;

  static String suitSymbol(Suit suit) => switch (suit) {
    Suit.spades => '♠',
    Suit.hearts => '♥',
    Suit.diamonds => '♦',
    Suit.clubs => '♣',
  };

  @override
  Widget build(BuildContext context) {
    final card = this.card;
    final radius = BorderRadius.circular(width * 0.12);
    if (card == null) {
      return Container(
        key: const ValueKey('bj-card-back'),
        width: width,
        height: width * 1.4,
        decoration: BoxDecoration(
          color: const Color(0xFF1565C0),
          borderRadius: radius,
          border: Border.all(color: Colors.white, width: width * 0.06),
        ),
      );
    }
    final red = card.suit == Suit.hearts || card.suit == Suit.diamonds;
    final color = red ? const Color(0xFFD32F2F) : const Color(0xFF212121);
    // U+FE0E asks for the plain glyph; some platforms draw emoji suits.
    final suit = '${suitSymbol(card.suit)}︎';
    return Container(
      key: ValueKey('bj-card-${card.id}'),
      width: width,
      height: width * 1.4,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(color: const Color(0xFFBDBDBD)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            card.rankLabel,
            style: TextStyle(
              color: color,
              fontSize: width * 0.45,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          Text(
            suit,
            style: TextStyle(color: color, fontSize: width * 0.4, height: 1),
          ),
        ],
      ),
    );
  }
}
