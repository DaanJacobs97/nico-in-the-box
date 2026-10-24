import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/games/tacticalvoxelrpg/tacticalvoxelrpg_game.dart';
import 'package:nico_shared/games/tacticalvoxelrpg/tacticalvoxelrpg_map.dart';
import 'package:nico_shared/net/protocol.dart';

const p1 = PlayerInfo(id: 'p1', nickname: 'Vera');
const p2 = PlayerInfo(id: 'p2', nickname: 'Rook');

List<VoxelTile> _flatTiles({bool withWall = false}) => [
  for (var y = 0; y < tacticalMapHeight; y++)
    for (var x = 0; x < tacticalMapWidth; x++)
      VoxelTile(
        x: x,
        y: y,
        terrain: withWall && x == 2 && y == 1 ? 'wall' : 'floor',
      ),
];

List<TacticalUnit> _units({bool ai = true, int aiHp = 8}) => [
  TacticalUnit(
    id: 'p1-closeCombat',
    ownerId: 'p1',
    kind: TacticalClass.closeCombat,
    x: 1,
    y: 1,
  ),
  TacticalUnit(
    id: 'p1-ranged',
    ownerId: 'p1',
    kind: TacticalClass.ranged,
    x: 1,
    y: 2,
  ),
  TacticalUnit(
    id: 'p1-trapper',
    ownerId: 'p1',
    kind: TacticalClass.trapper,
    x: 1,
    y: 3,
  ),
  if (!ai) ...[
    TacticalUnit(
      id: 'p2-closeCombat',
      ownerId: 'p2',
      kind: TacticalClass.closeCombat,
      x: 18,
      y: 11,
    ),
    TacticalUnit(
      id: 'p2-ranged',
      ownerId: 'p2',
      kind: TacticalClass.ranged,
      x: 18,
      y: 12,
    ),
    TacticalUnit(
      id: 'p2-trapper',
      ownerId: 'p2',
      kind: TacticalClass.trapper,
      x: 18,
      y: 13,
    ),
  ],
  if (ai)
    TacticalUnit(
      id: 'ai-closeCombat',
      ownerId: tacticalAiId,
      kind: TacticalClass.closeCombat,
      x: 3,
      y: 1,
      hp: aiHp,
    ),
];

TacticalVoxelRPGSession _custom({
  List<PlayerInfo> players = const [p1],
  List<TacticalUnit>? units,
  List<VoxelTile>? tiles,
  String turn = 'p1',
  String activeUnit = 'p1-closeCombat',
}) {
  final customUnits = units ?? _units();
  for (final unit in customUnits.where(
    (unit) => unit.ownerId != tacticalAiId,
  )) {
    unit.mana = unit.kind.maximumMana;
  }
  for (final unit in customUnits.where(
    (unit) => unit.ownerId != tacticalAiId,
  )) {
    unit.hand = [
      TacticalCard(id: 0, kind: TacticalCardKind.move),
      TacticalCard(id: 1, kind: TacticalCardKind.attack),
      TacticalCard(id: 2, kind: TacticalCardKind.trap),
      TacticalCard(id: 3, kind: TacticalCardKind.overwatch),
      TacticalCard(id: 4, kind: TacticalCardKind.skill),
    ];
  }
  final game = TacticalVoxelRPGSession.custom(
    players: players,
    map: TacticalMap.custom(tiles ?? _flatTiles()),
    units: customUnits,
    turnOwner: turn,
  );
  if (turn == 'p1' && customUnits.any((unit) => unit.id == activeUnit)) {
    game.applyAction('p1', {'type': 'selectUnit', 'unit': activeUnit});
  }
  return game;
}

int _cardId(
  TacticalVoxelRPGSession game,
  String unitId,
  TacticalCardKind kind,
) {
  final unit = (game.viewFor('p1')['units']! as List<Object?>)
      .cast<Json>()
      .firstWhere((unit) => unit['id'] == unitId);
  return ((unit['hand']! as List<Object?>).cast<Json>().firstWhere(
        (card) => card['kind'] == kind.name,
      ))['id']!
      as int;
}

void _playCard(
  TacticalVoxelRPGSession game,
  String unitId,
  TacticalCardKind kind, {
  List<GridPoint>? path,
  String? target,
  GridPoint? point,
}) {
  game.applyAction('p1', {
    'type': 'playCard',
    'unit': unitId,
    'cardId': _cardId(game, unitId, kind),
    if (path != null) 'path': [for (final tile in path) tile.toJson()],
    'target': ?target,
    'x': ?point?.x,
    'y': ?point?.y,
  });
}

