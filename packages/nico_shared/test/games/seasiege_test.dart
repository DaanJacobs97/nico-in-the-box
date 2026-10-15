import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/games/seasiege/seasiege_fleet.dart';
import 'package:nico_shared/games/seasiege/seasiege_game.dart';
import 'package:nico_shared/net/protocol.dart';

const a = PlayerInfo(id: 'a', nickname: 'Ann');
const b = PlayerInfo(id: 'b', nickname: 'Bob');
const c = PlayerInfo(id: 'c', nickname: 'Cat');

/// Every ship on its own even row, starting in column A:
/// carrier 0-4, battleship 20-23, cruiser 40-42, submarine 60-62,
/// destroyer 80-81.
final rowsFleet = [
  for (final (i, type) in ShipType.values.indexed)
    Ship(type, row: i * 2, col: 0),
];
const fleetCells = [
  0,
  1,
  2,
  3,
  4,
  20,
  21,
  22,
  23,
  40,
  41,
  42,
  60,
  61,
  62,
  80,
  81,
];

final throwsRefusal = throwsA(isA<GameActionException>());

Json fire(int cell, [String? target]) => {
  'type': 'fire',
  'cell': cell,
  'target': ?target,
};

Json move(String ship, int row, int col, {bool vertical = false}) => {
  'type': 'move',
  'ship': ship,
  'row': row,
  'col': col,
  'vertical': vertical,
};

SeaSiegeSession battle({bool shootAgain = false, String turn = 'a'}) =>
    SeaSiegeSession.custom(
      const [a, b],
      fleets: {'a': rowsFleet, 'b': rowsFleet},
      turn: turn,
      shootAgain: shootAgain,
    );

List<Ship> fleetOf(SeaSiegeSession s, String id) => [
  for (final ship in (s.viewFor(id)['fleet']! as List<Object?>).cast<Json>())
    Ship(
      ShipType.values.byName(ship['id']! as String),
      row: ship['row']! as int,
      col: ship['col']! as int,
      vertical: ship['vertical']! as bool,
    ),
];

Json board(SeaSiegeSession s, String id) =>
    (s.tableView()['boards']! as Json)[id]! as Json;

