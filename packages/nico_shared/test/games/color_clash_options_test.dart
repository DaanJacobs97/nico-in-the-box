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
ClashCard plus2(CardColor color) => card(color, CardKind.drawTwo);
ClashCard plus4() => card(CardColor.wild, CardKind.wildDrawFour);

const red = CardColor.red;
const blue = CardColor.blue;
const green = CardColor.green;

Matcher get rejected => throwsA(isA<GameActionException>());

String? turnOf(ColorClashSession g) => g.tableView()['turn'] as String?;
int cardsOf(ColorClashSession g, String id) =>
    (g.viewFor(id)['hand']! as List<Object?>).length;
int penaltyOf(ColorClashSession g) => g.tableView()['penalty']! as int;
List<Object?> playableOf(ColorClashSession g, String id) =>
    g.viewFor(id)['playable']! as List<Object?>;

void play(ColorClashSession g, String player, ClashCard card) => g.applyAction(
  player,
  {'type': 'play', 'cardId': card.id, if (card.isWild) 'color': 'blue'},
);
void draw(ColorClashSession g, String player) =>
    g.applyAction(player, {'type': 'draw'});

/// Three players, Ann to move, red 5 on top, plenty to draw.
ColorClashSession setup({
  required Map<String, List<ClashCard>> hands,
  bool stacking = false,
  bool playAfterPenalty = false,
  List<ClashCard>? drawPile,
}) => ColorClashSession.custom(
  const [a, b, c],
  hands: hands,
  drawPile: drawPile ?? [for (var i = 0; i < 30; i++) num(green, i % 10)],
  discard: [num(red, 5)],
  stacking: stacking,
  playAfterPenalty: playAfterPenalty,
);

