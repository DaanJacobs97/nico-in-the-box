import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/color_clash/clash_card.dart';
import 'package:nico_shared/games/color_clash/color_clash_game.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/net/protocol.dart';

const a = PlayerInfo(id: 'a', nickname: 'Ann');
const b = PlayerInfo(id: 'b', nickname: 'Bob');
const c = PlayerInfo(id: 'c', nickname: 'Cat');

var _nextId = 1000;
ClashCard card(CardColor color, CardKind kind, [int? value]) =>
    ClashCard(id: _nextId++, color: color, kind: kind, value: value);
ClashCard num(CardColor color, int value) =>
    card(color, CardKind.number, value);

const red = CardColor.red;
const blue = CardColor.blue;
const green = CardColor.green;
const yellow = CardColor.yellow;
const wild = CardColor.wild;

Matcher get rejected => throwsA(isA<GameActionException>());

String? turnOf(ColorClashSession g) => g.viewFor('a')['turn'] as String?;
int cardsOf(ColorClashSession g, String id) =>
    ((g.viewFor(id)['hand']! as List<Object?>)).length;

void play(
  ColorClashSession g,
  String player,
  ClashCard card, [
  String? color,
]) =>
    g.applyAction(player, {'type': 'play', 'cardId': card.id, 'color': ?color});

/// Session where the discard top is red 5 and everyone has spare cards.
ColorClashSession setup({
  List<PlayerInfo> players = const [a, b, c],
  required Map<String, List<ClashCard>> hands,
  List<ClashCard>? drawPile,
  int turnIndex = 0,
}) {
  return ColorClashSession.custom(
    players,
    hands: hands,
    drawPile: drawPile ?? [for (var i = 0; i < 20; i++) num(green, i % 10)],
    discard: [num(red, 5)],
    turnIndex: turnIndex,
  );
}