void main() {
  group('fleet', () {
    test('cell names', () {
      expect(cellName(0), 'A1');
      expect(cellName(33), 'D4');
      expect(cellName(99), 'J10');
    });

    test('random fleets are always valid', () {
      for (var seed = 0; seed < 300; seed++) {
        expect(
          isValidFleet(randomFleet(Random(seed))),
          isTrue,
          reason: '$seed',
        );
      }
    });

    test('invalid fleets are caught', () {
      expect(isValidFleet(rowsFleet), isTrue);
      expect(isValidFleet(rowsFleet.sublist(1)), isFalse, reason: 'missing');
      final overlapping = [...rowsFleet]
        ..[1] = const Ship(ShipType.battleship, row: 0, col: 4, vertical: true);
      expect(isValidFleet(overlapping), isFalse);
      final outside = [...rowsFleet]
        ..[0] = const Ship(ShipType.carrier, row: 0, col: 6);
      expect(isValidFleet(outside), isFalse);
    });
  });

  group('placing', () {
    late SeaSiegeSession s;
    setUp(() => s = SeaSiegeSession(const [a, b], random: Random(3)));

    test('everyone starts with a valid secret fleet, not ready', () {
      final table = s.tableView();
      expect(table['phase'], 'placing');
      expect(table['turn'], isNull);
      expect(table['ready'], {'a': false, 'b': false});
      expect(table, isNot(contains('fleet')));
      expect(isValidFleet(fleetOf(s, 'a')), isTrue);
      expect(isValidFleet(fleetOf(s, 'b')), isTrue);
    });

    test('a ship can be moved and rotated', () {
      final before = fleetOf(s, 'a');
      final destroyer = before.firstWhere((x) => x.type == ShipType.destroyer);
      // Find a free spot for the destroyer, then rotate it in place.
      final taken = {
        for (final x in before)
          if (x.type != ShipType.destroyer) ...x.cells,
      };
      for (var cell = 0; cell < 100; cell++) {
        final candidate = destroyer.movedTo(
          row: cell ~/ 10,
          col: cell % 10,
          vertical: true,
        );
        final flat = candidate.movedTo(
          row: candidate.row,
          col: candidate.col,
          vertical: false,
        );
        if (!candidate.inBounds || !flat.inBounds) continue;
        if ([...candidate.cells, ...flat.cells].any(taken.contains)) continue;
        s.applyAction(
          'a',
          move('destroyer', cell ~/ 10, cell % 10, vertical: true),
        );
        var moved = fleetOf(
          s,
          'a',
        ).firstWhere((x) => x.type == ShipType.destroyer);
        expect(moved.cells, candidate.cells);
        s.applyAction('a', move('destroyer', cell ~/ 10, cell % 10));
        moved = fleetOf(s, 'a').firstWhere((x) => x.type == ShipType.destroyer);
        expect(moved.cells, flat.cells);
        expect(isValidFleet(fleetOf(s, 'a')), isTrue);
        expect(fleetOf(s, 'a').map((x) => x.type), ShipType.values);
        return;
      }
      fail('no free spot found');
    });

    test('moves that break the rules are refused', () {
      final before = fleetOf(s, 'a');
      final other = before.first.cells.first;
      for (final bad in [
        move('carrier', 0, 6), // runs off the right edge
        move('carrier', 6, 0, vertical: true), // runs off the bottom
        move('carrier', -1, 0),
        move('destroyer', other ~/ 10, other % 10), // onto the carrier
        move('rowboat', 0, 0),
        {
          'type': 'move',
          'ship': 'carrier',
          'row': '1',
          'col': 0,
          'vertical': false,
        },
        {'type': 'move', 'ship': 'carrier', 'row': 1, 'col': 0},
        {'type': 'sail'},
      ]) {
        expect(() => s.applyAction('a', bad), throwsRefusal, reason: '$bad');
      }
      expect(fleetOf(s, 'a').map((x) => x.cells), before.map((x) => x.cells));
    });

    test('shuffle gives another valid fleet', () {
      final before = fleetOf(s, 'a').map((x) => x.cells).toList();
      s.applyAction('a', {'type': 'shuffle'});
      expect(isValidFleet(fleetOf(s, 'a')), isTrue);
      expect(fleetOf(s, 'a').map((x) => x.cells), isNot(before));
    });

    test('ready locks the fleet, unready unlocks it', () {
      s.applyAction('a', {'type': 'ready'});
      expect(s.tableView()['ready'], {'a': true, 'b': false});
      expect(() => s.applyAction('a', {'type': 'shuffle'}), throwsRefusal);
      s.applyAction('a', {'type': 'unready'});
      s.applyAction('a', {'type': 'shuffle'});
      expect(s.tableView()['phase'], 'placing');
    });

    test('nobody fires before the battle', () {
      expect(() => s.applyAction('a', fire(0)), throwsRefusal);
    });

    test('the battle starts once everyone is ready', () {
      s
        ..applyAction('a', {'type': 'ready'})
        ..applyAction('b', {'type': 'ready'});
      expect(s.tableView()['phase'], 'battle');
      expect(s.tableView()['turn'], 'a');
      expect(() => s.applyAction('a', {'type': 'unready'}), throwsRefusal);
      expect(() => s.applyAction('b', {'type': 'shuffle'}), throwsRefusal);
    });

    test('the first shooter alternates between rounds', () {
      for (final (round, first) in [(0, 'a'), (1, 'b'), (2, 'a')]) {
        final game = SeaSiegeSession(const [a, b], round: round)
          ..applyAction('a', {'type': 'ready'})
          ..applyAction('b', {'type': 'ready'});
        expect(game.tableView()['turn'], first, reason: 'round $round');
      }
    });
  });

  group('battle', () {
    test('a miss passes the turn', () {
      final s = battle()..applyAction('a', fire(99));
      expect(board(s, 'b')['misses'], [99]);
      expect(s.tableView()['turn'], 'b');
      expect((s.tableView()['log']! as List).single, {
        'shooter': 'a',
        'target': 'b',
        'cell': 99,
        'result': 'miss',
      });
    });

    test('a hit names the ship and passes the turn', () {
      final s = battle()..applyAction('a', fire(41));
      expect(board(s, 'b')['hits'], [41]);
      expect(
        (s.tableView()['log']! as List).single,
        containsPair('ship', 'Cruiser'),
      );
      expect(s.tableView()['turn'], 'b');
    });

    test(
      'with "Hit = shoot again", a hit keeps the turn and a miss ends it',
      () {
        final s = battle(shootAgain: true)..applyAction('a', fire(41));
        expect(s.tableView()['turn'], 'a');
        s.applyAction('a', fire(99));
        expect(s.tableView()['turn'], 'b');
      },
    );

    test('sinking a ship reveals it and announces it', () {
      final s = battle(shootAgain: true)
        ..applyAction('a', fire(80))
        ..applyAction('a', fire(81));
      final sunk = board(s, 'b')['sunk']! as List;
      expect(sunk.single, containsPair('id', 'destroyer'));
      expect((sunk.single as Json)['cells'], [80, 81]);
      expect(board(s, 'b')['afloat'], isNot(contains('Destroyer')));
      expect(
        (s.tableView()['log']! as List).last,
        containsPair('result', 'sunk'),
      );
    });

    test('bad shots are refused and change nothing', () {
      final s = battle()
        ..applyAction('a', fire(5))
        ..applyAction('b', fire(5));
      for (final (who, action) in [
        ('b', fire(6)), // out of turn
        ('a', fire(5)), // already fired there
        ('a', fire(100)),
        ('a', fire(-1)),
        ('a', {'type': 'fire', 'cell': '5'}),
        ('a', fire(6, 'a')), // at yourself
        ('a', fire(6, 'zed')),
        ('a', move('carrier', 5, 5)),
        ('zed', fire(6)),
      ]) {
        expect(
          () => s.applyAction(who, action),
          throwsRefusal,
          reason: '$who $action',
        );
      }
      expect(s.tableView()['turn'], 'a');
    });

    test('sinking the whole fleet wins, then nothing more is allowed', () {
      final s = battle(shootAgain: true);
      for (final cell in fleetCells) {
        s.applyAction('a', fire(cell));
      }
      expect(s.isOver, isTrue);
      expect(s.result, {
        'winnerIds': ['a'],
        'summary': 'Ann sank the whole fleet!',
      });
      expect(s.tableView()['turn'], isNull);
      expect(board(s, 'b')['afloat'], isEmpty);
      expect(() => s.applyAction('b', fire(0)), throwsRefusal);
    });

    test('the host option reaches the session', () {
      final on = seaSiegeDefinition.createSession(
        const [a, b],
        0,
        Random(1),
        {'shootAgain': true},
      );
      expect(on.tableView()['shootAgain'], isTrue);
      final off = seaSiegeDefinition.createSession(
        const [a, b],
        0,
        Random(1),
        seaSiegeDefinition.defaultOptions,
      );
      expect(off.tableView()['shootAgain'], isFalse);
    });
  });

  // Not playable yet (maxPlayers is 2), but the engine is ready for it.
  group('free-for-all stub', () {
    SeaSiegeSession three() => SeaSiegeSession.custom(
      const [a, b, c],
      fleets: {'a': rowsFleet, 'b': rowsFleet, 'c': rowsFleet},
      shootAgain: true,
    );

    test('with several opponents a shot must name its target', () {
      final s = three();
      expect(() => s.applyAction('a', fire(0)), throwsRefusal);
      s.applyAction('a', fire(0, 'c'));
      expect(board(s, 'c')['hits'], [0]);
    });

    test('sunk fleets are skipped and the last fleet afloat wins', () {
      final s = three();
      for (final cell in fleetCells) {
        s.applyAction('a', fire(cell, 'b'));
      }
      expect(s.isOver, isFalse);
      s.applyAction('a', fire(99, 'c')); // a miss: the turn moves on
      expect(s.tableView()['turn'], 'c', reason: 'b is out');
      expect(() => s.applyAction('c', fire(50, 'b')), throwsRefusal);
      for (final cell in fleetCells) {
        s.applyAction('c', fire(cell, 'a'));
      }
      expect(s.result!['winnerIds'], ['c']);
    });
  });

  group('random games', () {
    for (var seed = 0; seed < 20; seed++) {
      final shootAgain = seed.isOdd;
      test('seed $seed (shoot again: $shootAgain) ends without leaks', () {
        final random = Random(seed);
        final s = SeaSiegeSession(
          const [a, b],
          round: seed,
          random: random,
          shootAgain: shootAgain,
        );
        if (random.nextBool()) s.applyAction('a', {'type': 'shuffle'});
        s
          ..applyAction('a', {'type': 'ready'})
          ..applyAction('b', {'type': 'ready'});
        final fleets = {'a': fleetOf(s, 'a'), 'b': fleetOf(s, 'b')};
        for (var shots = 0; !s.isOver; shots++) {
          expect(shots, lessThan(200), reason: 'the game never ends');
          expectPrivate(s, fleets);
          final shooter = s.tableView()['turn']! as String;
          final target = shooter == 'a' ? 'b' : 'a';
          final tried = {
            ...(board(s, target)['hits']! as List).cast<int>(),
            ...(board(s, target)['misses']! as List).cast<int>(),
          };
          final open = [
            for (var i = 0; i < 100; i++)
              if (!tried.contains(i)) i,
          ];
          s.applyAction(shooter, fire(open[random.nextInt(open.length)]));
        }
        expectPrivate(s, fleets);
        expect(s.result, isNotNull);
      });
    }
  });
}

/// Privacy: the table never shows a ship that is still afloat, and each
/// player's view adds only their own fleet to the table.
void expectPrivate(SeaSiegeSession s, Map<String, List<Ship>> fleets) {
  final table = s.tableView();
  expect(table, isNot(contains('fleet')));
  for (final MapEntry(key: id, value: fleet) in fleets.entries) {
    final b = (table['boards']! as Json)[id]! as Json;
    expect(b.keys, unorderedEquals(['hits', 'misses', 'sunk', 'afloat']));
    final hits = (b['hits']! as List).cast<int>().toSet();
    for (final sunk in b['sunk']! as List) {
      final cells = ((sunk! as Json)['cells']! as List).cast<int>();
      expect(hits.containsAll(cells), isTrue, reason: 'only sunk ships show');
    }
    final view = s.viewFor(id);
    expect(view.keys.toSet(), {...table.keys, 'fleet'});
    for (final key in table.keys) {
      expect(view[key], table[key], reason: 'view and table differ on $key');
    }
    final shown = [
      for (final ship in view['fleet']! as List) (ship! as Json)['cells'],
    ];
    expect(shown, [for (final ship in fleet) ship.cells]);
  }
}
