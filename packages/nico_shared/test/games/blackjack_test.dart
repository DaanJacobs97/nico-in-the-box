import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/blackjack/blackjack_cards.dart';
import 'package:nico_shared/games/blackjack/blackjack_game.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/net/protocol.dart';

List<PlayerInfo> _players(int count) => [
  for (var i = 1; i <= count; i++) PlayerInfo(id: 'p$i', nickname: 'Player $i'),
];

/// A card by rank (1 = ace … 13 = king); suits only tell copies apart.
PlayingCard c(int rank, [Suit suit = Suit.spades]) => PlayingCard(rank, suit);

/// [cards] first, then enough filler (2s) that no reshuffle happens.
List<PlayingCard> _deck(List<PlayingCard> cards) => [
  ...cards,
  for (var i = 0; i < reshuffleBelow + 10; i++) c(2, Suit.clubs),
];

/// Two players; cards are dealt p1, p2, dealer, p1, p2, dealer, then hits.
BlackjackSession _game(
  List<PlayingCard> cards, {
  bool chipsMode = false,
  int hands = 5,
  int players = 2,
}) => BlackjackSession.custom(
  _players(players),
  deck: _deck(cards),
  chipsMode: chipsMode,
  hands: hands,
);

Json _do(String type) => {'type': type};
Json _bet(int amount) => {'type': 'bet', 'amount': amount};

void _dealAll(BlackjackSession s, {int players = 2, int bet = 100}) {
  for (var i = 1; i <= players; i++) {
    s.applyAction('p$i', s.chipsMode ? _bet(bet) : _do('deal'));
  }
}

Json _seat(BlackjackSession s, String id) =>
    (s.tableView()['seats']! as List<Object?>).cast<Json>().firstWhere(
      (seat) => seat['id'] == id,
    );

List<Json> _hands(BlackjackSession s, String id) =>
    (_seat(s, id)['hands']! as List<Object?>).cast<Json>();

Json? _turn(BlackjackSession s) => s.tableView()['turn'] as Json?;

Json _dealer(BlackjackSession s) => s.tableView()['dealer']! as Json;

Matcher get _rejected => throwsA(isA<GameActionException>());

