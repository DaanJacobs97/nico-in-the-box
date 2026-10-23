import 'dart:math';

import '../../net/protocol.dart';
import '../game_session.dart';
import 'blackjack_cards.dart';

const blackjackDefinition = GameDefinition(
  id: 'blackjack',
  name: 'Blackjack',
  description: 'Beat the dealer to 21 without going over.',
  minPlayers: 2,
  maxPlayers: 8,
  category: GameCategory.gambling,
  options: [
    GameOption.choice(
      id: 'mode',
      label: 'Mode',
      description: 'Race to x winning hands, or the most chips after x hands.',
      choices: [
        GameChoice('wins', 'First to x wins'),
        GameChoice('chips', 'Most chips'),
      ],
      defaultChoice: 'wins',
    ),
    GameOption.choice(
      id: 'hands',
      label: 'x (hands)',
      choices: [
        GameChoice('3', '3'),
        GameChoice('5', '5'),
        GameChoice('10', '10'),
        GameChoice('20', '20'),
      ],
      defaultChoice: '5',
    ),
  ],
  createSession: _create,
);

GameSession _create(
  List<PlayerInfo> players,
  int round,
  Random random,
  GameOptions options,
) => BlackjackSession(
  players,
  random: random,
  round: round,
  chipsMode: options.choice('mode', 'wins') == 'chips',
  hands: int.parse(options.choice('hands', '5')),
);

const startingChips = 1000;
const minBet = 10;
const maxBet = 500;

/// Reshuffle before a hand when fewer cards than this are left.
const reshuffleBelow = 20;

/// One hand of a player: two after a split.
class _Hand {
  _Hand(this.cards, this.bet, {this.fromSplit = false});

  final List<PlayingCard> cards;
  int bet;
  final bool fromSplit;
  bool doubled = false;

  /// No more moves: stood, bust, 21, doubled, a natural or split aces.
  bool done = false;

  /// `win`, `blackjack`, `push` or `lose` once settled.
  String? result;

  int get total => handValue(cards).total;
  bool get bust => total > 21;
  bool get natural => !fromSplit && isNatural(cards);

  Json toJson() => {
    'cards': [for (final c in cards) c.toJson()],
    'total': total,
    'soft': handValue(cards).soft,
    'bet': bet,
    'doubled': doubled,
    'natural': natural,
    'done': done,
    'result': result,
  };
}

class _Seat {
  _Seat(this.player);

  final PlayerInfo player;
  int chips = startingChips;
  int wins = 0;

  /// Broke in the chips mode: watches the remaining hands.
  bool out = false;

  /// Bet placed (chips mode) or Deal tapped (wins mode) for the next hand.
  bool ready = false;
  int bet = 0;
  List<_Hand> hands = [];
}

/// Blackjack against an AI dealer, seat by seat.
///
/// Actions:
/// - between hands: `{'type': 'bet', 'amount': int}` (chips mode, 10–500 in
///   steps of 10) or `{'type': 'deal'}` (wins mode). The hand is dealt once
///   every player still in is ready.
/// - on your turn: `{'type': 'hit' | 'stand' | 'double' | 'split'}`.
///   Double (chips mode only) on a first two cards; split one pair of the same
///   rank, once. Split aces get one card each.
///
/// The dealer stands on 17 (soft 17 too) and checks for blackjack first.
/// Wins mode: a winning hand counts one win, first to [hands] wins. Chips mode:
/// a win pays 1:1, blackjack 3:2; the most chips after [hands] hands wins.
class BlackjackSession implements GameSession {
  BlackjackSession(
    List<PlayerInfo> players, {
    required this._random,
    int round = 0,
    this.chipsMode = false,
    this.hands = 5,
  }) : // The first seat to play moves round by round.
       _seats = [
         for (var i = 0; i < players.length; i++)
           _Seat(players[(i + round) % players.length]),
       ] {
    _shuffle();
  }

  /// A session whose cards come off [deck] in order (seats in [players]
  /// order, starting with the first). Intended for tests: give at least
  /// [reshuffleBelow] cards per hand, or the deck is reshuffled.
  BlackjackSession.custom(
    List<PlayerInfo> players, {
    required List<PlayingCard> deck,
    Random? random,
    this.chipsMode = false,
    this.hands = 5,
  }) : _random = random ?? Random(0),
       _seats = [for (final p in players) _Seat(p)] {
    _deck.addAll(deck.reversed);
  }

  final bool chipsMode;

  /// x: wins to reach, or hands to play.
  final int hands;

  final Random _random;
  final List<_Seat> _seats;
  final List<PlayingCard> _deck = [];
  final List<PlayingCard> _dealer = [];

  /// The dealer's second card stays hidden until the dealer plays.
  bool _holeHidden = false;
  bool _playing = false;
  int _handsPlayed = 0;
  bool _reshuffled = false;