void main() {
  group('deck', () {
    test('has the standard 108 cards with unique ids', () {
      final deck = buildDeck();
      expect(deck, hasLength(108));
      expect(deck.map((c) => c.id).toSet(), hasLength(108));
      int count(CardKind kind) => deck.where((c) => c.kind == kind).length;
      expect(count(CardKind.number), 76);
      expect(count(CardKind.skip), 8);
      expect(count(CardKind.reverse), 8);
      expect(count(CardKind.drawTwo), 8);
      expect(count(CardKind.wild), 4);
      expect(count(CardKind.wildDrawFour), 4);
      expect(
        deck.where((c) => c.kind == CardKind.number && c.value == 0),
        hasLength(4),
      );
    });

    test('card JSON round trip', () {
      final original = card(blue, CardKind.number, 7);
      final copy = ClashCard.fromJson(original.toJson());
      expect(copy.id, original.id);
      expect(copy.color, blue);
      expect(copy.value, 7);
    });

    test('playability: color, number, symbol and wilds', () {
      final top = num(red, 5);
      expect(num(red, 1).canPlayOn(top, red), isTrue);
      expect(num(blue, 5).canPlayOn(top, red), isTrue);
      expect(num(blue, 4).canPlayOn(top, red), isFalse);
      expect(card(wild, CardKind.wild).canPlayOn(top, red), isTrue);
      expect(card(wild, CardKind.wildDrawFour).canPlayOn(top, red), isTrue);
      final skip = card(red, CardKind.skip);
      expect(card(blue, CardKind.skip).canPlayOn(skip, red), isTrue);
      expect(card(blue, CardKind.reverse).canPlayOn(skip, red), isFalse);
      // After a wild, the chosen color counts, not the card's own color.
      final wildTop = card(wild, CardKind.wild);
      expect(num(green, 3).canPlayOn(wildTop, green), isTrue);
      expect(num(red, 3).canPlayOn(wildTop, green), isFalse);
    });
  });

  group('new session', () {
    test('deals 7 each, starts on a number and the first player moves', () {
      final game = ColorClashSession([a, b, c], random: Random(7));
      for (final p in [a, b, c]) {
        expect(cardsOf(game, p.id), handSize);
      }
      final view = game.viewFor('a');
      final top = ClashCard.fromJson(view['top']! as Json);
      expect(top.kind, CardKind.number);
      expect(view['drawPile'], 108 - 3 * handSize - 1);
      expect(view['turn'], 'a');
    });

    test('starting player rotates with the round', () {
      final game = colorClashDefinition.createSession(
        [a, b, c],
        1,
        Random(1),
        const {},
      );
      expect(game.viewFor('a')['turn'], 'b');
    });

    test('views hide other hands', () {
      final game = ColorClashSession([a, b], random: Random(3));
      final view = game.viewFor('a');
      final players = (view['players']! as List<Object?>).cast<Json>();
      expect(players.map((p) => p['cards']), [7, 7]);
      expect(view.containsKey('hands'), isFalse);
    });
  });

  group('turns and action cards', () {
    test('rejects out-of-turn, unknown and unplayable cards', () {
      final r1 = num(red, 1);
      final b4 = num(blue, 4);
      final game = setup(
        hands: {
          'a': [r1, b4, num(red, 9)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      expect(() => play(game, 'b', r1), rejected);
      expect(() => play(game, 'a', b4), rejected);
      expect(
        () => game.applyAction('a', {'type': 'play', 'cardId': 999}),
        rejected,
      );
      expect(() => game.applyAction('a', {'type': 'dance'}), rejected);
      play(game, 'a', r1);
      expect(turnOf(game), 'b');
    });

    test('skip jumps over the next player', () {
      final skip = card(red, CardKind.skip);
      final game = setup(
        hands: {
          'a': [skip, num(red, 1)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      play(game, 'a', skip);
      expect(turnOf(game), 'c');
    });

    test('reverse flips direction with three players', () {
      final reverse = card(red, CardKind.reverse);
      final game = setup(
        hands: {
          'a': [reverse, num(red, 1)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      play(game, 'a', reverse);
      expect(turnOf(game), 'c');
      expect(game.viewFor('a')['direction'], -1);
    });

    test('reverse acts as skip with two players', () {
      final reverse = card(red, CardKind.reverse);
      final game = setup(
        players: [a, b],
        hands: {
          'a': [reverse, num(red, 1)],
          'b': [num(red, 2), num(red, 3)],
        },
      );
      play(game, 'a', reverse);
      expect(turnOf(game), 'a');
    });

    test('draw two makes the next player draw 2 and skips them', () {
      final drawTwo = card(red, CardKind.drawTwo);
      final game = setup(
        hands: {
          'a': [drawTwo, num(red, 1)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      play(game, 'a', drawTwo);
      expect(cardsOf(game, 'b'), 4);
      expect(turnOf(game), 'c');
    });

    test('wild needs a valid color and sets it', () {
      final w = card(wild, CardKind.wild);
      final game = setup(
        hands: {
          'a': [w, num(red, 1)],
          'b': [num(blue, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      expect(() => play(game, 'a', w), rejected);
      expect(() => play(game, 'a', w, 'purple'), rejected);
      play(game, 'a', w, 'blue');
      expect(game.viewFor('b')['color'], 'blue');
      expect(turnOf(game), 'b');
      // Red no longer matches; blue does.
      expect(game.viewFor('b')['playable'], hasLength(1));
    });

    test('wild draw four makes the next player draw 4 and skips them', () {
      final w4 = card(wild, CardKind.wildDrawFour);
      final game = setup(
        hands: {
          'a': [w4, num(red, 1)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      play(game, 'a', w4, 'yellow');
      expect(cardsOf(game, 'b'), 6);
      expect(turnOf(game), 'c');
      expect(game.viewFor('c')['color'], 'yellow');
    });

    test('direction wraps around correctly when reversed', () {
      final reverse = card(red, CardKind.reverse);
      final game = setup(
        hands: {
          'a': [num(red, 1), num(red, 2)],
          'b': [reverse, num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
        turnIndex: 1,
      );
      play(game, 'b', reverse);
      expect(turnOf(game), 'a');
    });
  });

  group('drawing', () {
    test('an unplayable drawn card ends the turn', () {
      final game = setup(
        hands: {
          'a': [num(blue, 1), num(blue, 2)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
        drawPile: [num(green, 1)],
      );
      game.applyAction('a', {'type': 'draw'});
      expect(cardsOf(game, 'a'), 3);
      expect(turnOf(game), 'b');
    });

    test('a playable drawn card may be played, but only that card', () {
      final drawn = num(red, 8);
      final other = num(red, 1);
      final game = setup(
        hands: {
          'a': [other, num(blue, 2)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
        drawPile: [drawn],
      );
      game.applyAction('a', {'type': 'draw'});
      expect(turnOf(game), 'a');
      expect(game.viewFor('a')['pendingDrawn'], drawn.id);
      expect(game.viewFor('a')['playable'], [drawn.id]);
      expect(() => play(game, 'a', other), rejected);
      expect(() => game.applyAction('a', {'type': 'draw'}), rejected);
      play(game, 'a', drawn);
      expect(turnOf(game), 'b');
    });

    test('pass is only allowed after drawing a playable card', () {
      final game = setup(
        hands: {
          'a': [num(red, 1), num(blue, 2)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
        drawPile: [num(red, 8)],
      );
      expect(() => game.applyAction('a', {'type': 'pass'}), rejected);
      game.applyAction('a', {'type': 'draw'});
      game.applyAction('a', {'type': 'pass'});
      expect(turnOf(game), 'b');
      expect(cardsOf(game, 'a'), 3);
    });

    test('reshuffles the discard pile (keeping the top) when empty', () {
      final r1 = num(red, 1);
      final r2 = num(red, 2);
      final game = setup(
        players: [a, b],
        hands: {
          'a': [r1, num(blue, 9)],
          'b': [r2, num(blue, 8)],
        },
        drawPile: [],
      );
      play(game, 'a', r1);
      play(game, 'b', r2);
      // Discard is now [red 5, red 1, red 2]; draw pile is empty.
      game.applyAction('a', {'type': 'draw'});
      final view = game.viewFor('a');
      expect(cardsOf(game, 'a'), 2);
      expect(view['drawPile'], 1);
      expect(ClashCard.fromJson(view['top']! as Json).id, r2.id);
    });

    test('with nothing left to draw the turn simply passes', () {
      final game = setup(
        players: [a, b],
        hands: {
          'a': [num(blue, 1), num(blue, 2)],
          'b': [num(red, 2), num(red, 3)],
        },
        drawPile: [],
      );
      game.applyAction('a', {'type': 'draw'});
      expect(cardsOf(game, 'a'), 2);
      expect(turnOf(game), 'b');
    });
  });

  group('last card', () {
    test('playing down to one card without calling can be caught', () {
      final r1 = num(red, 1);
      final game = setup(
        hands: {
          'a': [r1, num(blue, 2)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      play(game, 'a', r1);
      expect(game.viewFor('b')['vulnerable'], 'a');
      expect(() => game.applyAction('a', {'type': 'catch'}), rejected);
      game.applyAction('c', {'type': 'catch'});
      expect(cardsOf(game, 'a'), 1 + lastCardPenalty);
      expect(game.viewFor('b')['vulnerable'], isNull);
      expect(() => game.applyAction('b', {'type': 'catch'}), rejected);
    });

    test('calling with two cards on your turn protects you', () {
      final r1 = num(red, 1);
      final game = setup(
        hands: {
          'a': [r1, num(blue, 2)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      expect(game.viewFor('a')['canCallLast'], isTrue);
      game.applyAction('a', {'type': 'callLast'});
      play(game, 'a', r1);
      expect(game.viewFor('b')['vulnerable'], isNull);
      expect(() => game.applyAction('b', {'type': 'catch'}), rejected);
    });

    test('calling right after playing saves you', () {
      final r1 = num(red, 1);
      final game = setup(
        hands: {
          'a': [r1, num(blue, 2)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      play(game, 'a', r1);
      game.applyAction('a', {'type': 'callLast'});
      expect(() => game.applyAction('b', {'type': 'catch'}), rejected);
    });

    test('the catch window closes on the next play', () {
      final r1 = num(red, 1);
      final r2 = num(red, 2);
      final game = setup(
        hands: {
          'a': [r1, num(blue, 2)],
          'b': [r2, num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      play(game, 'a', r1);
      play(game, 'b', r2);
      expect(game.viewFor('c')['vulnerable'], 'b');
      game.applyAction('c', {'type': 'catch'});
      expect(cardsOf(game, 'a'), 1);
    });

    test('cannot call with three cards or out of turn with two', () {
      final game = setup(
        hands: {
          'a': [num(red, 1), num(red, 2), num(red, 3)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
      );
      expect(() => game.applyAction('a', {'type': 'callLast'}), rejected);
      expect(() => game.applyAction('b', {'type': 'callLast'}), rejected);
    });

    test('drawing after calling clears the call', () {
      final game = setup(
        hands: {
          'a': [num(blue, 1), num(blue, 2)],
          'b': [num(red, 2), num(red, 3)],
          'c': [num(red, 2), num(red, 3)],
        },
        drawPile: [num(green, 1)],
      );
      game.applyAction('a', {'type': 'callLast'});
      game.applyAction('a', {'type': 'draw'});
      final players = (game.viewFor('a')['players']! as List<Object?>)
          .cast<Json>();
      expect(players.first['calledLast'], isFalse);
    });
  });

  test('emptying your hand wins the round', () {
    final r1 = num(red, 1);
    final game = setup(
      hands: {
        'a': [r1],
        'b': [num(red, 2), num(red, 3)],
        'c': [num(red, 2), num(red, 3)],
      },
    );
    play(game, 'a', r1);
    expect(game.isOver, isTrue);
    expect(game.result, {
      'winnerIds': ['a'],
      'summary': 'Ann wins the round!',
    });
    expect(game.viewFor('b')['turn'], isNull);
    expect(() => game.applyAction('b', {'type': 'draw'}), rejected);
  });

  test('a random game played by bots always finishes legally', () {
    for (var seed = 0; seed < 100; seed++) {
      final random = Random(seed);
      // Every combination of the two options, 25 games each.
      final game = ColorClashSession(
        [a, b, c],
        random: random,
        stacking: seed.isOdd,
        playAfterPenalty: seed % 4 >= 2,
      );
      var moves = 0;
      while (!game.isOver && moves < 5000) {
        final turn = turnOf(game)!;
        final view = game.viewFor(turn);
        final playable = (view['playable']! as List<Object?>).cast<int>();
        if (view['canCallLast'] == true) {
          game.applyAction(turn, {'type': 'callLast'});
        }
        if (playable.isNotEmpty) {
          game.applyAction(turn, {
            'type': 'play',
            'cardId': playable.first,
            'color': playableColors[random.nextInt(4)].name,
          });
        } else if (view['pendingDrawn'] != null) {
          game.applyAction(turn, {'type': 'pass'});
        } else {
          game.applyAction(turn, {'type': 'draw'});
        }
        moves++;
      }
      expect(game.isOver, isTrue, reason: 'seed $seed did not finish');
    }
  });

  group('table view (shared screen)', () {
    /// Every card-shaped object anywhere inside [value].
    Iterable<Json> cardsIn(Object? value) sync* {
      if (value is Map<String, Object?>) {
        if (value.containsKey('kind') && value.containsKey('color')) {
          yield value;
        }
        for (final v in value.values) {
          yield* cardsIn(v);
        }
      } else if (value is List<Object?>) {
        for (final v in value) {
          yield* cardsIn(v);
        }
      }
    }

    test('has public state but no private fields', () {
      final game = ColorClashSession([a, b, c], random: Random(11));
      final table = game.tableView();
      for (final key in ['hand', 'playable', 'pendingDrawn', 'canCallLast']) {
        expect(table.containsKey(key), isFalse, reason: key);
      }
      final players = (table['players']! as List<Object?>).cast<Json>();
      expect(players.map((p) => p['cards']), [7, 7, 7]);
      expect(table['turn'], 'a');
      // A player's view is the table view plus their own private parts.
      final view = game.viewFor('a');
      for (final key in table.keys) {
        expect(view[key], table[key], reason: key);
      }
    });

    test('never contains a card from any hand, in any state', () {
      for (var seed = 0; seed < 10; seed++) {
        final random = Random(seed);
        final game = ColorClashSession([a, b, c], random: random);
        var moves = 0;
        while (!game.isOver && moves < 5000) {
          final handIds = {
            for (final p in [a, b, c])
              for (final card in game.viewFor(p.id)['hand']! as List<Object?>)
                (card! as Json)['id'],
          };
          final shown = cardsIn(game.tableView()).toList();
          // The only card on the table is the public top of the discard pile.
          expect(shown, hasLength(1), reason: 'seed $seed move $moves');
          expect(handIds.contains(shown.single['id']), isFalse);

          final turn = turnOf(game)!;
          final view = game.viewFor(turn);
          final playable = (view['playable']! as List<Object?>).cast<int>();
          if (playable.isNotEmpty) {
            game.applyAction(turn, {
              'type': 'play',
              'cardId': playable.first,
              'color': playableColors[random.nextInt(4)].name,
            });
          } else if (view['pendingDrawn'] != null) {
            game.applyAction(turn, {'type': 'pass'});
          } else {
            game.applyAction(turn, {'type': 'draw'});
          }
          moves++;
        }
      }
    });
  });
}