void main() {
  group('cards', () {
    test('a deck has 52 different cards', () {
      final deck = buildDeck();
      expect(deck, hasLength(52));
      expect(deck.map((c) => c.id).toSet(), hasLength(52));
    });

    test('aces count 11 unless that busts', () {
      expect(handValue([c(1), c(6)]), (total: 17, soft: true));
      expect(handValue([c(1), c(6), c(10)]), (total: 17, soft: false));
      expect(handValue([c(1), c(1)]), (total: 12, soft: true));
      expect(handValue([c(13), c(12), c(2)]), (total: 22, soft: false));
      expect(isNatural([c(1), c(11)]), isTrue);
      expect(isNatural([c(7), c(7), c(7)]), isFalse);
    });
  });

  group('dealing', () {
    test('a hand is dealt once everyone taps Deal', () {
      final s = _game([c(10), c(9), c(5), c(7), c(8), c(6)]);
      s.applyAction('p1', _do('deal'));
      expect(s.tableView()['playing'], isFalse);
      expect(s.viewFor('p1')['actions'], isEmpty, reason: 'already in');
      s.applyAction('p2', _do('deal'));
      expect(s.tableView()['playing'], isTrue);
      expect(_hands(s, 'p1').single['total'], 17);
      expect(_turn(s), {'player': 'p1', 'hand': 0});
      expect(s.viewFor('p1')['actions'], ['hit', 'stand']);
      expect(s.viewFor('p2')['actions'], isEmpty);
    });

    test('the dealer shows one card until playing', () {
      final s = _game([c(10), c(9), c(5), c(7), c(8), c(6)]);
      _dealAll(s);
      expect(_dealer(s)['hidden'], isTrue);
      expect(_dealer(s)['cards'], [c(5).toJson()]);
      expect(_dealer(s)['total'], 5);
      // The hole card (a 6 of spades) appears nowhere.
      expect(jsonEncode(s.viewFor('p1')), isNot(contains('"rank":6')));
    });

    test('the first seat to play moves round by round', () {
      Json first(int round) =>
          (BlackjackSession(
                    _players(3),
                    random: Random(1),
                    round: round,
                  ).tableView()['seats']!
                  as List<Object?>)
              .cast<Json>()
              .first;
      expect(first(0)['id'], 'p1');
      expect(first(1)['id'], 'p2');
    });

    test('bets: 10 to 500 in steps of 10, and only in the chips mode', () {
      final s = _game([], chipsMode: true);
      for (final bad in [
        _bet(5),
        _bet(15),
        _bet(510),
        {'type': 'bet', 'amount': '50'},
        _do('deal'),
      ]) {
        expect(() => s.applyAction('p1', bad), _rejected, reason: '$bad');
      }
      s.applyAction('p1', _bet(500));
      expect(_seat(s, 'p1')['chips'], 500);
      expect(_seat(s, 'p1')['bet'], 500);
      expect(() => s.applyAction('p1', _bet(10)), _rejected, reason: 'once');
      expect(
        () => _game([]).applyAction('p1', _bet(10)),
        _rejected,
        reason: 'no bets when racing to wins',
      );
    });
  });

  group('moves', () {
    test('hit, bust, and the turn moves on', () {
      final s = _game([c(10), c(9), c(5), c(6), c(8), c(10), c(13)]);
      _dealAll(s);
      s.applyAction('p1', _do('hit'));
      expect(_hands(s, 'p1').single['total'], 26);
      expect(_turn(s), {'player': 'p2', 'hand': 0});
    });

    test('reaching 21 stands by itself', () {
      final s = _game([c(10), c(9), c(5), c(6), c(8), c(10), c(5)]);
      _dealAll(s);
      s.applyAction('p1', _do('hit'));
      expect(_hands(s, 'p1').single['done'], isTrue);
      expect(_turn(s)!['player'], 'p2');
    });

    test('moves out of turn, or between hands, are refused', () {
      final s = _game([c(10), c(9), c(5), c(6), c(8), c(10)]);
      expect(() => s.applyAction('p1', _do('hit')), _rejected);
      _dealAll(s);
      expect(() => s.applyAction('p2', _do('stand')), _rejected);
      expect(() => s.applyAction('p1', _do('deal')), _rejected);
      expect(() => s.applyAction('p1', _do('fly')), _rejected);
      expect(() => s.applyAction('nobody', _do('hit')), _rejected);
    });

    test('double: one card, twice the bet, chips mode only', () {
      final cards = [c(5), c(9), c(10), c(6), c(8), c(7), c(10)];
      final s = _game(cards, chipsMode: true);
      _dealAll(s);
      expect(s.viewFor('p1')['actions'], contains('double'));
      s.applyAction('p1', _do('double'));
      final hand = _hands(s, 'p1').single;
      expect(hand['total'], 21);
      expect(hand['bet'], 200);
      expect(hand['done'], isTrue);
      expect(_seat(s, 'p1')['chips'], 800);

      final wins = _game(cards);
      _dealAll(wins);
      expect(wins.viewFor('p1')['actions'], isNot(contains('double')));
      expect(() => wins.applyAction('p1', _do('double')), _rejected);
    });

    test('split: two hands, played one after the other', () {
      // p1: 8 8 → splits; draws 3 (11) and 10 (18).
      final s = _game([
        c(8),
        c(9),
        c(10),
        c(8, Suit.hearts),
        c(9),
        c(7),
        c(3),
        c(10),
      ], chipsMode: true);
      _dealAll(s);
      expect(s.viewFor('p1')['actions'], contains('split'));
      s.applyAction('p1', _do('split'));
      expect(_hands(s, 'p1').map((h) => h['total']), [11, 18]);
      expect(_seat(s, 'p1')['chips'], 800, reason: 'a second bet');
      expect(_turn(s), {'player': 'p1', 'hand': 0});
      expect(s.viewFor('p1')['actions'], isNot(contains('split')));
      s.applyAction('p1', _do('stand'));
      expect(_turn(s), {'player': 'p1', 'hand': 1});
    });

    test('split aces get one card each; a 21 there is not blackjack', () {
      final s = _game([
        c(1),
        c(9),
        c(10),
        c(1, Suit.hearts),
        c(9),
        c(7),
        c(13),
        c(5),
      ], chipsMode: true);
      _dealAll(s);
      s.applyAction('p1', _do('split'));
      expect(_hands(s, 'p1').every((h) => h['done'] == true), isTrue);
      expect(_hands(s, 'p1').first['natural'], isFalse);
      s.applyAction('p2', _do('stand'));
      // Dealer 17: the 21 wins 1:1, the 16 loses.
      expect(_hands(s, 'p1').map((h) => h['result']), ['win', 'lose']);
      expect(_seat(s, 'p1')['chips'], 800 + 200);
    });

    test('only a pair of the same rank splits', () {
      final s = _game([c(10), c(9), c(10), c(13), c(9), c(7)]);
      _dealAll(s);
      expect(s.viewFor('p1')['actions'], ['hit', 'stand']);
      expect(() => s.applyAction('p1', _do('split')), _rejected);
    });
  });

  group('dealer and settling', () {
    test('the dealer draws to 17 and stands on a soft 17', () {
      final s = _game([c(10), c(10), c(1), c(8), c(9), c(6)]);
      _dealAll(s);
      s
        ..applyAction('p1', _do('stand'))
        ..applyAction('p2', _do('stand'));
      expect(_dealer(s)['hidden'], isFalse);
      expect(_dealer(s)['total'], 17);
      expect((_dealer(s)['cards']! as List<Object?>), hasLength(2));
      expect(_hands(s, 'p1').single['result'], 'win'); // 18
      expect(_hands(s, 'p2').single['result'], 'win'); // 19
      expect(_seat(s, 'p1')['wins'], 1);
      expect(s.tableView()['playing'], isFalse);
    });

    test('a dealer blackjack ends the hand at once', () {
      final s = _game([c(1), c(10), c(1, Suit.hearts), c(13), c(9), c(12)]);
      _dealAll(s);
      expect(s.tableView()['playing'], isFalse, reason: 'no turns');
      expect(_hands(s, 'p1').single['result'], 'push'); // blackjack vs it
      expect(_hands(s, 'p2').single['result'], 'lose');
    });

    test('payouts: win 1:1, blackjack 3:2, push back, bust lost', () {
      // p1 blackjack, p2 20, p3 18 (push), p4 busts; dealer 18.
      final s = _game(
        [
          ...[c(1), c(10), c(10), c(9), c(10)],
          ...[c(13), c(10), c(8), c(6), c(8)],
          c(10),
        ],
        chipsMode: true,
        players: 4,
      );
      _dealAll(s, players: 4);
      s
        ..applyAction('p2', _do('stand'))
        ..applyAction('p3', _do('stand'))
        ..applyAction('p4', _do('hit'));
      expect(
        [for (var i = 1; i <= 4; i++) _hands(s, 'p$i').single['result']],
        ['blackjack', 'win', 'push', 'lose'],
      );
      expect(
        [for (var i = 1; i <= 4; i++) _seat(s, 'p$i')['chips']],
        [1150, 1100, 1000, 900],
      );
    });

    test('the deck is reshuffled before a hand when it runs low', () {
      final s = BlackjackSession.custom(
        _players(2),
        deck: [
          c(10),
          c(9),
          c(5),
          c(7),
          c(8),
          c(6),
          for (var i = 0; i < 20; i++) c(2),
        ],
      );
      _dealAll(s);
      s
        ..applyAction('p1', _do('stand'))
        ..applyAction('p2', _do('stand'));
      expect(s.tableView()['reshuffled'], isFalse);
      _dealAll(s);
      expect(s.tableView()['reshuffled'], isTrue);
      expect(s.tableView()['cardsLeft'], 52 - 6);
    });
  });

  group('end', () {
    test('first to x wins; a tie shares it', () {
      final s = _game([c(10), c(10), c(10), c(9), c(9), c(7)], hands: 1);
      _dealAll(s);
      s
        ..applyAction('p1', _do('stand'))
        ..applyAction('p2', _do('stand'));
      expect(s.isOver, isTrue);
      expect(s.result!['winnerIds'], ['p1', 'p2']);
      expect(s.result!['summary'], contains('share'));
      expect(() => s.applyAction('p1', _do('deal')), _rejected);
    });

    test('most chips after x hands', () {
      final s = _game(
        [c(10), c(10), c(10), c(9), c(7), c(8)],
        chipsMode: true,
        hands: 1,
      );
      _dealAll(s);
      s
        ..applyAction('p1', _do('stand'))
        ..applyAction('p2', _do('stand'));
      // p1 19 beats 18, p2 17 loses.
      expect(s.result!['winnerIds'], ['p1']);
    });

    test('a broke player sits out; all broke ends the game', () {
      final s = _game(
        [c(10), c(10), c(10), c(6), c(6), c(9)],
        chipsMode: true,
        hands: 20,
      );
      _dealAll(s, bet: 500);
      s.applyAction('p1', _do('stand'));
      s.applyAction('p2', _do('stand'));
      expect(_seat(s, 'p1')['chips'], 500);
      final next = _game(
        [c(10), c(10), c(10), c(6), c(6), c(9)],
        chipsMode: true,
        hands: 20,
      );
      // Two all-in losses each: everyone is out, so the game ends early.
      for (var hand = 0; hand < 2; hand++) {
        _dealAll(next, bet: 500);
        if (next.tableView()['playing'] == true) {
          next
            ..applyAction('p1', _do('stand'))
            ..applyAction('p2', _do('stand'));
        }
      }
      expect(_seat(next, 'p1')['out'], isTrue);
      expect(next.viewFor('p1')['actions'], isEmpty);
      expect(next.isOver, isTrue);
    });
  });

  group('random games', () {
    for (var seed = 0; seed < 40; seed++) {
      final chipsMode = seed.isOdd;
      test(
        'seed $seed (${chipsMode ? 'chips' : 'wins'}) ends, hole hidden',
        () {
          final random = Random(seed);
          final players = _players(2 + seed % 7);
          final s = BlackjackSession(
            players,
            random: random,
            round: seed,
            chipsMode: chipsMode,
            hands: const [3, 5, 10, 20][seed % 4],
          );
          for (var moves = 0; !s.isOver; moves++) {
            expect(moves, lessThan(5000), reason: 'the game never ends');
            _expectPrivate(s, players);
            final mover = players.firstWhere(
              (p) => (s.viewFor(p.id)['actions']! as List<Object?>).isNotEmpty,
            );
            final actions = (s.viewFor(mover.id)['actions']! as List<Object?>)
                .cast<String>();
            final action = actions.contains('bet')
                ? _bet(10 * (1 + random.nextInt(10)))
                : _do(actions[random.nextInt(actions.length)]);
            try {
              s.applyAction(mover.id, action);
            } on GameActionException {
              // A random bet above the player's chips: bet the minimum.
              s.applyAction(mover.id, _bet(minBet));
            }
          }
          expect(s.result, isNotNull);
        },
      );
    }
  });
}

/// The table and every view agree, and the hole card is never sent.
void _expectPrivate(BlackjackSession s, List<PlayerInfo> players) {
  final table = s.tableView();
  final dealer = table['dealer']! as Json;
  if (dealer['hidden'] == true) {
    expect(dealer['cards'], hasLength(1), reason: 'only the up card');
  }
  for (final p in players) {
    final view = s.viewFor(p.id);
    for (final key in table.keys) {
      expect(view[key], table[key], reason: 'view and table differ on $key');
    }
    expect(view.keys.toSet().difference(table.keys.toSet()), {'actions'});
  }
}