  /// Whose turn: seat and hand index, while [_playing].
  int _seat = 0;
  int _hand = 0;
  List<String>? _winners;

  void _shuffle() {
    _deck
      ..clear()
      ..addAll(buildDeck()..shuffle(_random));
  }

  PlayingCard _draw() {
    // Only reachable with many splits and a near-empty deck: start a fresh
    // one, minus the cards on the table.
    if (_deck.isEmpty) {
      final onTable = {
        ..._dealer,
        for (final s in _seats)
          for (final h in s.hands) ...h.cards,
      };
      _deck.addAll(buildDeck().where((c) => !onTable.contains(c)));
      _deck.shuffle(_random);
    }
    return _deck.removeLast();
  }

  _Seat _seatOf(String playerId) {
    for (final s in _seats) {
      if (s.player.id == playerId) return s;
    }
    throw const GameActionException('You are not playing this game.');
  }

  Iterable<_Seat> get _inPlay => _seats.where((s) => !s.out);

  _Hand? get _currentHand => _playing && _seat < _seats.length
      ? _seats[_seat].hands.elementAtOrNull(_hand)
      : null;

  @override
  bool get isOver => _winners != null;

  @override
  void applyAction(String playerId, Json action) {
    final seat = _seatOf(playerId);
    if (isOver) throw const GameActionException('The game is over.');
    final type = action['type'];
    if (type == 'bet' || type == 'deal') {
      _ready(seat, action);
      return;
    }
    if (!const ['hit', 'stand', 'double', 'split'].contains(type)) {
      throw const GameActionException('Unknown move.');
    }
    final hand = _currentHand;
    if (hand == null || _seats[_seat] != seat) {
      throw const GameActionException("It's not your turn.");
    }
    switch (type) {
      case 'hit':
        hand.cards.add(_draw());
        if (hand.total >= 21) hand.done = true;
      case 'stand':
        hand.done = true;
      case 'double':
        if (!_canDouble(seat, hand)) {
          throw const GameActionException("You can't double now.");
        }
        seat.chips -= hand.bet;
        hand
          ..bet *= 2
          ..doubled = true
          ..cards.add(_draw())
          ..done = true;
      case 'split':
        if (!_canSplit(seat, hand)) {
          throw const GameActionException("You can't split now.");
        }
        _split(seat, hand);
    }
    _advance();
  }

  void _ready(_Seat seat, Json action) {
    if (_playing) throw const GameActionException('Wait for this hand to end.');
    if (seat.out) throw const GameActionException("You're out of chips.");
    if (seat.ready) throw const GameActionException("You're already in.");
    if (chipsMode) {
      if (action['type'] != 'bet') {
        throw const GameActionException('Place a bet to play.');
      }
      final amount = action['amount'];
      if (amount is! int ||
          amount < minBet ||
          amount > maxBet ||
          amount % minBet != 0) {
        throw const GameActionException('Bet 10 to 500, in steps of 10.');
      }
      if (amount > seat.chips) {
        throw const GameActionException("You don't have that many chips.");
      }
      seat
        ..bet = amount
        ..chips -= amount;
    } else if (action['type'] != 'deal') {
      throw const GameActionException('There are no bets in this mode.');
    }
    seat.ready = true;
    if (_inPlay.every((s) => s.ready)) _deal();
  }

  bool _canDouble(_Seat seat, _Hand hand) =>
      chipsMode &&
      hand.cards.length == 2 &&
      !(hand.fromSplit && hand.cards.first.isAce) &&
      seat.chips >= hand.bet;

  bool _canSplit(_Seat seat, _Hand hand) =>
      seat.hands.length == 1 &&
      hand.cards.length == 2 &&
      hand.cards[0].rank == hand.cards[1].rank &&
      (!chipsMode || seat.chips >= hand.bet);

  void _split(_Seat seat, _Hand hand) {
    if (chipsMode) seat.chips -= hand.bet;
    final second = hand.cards.removeLast();
    final aces = second.isAce;
    seat.hands = [
      _Hand([hand.cards.first, _draw()], hand.bet, fromSplit: true),
      _Hand([second, _draw()], hand.bet, fromSplit: true),
    ];
    for (final h in seat.hands) {
      // Split aces get one card each; a 21 stands by itself.
      if (aces || h.total == 21) h.done = true;
    }
  }

  void _deal() {
    _reshuffled = _deck.length < reshuffleBelow;
    if (_reshuffled) _shuffle();
    _dealer.clear();
    for (final s in _seats) {
      s.hands = s.out ? [] : [_Hand([], s.bet)];
    }
    for (var round = 0; round < 2; round++) {
      for (final s in _inPlay) {
        s.hands.single.cards.add(_draw());
      }
      _dealer.add(_draw());
    }
    _holeHidden = true;
    _playing = true;
    // The dealer checks for blackjack when showing an ace or a ten.
    if (_dealer.first.value >= 10 || _dealer.first.isAce) {
      if (isNatural(_dealer)) {
        _finishHand();
        return;
      }
    }
    for (final s in _inPlay) {
      if (s.hands.single.natural) s.hands.single.done = true;
    }
    _seat = 0;
    _hand = 0;
    _advance();
  }