void main() {
  group('options', () {
    test('the definition declares both, on by default', () {
      expect(
        {for (final o in colorClashDefinition.options) o.id: o.defaultValue},
        {'stacking': true, 'playAfterPenalty': true},
      );
    });

    test('a session from the definition uses the chosen values', () {
      ColorClashSession create(GameOptions options) =>
          colorClashDefinition.createSession(
            const [a, b],
            0,
            Random(1),
            {...colorClashDefinition.defaultOptions, ...options},
          ) as ColorClashSession;
      expect(create({}).stacking, isTrue);
      expect(create({}).playAfterPenalty, isTrue);
      expect(create({'stacking': false}).stacking, isFalse);
      expect(create({'playAfterPenalty': false}).playAfterPenalty, isFalse);
    });

    test('both off: a +2 is drawn at once and skips the player', () {
      final opener = plus2(red);
      final g = setup(
        hands: {
          'a': [opener, num(red, 1)],
          'b': [plus2(blue), num(blue, 1)],
          'c': [num(green, 1), num(green, 2)],
        },
      );
      play(g, 'a', opener);
      expect(cardsOf(g, 'b'), 4);
      expect(penaltyOf(g), 0);
      expect(turnOf(g), 'c');
    });
  });

  group('play after drawing a penalty', () {
    test('without stacking, the drawer keeps their turn', () {
      final opener = plus2(red);
      final g = setup(
        playAfterPenalty: true,
        hands: {
          'a': [opener, num(red, 1)],
          'b': [num(blue, 1)],
          'c': [num(green, 1)],
        },
      );
      play(g, 'a', opener);
      expect(cardsOf(g, 'b'), 3);
      expect(turnOf(g), 'b');
      expect(g.tableView()['log'], contains('Bob draws 2'));
    });

    test('a Wild +4 works the same way', () {
      final opener = plus4();
      final g = setup(
        playAfterPenalty: true,
        hands: {
          'a': [opener, num(red, 1)],
          'b': [num(blue, 1)],
          'c': [num(green, 1)],
        },
      );
      play(g, 'a', opener);
      expect(cardsOf(g, 'b'), 5);
      expect(turnOf(g), 'b');
      expect(g.tableView()['color'], 'blue');
    });
  });

  group('stacking', () {
    late ClashCard annPlus2;
    late ClashCard bobPlus2;
    late ClashCard bobPlus4;
    late ClashCard catPlus2;
    late ClashCard catPlus4;
    late ClashCard bobRed7;

    ColorClashSession stackGame({bool playAfterPenalty = false}) {
      annPlus2 = plus2(red);
      bobPlus2 = plus2(blue);
      bobPlus4 = plus4();
      catPlus2 = plus2(green);
      catPlus4 = plus4();
      bobRed7 = num(red, 7);
      return setup(
        stacking: true,
        playAfterPenalty: playAfterPenalty,
        hands: {
          'a': [annPlus2, num(red, 1)],
          'b': [bobPlus2, bobPlus4, bobRed7, num(blue, 1)],
          'c': [catPlus2, catPlus4, num(blue, 2), num(green, 1)],
        },
      );
    }

    test('a +2 becomes a pending penalty for the next player', () {
      final g = stackGame();
      play(g, 'a', annPlus2);
      expect(penaltyOf(g), 2);
      expect(turnOf(g), 'b');
      expect(cardsOf(g, 'b'), 4);
      expect(g.tableView()['log'], contains('Bob must draw 2 or stack'));
    });

    test('only a +2 or a Wild +4 can answer a +2', () {
      final g = stackGame();
      play(g, 'a', annPlus2);
      expect(playableOf(g, 'b'), unorderedEquals([bobPlus2.id, bobPlus4.id]));
      // Red 7 matches the red +2's color but doesn't answer the penalty.
      expect(() => play(g, 'b', bobRed7), rejected);
    });

    test('stacking adds up and passes the total on', () {
      final g = stackGame();
      play(g, 'a', annPlus2);
      play(g, 'b', bobPlus2);
      expect(penaltyOf(g), 4);
      expect(turnOf(g), 'c');
      play(g, 'c', catPlus4);
      expect(penaltyOf(g), 8);
      expect(turnOf(g), 'a');
      expect(g.tableView()['color'], 'blue');
    });

    test('a +2 cannot go on a Wild +4', () {
      final g = stackGame();
      play(g, 'a', annPlus2);
      play(g, 'b', bobPlus4);
      expect(playableOf(g, 'c'), [catPlus4.id]);
      expect(() => play(g, 'c', catPlus2), rejected);
    });

    test('drawing takes the whole total and, by default, the turn', () {
      final g = stackGame();
      play(g, 'a', annPlus2);
      play(g, 'b', bobPlus2);
      draw(g, 'c');
      expect(cardsOf(g, 'c'), 8);
      expect(penaltyOf(g), 0);
      expect(turnOf(g), 'a');
      expect(g.tableView()['log'], contains('Cat draws 4 and is skipped'));
    });

    test('with play after penalty, the drawer then plays normally', () {
      final g = stackGame(playAfterPenalty: true);
      play(g, 'a', annPlus2);
      draw(g, 'b');
      expect(cardsOf(g, 'b'), 6);
      expect(turnOf(g), 'b');
      expect(penaltyOf(g), 0);
      // An ordinary turn again: the blue +2 matches the top +2 by symbol.
      expect(playableOf(g, 'b'), contains(bobPlus2.id));
      play(g, 'b', bobRed7);
      expect(turnOf(g), 'c');
    });

    test('a short draw pile hands over what is left', () {
      final opener = plus2(red);
      final g = setup(
        stacking: true,
        drawPile: [num(green, 1)],
        hands: {
          'a': [opener, num(red, 1)],
          'b': [num(blue, 1)],
          'c': [num(green, 1)],
        },
      );
      play(g, 'a', opener);
      draw(g, 'b');
      // The one card in the pile, then the reshuffled red 5; nothing more.
      expect(cardsOf(g, 'b'), 3);
      expect(g.tableView()['drawPile'], 0);
      expect(penaltyOf(g), 0);
      expect(turnOf(g), 'c');
    });

    test('a stacked last card still wins', () {
      final last = plus2(blue);
      final opener = plus2(red);
      final g = setup(
        stacking: true,
        hands: {
          'a': [opener, num(red, 1)],
          'b': [last],
          'c': [num(green, 1)],
        },
      );
      play(g, 'a', opener);
      play(g, 'b', last);
      expect(g.isOver, isTrue);
      expect(g.result!['winnerIds'], ['b']);
    });
  });
}