void _finishAndSelect(TacticalVoxelRPGSession game, String unitId) {
  if (game.tableView()['activeUnit'] != unitId) {
    game.applyAction('p1', {'type': 'selectUnit', 'unit': unitId});
  }
  game.applyAction('p1', {'type': 'finishUnit', 'unit': unitId});
}

void main() {
  group('pre-battle company selection', () {
    test('all joined players must ready before battle starts', () {
      final game = tacticalVoxelRPGDefinition.createSession(
        [p1, p2],
        0,
        Random(16),
        const {},
      );
      expect(game.viewFor('p1')['phase'], 'selection');
      expect(game.viewFor('p2')['phase'], 'selection');
      expect(game.viewFor('p1')['draftSelectedUnitIds'], isEmpty);

      for (final unit in ['closeCombat', 'ranged', 'trapper']) {
        game.applyAction('p1', {
          'type': 'draftSelectUnit',
          'unit': 'p1-$unit',
          'selected': true,
        });
      }
      game.applyAction('p1', {'type': 'draftReady', 'ready': true});
      expect(game.viewFor('p1')['phase'], 'selection');
      expect(game.tableView()['draftReadyCount'], 1);

      for (final unit in ['closeCombat', 'ranged', 'trapper']) {
        game.applyAction('p2', {
          'type': 'draftSelectUnit',
          'unit': 'p2-$unit',
          'selected': true,
        });
      }
      game.applyAction('p2', {'type': 'draftReady', 'ready': true});
      expect(game.viewFor('p1')['phase'], 'battle');
      expect(game.viewFor('p2')['phase'], 'battle');
    });

    test('each player must select three heroes before readying up', () {
      final game = TacticalVoxelRPGSession(
        [p1],
        random: Random(17),
        preBattleSelection: true,
      );
      for (final unit in ['closeCombat', 'ranged']) {
        game.applyAction('p1', {
          'type': 'draftSelectUnit',
          'unit': 'p1-$unit',
          'selected': true,
        });
      }
      expect(game.viewFor('p1')['draftSelectedUnitIds'], hasLength(2));
      expect(
        () => game.applyAction('p1', {'type': 'draftReady', 'ready': true}),
        throwsA(isA<GameActionException>()),
      );

      game.applyAction('p1', {
        'type': 'draftSelectUnit',
        'unit': 'p1-trapper',
        'selected': true,
      });
      game.applyAction('p1', {'type': 'draftReady', 'ready': true});
      expect(game.viewFor('p1')['phase'], 'battle');
    });

    test('the 60-second draft timeout starts the battle', () {
      final game = TacticalVoxelRPGSession(
        [p1],
        random: Random(18),
        preBattleSelection: true,
        selectionDuration: Duration.zero,
      );
      expect(game.viewFor('p1')['draftSeconds'], 0);
      game.applyAction('p1', {'type': 'draftTimeout'});
      expect(game.viewFor('p1')['phase'], 'battle');
      expect(
        (game.tableView()['units']! as List<Object?>).cast<Json>().where(
          (unit) => unit['owner'] == 'p1',
        ),
        hasLength(3),
      );
    });
  });

  group('mission setup', () {
    test('one player receives three units and a solo AI team', () {
      final game = TacticalVoxelRPGSession([p1], random: Random(10));
      final units = (game.tableView()['units']! as List<Object?>).cast<Json>();
      final squad = units.where((unit) => unit['owner'] == 'p1').toList();
      expect(squad, hasLength(3));
      expect(squad.map((unit) => unit['movement']), [5, 4, 8]);
      expect(squad.map((unit) => unit['weapon']), [
        'Iron greatsword',
        'Worn longbow',
        'Ashwood staff',
      ]);
      expect(squad.map((unit) => unit['energy']), [2, 2, 2]);
      final privateUnits = (game.viewFor('p1')['units']! as List<Object?>)
          .cast<Json>()
          .where((unit) => unit['owner'] == 'p1');
      expect(
        privateUnits.every((unit) => (unit['hand'] as List).length == 5),
        isTrue,
      );
      expect(
        (game.tableView()['units']! as List<Object?>)
            .cast<Json>()
            .where((unit) => unit['owner'] == 'p1')
            .every((unit) => !unit.containsKey('hand')),
        isTrue,
      );
      expect(
        units.where((unit) => unit['owner'] == tacticalAiId),
        hasLength(3),
      );
      expect(
        units
            .where((unit) => unit['owner'] == tacticalAiId)
            .every(
              (unit) => [
                'acid',
                'dark',
                'fire',
                'plasma',
                'water',
              ].contains(unit['sprite']),
            ),
        isTrue,
      );
      expect(game.tableView()['solo'], isTrue);
      expect(game.tableView()['width'], tacticalSoloMapWidth);
      expect(game.tableView()['height'], tacticalSoloMapHeight);
      expect(game.tableView()['tiles'], hasLength(15 * 15));
    });

    test('two players each get three units and no AI', () {
      final game = TacticalVoxelRPGSession([p1, p2], random: Random(12));
      final units = (game.tableView()['units']! as List<Object?>).cast<Json>();
      expect(units, hasLength(6));
      expect(units.any((unit) => unit['owner'] == tacticalAiId), isFalse);
      expect(game.tableView()['solo'], isFalse);
      expect(game.tableView()['width'], tacticalMapWidth);
      expect(game.tableView()['height'], tacticalMapHeight);
    });

    test('minimum and maximum player counts are one and six', () {
      expect(tacticalVoxelRPGDefinition.minPlayers, 1);
      expect(tacticalVoxelRPGDefinition.maxPlayers, 6);
      final tooMany = [
        for (var i = 1; i <= 7; i++)
          PlayerInfo(id: 'p$i', nickname: 'Player $i'),
      ];
      expect(() => TacticalVoxelRPGSession(tooMany), throwsArgumentError);
    });

    test('map generation is reproducible with coherent biomes and paths', () {
      final first = TacticalMap.generate(Random(42));
      final second = TacticalMap.generate(Random(42));
      expect(
        first.tiles.map((tile) => tile.toJson()).toList(),
        second.tiles.map((tile) => tile.toJson()).toList(),
      );
      expect(first.tiles, hasLength(40 * 30));
      expect(tacticalMapWidth, 40);
      expect(tacticalMapHeight, 30);
      expect(first.spawnTeams, hasLength(6));
      expect(first.tiles.any((tile) => tile.biome == 'forest'), isTrue);
      expect(first.tiles.any((tile) => tile.biome == 'highland'), isTrue);
      expect(first.tiles.any((tile) => tile.biome == 'wetland'), isTrue);
      expect(first.tiles.any((tile) => tile.terrain == 'water'), isTrue);
      expect(first.tiles.any((tile) => tile.terrain == 'cliff'), isTrue);
      expect(first.tiles.any((tile) => tile.terrain == 'path'), isTrue);
      expect(first.tiles.any((tile) => tile.biome == 'underground'), isFalse);
      for (final team in first.spawnTeams) {
        for (final point in team) {
          expect(first.tileAt(point).passable, isTrue);
        }
      }
      expect(
        first.findPath(
          first.spawnTeams.first.first,
          first.spawnTeams.last.first,
          blocked: (_) => false,
        ),
        isNotNull,
      );
    });
  });

  group('energy and routes', () {
    test(
      'each unit starts with two action points and Strides follows its route',
      () {
        final game = _custom()
          ..applyAction('p1', {
            'type': 'planRoute',
            'unit': 'p1-closeCombat',
            'path': [
              const GridPoint(2, 1).toJson(),
              const GridPoint(2, 2).toJson(),
            ],
          });
        _playCard(game, 'p1-closeCombat', TacticalCardKind.move);
        final table = game.tableView();
        final unit = (table['units']! as List<Object?>).cast<Json>().firstWhere(
          (entry) => entry['id'] == 'p1-closeCombat',
        );
        expect([unit['x'], unit['y']], [2, 2]);
        expect(unit['energy'], 1);
      },
    );

    test('a five-tile Vanguard move spends only one energy', () {
      final units = _units()
        ..firstWhere((unit) => unit.id == 'ai-closeCombat').x = 8;
      units.firstWhere((unit) => unit.id == 'ai-closeCombat').y = 8;
      final game = _custom(units: units);
      _playCard(
        game,
        'p1-closeCombat',
        TacticalCardKind.move,
        path: [for (var x = 2; x <= 6; x++) GridPoint(x, 1)],
      );
      final unit = (game.tableView()['units']! as List<Object?>)
          .cast<Json>()
          .firstWhere((entry) => entry['id'] == 'p1-closeCombat');
      expect([unit['x'], unit['y']], [6, 1]);
      expect(unit['energy'], 1);
    });

    test('movement terrain modifiers are stored on each character', () {
      final game = _custom();
      final unit = (game.tableView()['units']! as List<Object?>)
          .cast<Json>()
          .firstWhere((entry) => entry['id'] == 'p1-closeCombat');
      expect(unit['terrainMovementCosts'], {
        'path': 667,
        'bridge': 667,
        'grass': 1000,
        'deepGrass': 1111,
        'brush': 1000,
        'bank': 1000,
        'forest': 1250,
        'marsh': 1000,
        'river': 10000,
        'water': 10000,
      });
    });

    test('paths extend movement and water exceeds the unskilled budget', () {
      final units = _units()
        ..firstWhere((unit) => unit.id == 'ai-closeCombat').x = 20
        ..firstWhere((unit) => unit.id == 'ai-closeCombat').y = 20;
      final pathTiles = _flatTiles().toList();
      for (var x = 2; x <= 8; x++) {
        pathTiles[1 * tacticalMapWidth + x] = VoxelTile(
          x: x,
          y: 1,
          terrain: 'path',
        );
      }
      final pathGame = _custom(tiles: pathTiles, units: units);
      pathGame.applyAction('p1', {
        'type': 'planRoute',
        'unit': 'p1-closeCombat',
        'path': [for (var x = 2; x <= 8; x++) GridPoint(x, 1).toJson()],
      });

      final waterTiles = _flatTiles().toList()
        ..[1 * tacticalMapWidth + 2] = const VoxelTile(
          x: 2,
          y: 1,
          terrain: 'water',
        );
      expect(waterTiles[1 * tacticalMapWidth + 2].passable, isTrue);
      expect(
        () => _custom(tiles: waterTiles).applyAction('p1', {
          'type': 'planRoute',
          'unit': 'p1-closeCombat',
          'path': [const GridPoint(2, 1).toJson()],
        }),
        throwsA(isA<GameActionException>()),
      );
    });

    test('one move spends one energy regardless of route length', () {
      final tiles = _flatTiles(withWall: true).toList();
      tiles[1 * tacticalMapWidth + 2] = const VoxelTile(
        x: 2,
        y: 1,
        terrain: 'rubble',
      );
      final units = _units()
        ..firstWhere((unit) => unit.id == 'ai-closeCombat').x = 8;
      units.firstWhere((unit) => unit.id == 'ai-closeCombat').y = 8;
      final game = _custom(tiles: tiles, units: units);
      _playCard(
        game,
        'p1-closeCombat',
        TacticalCardKind.move,
        path: [const GridPoint(2, 1), const GridPoint(3, 1)],
      );
      final unit = (game.tableView()['units']! as List<Object?>)
          .cast<Json>()
          .firstWhere((entry) => entry['id'] == 'p1-closeCombat');
      expect([unit['x'], unit['y']], [3, 1]);
      expect(unit['energy'], 1);
    });

    test('route planning rejects walls and non-adjacent jumps', () {
      final game = _custom(tiles: _flatTiles(withWall: true));
      expect(
        () => game.applyAction('p1', {
          'type': 'planRoute',
          'unit': 'p1-closeCombat',
          'path': [const GridPoint(2, 1).toJson()],
        }),
        throwsA(isA<GameActionException>()),
      );
      expect(
        () => game.applyAction('p1', {
          'type': 'planRoute',
          'unit': 'p1-closeCombat',
          'path': [const GridPoint(4, 1).toJson()],
        }),
        throwsA(isA<GameActionException>()),
      );
    });
  });

  group('combat and traps', () {
    test(
      'Weapon strike spends one AP and deals eight damage in weapon range',
      () {
        final game = _custom(units: _units(aiHp: 18), activeUnit: 'p1-ranged');
        _playCard(
          game,
          'p1-ranged',
          TacticalCardKind.attack,
          target: 'ai-closeCombat',
        );
        final target = (game.tableView()['units']! as List<Object?>)
            .cast<Json>()
            .firstWhere((unit) => unit['id'] == 'ai-closeCombat');
        expect(target['hp'], 10);
        expect(game.tableView()['lastAction'], containsPair('damage', 8));
        final attacker = (game.tableView()['units']! as List<Object?>)
            .cast<Json>()
            .firstWhere((unit) => unit['id'] == 'p1-ranged');
        expect(attacker['energy'], 1);
      },
    );

    test('Thorn snare can be placed nearby and triggers for six damage', () {
      final units = _units()
        ..removeWhere(
          (unit) => unit.id != 'p1-trapper' && unit.id != 'ai-closeCombat',
        )
        ..removeWhere((unit) => unit.id == 'ai-closeCombat')
        ..add(
          TacticalUnit(
            id: 'ai-closeCombat',
            ownerId: tacticalAiId,
            kind: TacticalClass.closeCombat,
            x: 5,
            y: 3,
          ),
        );
      final game = _custom(units: units, activeUnit: 'p1-trapper');
      _playCard(
        game,
        'p1-trapper',
        TacticalCardKind.trap,
        point: const GridPoint(3, 3),
      );
      game
        ..applyAction('p1', {'type': 'finishUnit', 'unit': 'p1-trapper'})
        ..applyAction('p1', {'type': 'endTurn'});
      final guard = (game.tableView()['units']! as List<Object?>)
          .cast<Json>()
          .firstWhere((unit) => unit['id'] == 'ai-closeCombat');
      expect(guard['hp'], 2);
      expect(game.tableView()['traps'], isEmpty);
    });

    test('Thorn snare can be placed on a tile along the planned route', () {
      final units = [
        TacticalUnit(
          id: 'p1-trapper',
          ownerId: 'p1',
          kind: TacticalClass.trapper,
          x: 1,
          y: 3,
          mana: 6,
          maxMana: 6,
        ),
      ];
      final game = _custom(units: units, activeUnit: 'p1-trapper');
      game.applyAction('p1', {
        'type': 'planRoute',
        'unit': 'p1-trapper',
        'path': [for (var x = 2; x <= 6; x++) GridPoint(x, 3).toJson()],
      });
      _playCard(
        game,
        'p1-trapper',
        TacticalCardKind.trap,
        point: const GridPoint(6, 3),
      );
      _playCard(game, 'p1-trapper', TacticalCardKind.move);

      expect(game.tableView()['traps'], [
        {'owner': 'p1', 'x': 6, 'y': 3, 'damage': 6},
      ]);
      final trapper = (game.tableView()['units']! as List<Object?>)
          .cast<Json>()
          .single;
      expect([trapper['x'], trapper['y']], [6, 3]);
    });
  });

  group('turns, outcomes and views', () {
    test('two-player turns alternate without running an AI phase', () {
      final game = _custom(players: const [p1, p2], units: _units(ai: false));
      _finishAndSelect(game, 'p1-closeCombat');
      _finishAndSelect(game, 'p1-ranged');
      _finishAndSelect(game, 'p1-trapper');
      game.applyAction('p1', {'type': 'endTurn'});
      expect(game.tableView()['turn'], 'p2');
      expect((game.tableView()['units']! as List<Object?>).length, 6);
    });

    test('Soul rend defeats the final opposing unit and wins the mission', () {
      final units = _units(aiHp: 2);
      units.removeWhere(
        (unit) => unit.id != 'p1-closeCombat' && unit.id != 'ai-closeCombat',
      );
      units.firstWhere((unit) => unit.id == 'p1-closeCombat').x = 2;
      final game = _custom(units: units);
      _playCard(
        game,
        'p1-closeCombat',
        TacticalCardKind.skill,
        target: 'ai-closeCombat',
      );
      expect(game.isOver, isTrue);
      expect(game.result!['winnerIds'], ['p1']);
    });

    test('players see the public battlefield and only their own unit ids', () {
      final game = TacticalVoxelRPGSession([p1], random: Random(8));
      final table = game.tableView();
      final view = game.viewFor('p1');
      for (final key in table.keys) {
        if (key == 'units') continue;
        expect(view[key], table[key], reason: 'public field $key differs');
      }
      expect(view['myUnits'], hasLength(3));
      expect(view['canAct'], isTrue);
      final publicUnits = (table['units']! as List<Object?>).cast<Json>();
      final privateUnits = (view['units']! as List<Object?>).cast<Json>();
      expect(publicUnits.every((unit) => !unit.containsKey('hand')), isTrue);
      expect(
        privateUnits
            .where((unit) => unit['owner'] == 'p1')
            .every((unit) => (unit['hand'] as List).length == 5),
        isTrue,
      );
      expect(
        privateUnits
            .where((unit) => unit['owner'] == tacticalAiId)
            .every((unit) => !unit.containsKey('hand')),
        isTrue,
      );
    });
  });
}