  /// Moves the turn to the next hand that still has moves, or lets the
  /// dealer play when there is none.
  void _advance() {
    while (_seat < _seats.length) {
      final seatHands = _seats[_seat].hands;
      while (_hand < seatHands.length) {
        if (!seatHands[_hand].done) return;
        _hand++;
      }
      _seat++;
      _hand = 0;
    }
    _finishHand();
  }

  void _finishHand() {
    _holeHidden = false;
    final live = [
      for (final s in _inPlay)
        for (final h in s.hands)
          if (!h.bust && !h.natural) h,
    ];
    final dealerNatural = isNatural(_dealer);
    if (live.isNotEmpty && !dealerNatural) {
      while (handValue(_dealer).total < 17) {
        _dealer.add(_draw());
      }
    }
    final dealerTotal = handValue(_dealer).total;
    for (final s in _inPlay) {
      for (final h in s.hands) {
        h.done = true;
        h.result = h.bust
            ? 'lose'
            : dealerNatural
            ? (h.natural ? 'push' : 'lose')
            : h.natural
            ? 'blackjack'
            : dealerTotal > 21 || h.total > dealerTotal
            ? 'win'
            : h.total == dealerTotal
            ? 'push'
            : 'lose';
        switch (h.result) {
          case 'win':
            s.wins++;
            s.chips += h.bet * 2;
          case 'blackjack':
            s.wins++;
            s.chips += h.bet + h.bet * 3 ~/ 2;
          case 'push':
            s.chips += h.bet;
        }
      }
      s
        ..ready = false
        ..bet = 0;
      if (chipsMode && s.chips < minBet) s.out = true;
    }
    _playing = false;
    _handsPlayed++;
    _checkEnd();
  }

  void _checkEnd() {
    int score(_Seat s) => chipsMode ? s.chips : s.wins;
    final over = chipsMode
        ? _handsPlayed >= hands || _inPlay.isEmpty
        : _seats.any((s) => s.wins >= hands);
    if (!over) return;
    final best = _seats.map(score).reduce(max);
    _winners = [
      for (final s in _seats)
        if (score(s) == best) s.player.id,
    ];
  }

  /// What [playerId] may do right now.
  List<String> _actionsFor(String playerId) {
    if (isOver) return const [];
    final seat = _seats.where((s) => s.player.id == playerId).firstOrNull;
    if (seat == null || seat.out) return const [];
    if (!_playing) {
      if (seat.ready) return const [];
      return chipsMode ? const ['bet'] : const ['deal'];
    }
    final hand = _currentHand;
    if (hand == null || _seats[_seat] != seat) return const [];
    return [
      'hit',
      'stand',
      if (_canDouble(seat, hand)) 'double',
      if (_canSplit(seat, hand)) 'split',
    ];
  }

  @override
  Json tableView() => {
    'mode': chipsMode ? 'chips' : 'wins',
    'hands': hands,
    'handsPlayed': _handsPlayed,
    'playing': _playing,
    'turn': _currentHand == null
        ? null
        : {'player': _seats[_seat].player.id, 'hand': _hand},
    'dealer': {
      // While hidden, only the up card is sent: never the hole card.
      'cards': [
        for (final c in _holeHidden ? _dealer.take(1) : _dealer) c.toJson(),
      ],
      'hidden': _holeHidden,
      'total': _dealer.isEmpty
          ? 0
          : handValue(_holeHidden ? _dealer.sublist(0, 1) : _dealer).total,
    },
    'seats': [
      for (final s in _seats)
        {
          'id': s.player.id,
          'chips': s.chips,
          'wins': s.wins,
          'out': s.out,
          'ready': s.ready,
          'bet': s.bet,
          'hands': [for (final h in s.hands) h.toJson()],
        },
    ],
    'cardsLeft': _deck.length,
    'reshuffled': _reshuffled,
    'winners': _winners,
  };

  /// Everything is face up except the hole card, so a player sees the table
  /// plus what they may do.
  @override
  Json viewFor(String playerId) => {
    ...tableView(),
    'actions': _actionsFor(playerId),
  };

  @override
  Json? get result {
    final winners = _winners;
    if (winners == null) return null;
    final names = [
      for (final id in winners)
        _seats.firstWhere((s) => s.player.id == id).player.nickname,
    ];
    final how = chipsMode ? 'most chips' : 'first to $hands wins';
    return {
      'winnerIds': winners,
      'summary': names.length == 1
          ? '${names.single} wins ($how)!'
          : '${names.join(' and ')} share the win ($how)!',
    };
  }
}
