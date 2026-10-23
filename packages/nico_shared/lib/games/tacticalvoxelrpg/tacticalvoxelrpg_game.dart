import 'dart:math';

import '../../net/protocol.dart';
import '../game_session.dart';
import 'tacticalvoxelrpg_map.dart';

part 'tacticalvoxelrpg_movement.dart';
part 'tacticalvoxelrpg_cards.dart';

const tacticalVoxelRPGDefinition = GameDefinition(
  id: 'tacticalvoxelrpg',
  name: 'Tactical Voxel RPG',
  description: 'Command three heroes through connected rooms and corridors.',
  minPlayers: 1,
  maxPlayers: 6,
  createSession: _create,
);

const tacticalEnergyPerTurn = 2;
const tacticalAiId = '__ai__';
const tacticalMovementScale = 1000;
const tacticalDefaultMovementCosts = <String, int>{
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
};

GameSession _create(
  List<PlayerInfo> players,
  int round,
  Random random,
  GameOptions _,
) => TacticalVoxelRPGSession(players, round: round, random: random);

enum TacticalClass { closeCombat, ranged, trapper }

extension TacticalClassLabel on TacticalClass {
  String get label => switch (this) {
    TacticalClass.closeCombat => 'Vanguard',
    TacticalClass.ranged => 'Ranger',
    TacticalClass.trapper => 'Trapper',
  };

  int get range => switch (this) {
    TacticalClass.closeCombat => 1,
    TacticalClass.ranged => 6,
    TacticalClass.trapper => 3,
  };

  int get minimumRange => switch (this) {
    TacticalClass.closeCombat => 1,
    TacticalClass.ranged => 2,
    TacticalClass.trapper => 1,
  };

  int get maximumHp => switch (this) {
    TacticalClass.closeCombat => 40,
    TacticalClass.ranged => 32,
    TacticalClass.trapper => 26,
  };

  int get startingHp => switch (this) {
    TacticalClass.closeCombat => 38,
    TacticalClass.ranged => 28,
    TacticalClass.trapper => 22,
  };

  int get maximumMana => switch (this) {
    TacticalClass.closeCombat => 2,
    TacticalClass.ranged => 3,
    TacticalClass.trapper => 6,
  };

  String get weapon => switch (this) {
    TacticalClass.closeCombat => 'Iron greatsword',
    TacticalClass.ranged => 'Worn longbow',
    TacticalClass.trapper => 'Ashwood staff',
  };

  int get movement => switch (this) {
    TacticalClass.closeCombat => 5,
    TacticalClass.ranged => 4,
    TacticalClass.trapper => 8,
  };
}

class TacticalUnit {
  TacticalUnit({
    required this.id,
    required this.ownerId,
    required this.kind,
    required this.x,
    required this.y,
    this.hp = 8,
    this.maxHp = 8,
    this.energy = tacticalEnergyPerTurn,
    this.trapCharges = 2,
    this.terrainMovementCosts = tacticalDefaultMovementCosts,
    this.sprite,
    this.displayName,
    this.role,
    this.mana = 0,
    this.maxMana = 0,
  });

  final String id;
  final String ownerId;
  final TacticalClass kind;
  int x;
  int y;
  int hp;
  final int maxHp;
  int energy;
  int trapCharges;
  final Map<String, int> terrainMovementCosts;
  final String? sprite;
  final String? displayName;
  final String? role;
  int mana;
  final int maxMana;
  bool completed = false;
  bool overwatch = false;
  int? retainedCardId;
  List<TacticalCard> hand = [];
  List<TacticalCard> drawPile = [];
  List<TacticalCard> discardPile = [];
  List<GridPoint> route = [];

  int movementCostFor(VoxelTile tile) =>
      terrainMovementCosts[tile.terrain] ??
      terrainMovementCosts[tile.biome] ??
      tacticalMovementScale;

  Json toJson({bool includePrivate = false}) => {
    'id': id,
    'owner': ownerId,
    'kind': kind.name,
    'name': displayName ?? kind.label,
    'role': role ?? kind.label,
    'x': x,
    'y': y,
    'hp': hp,
    'maxHp': maxHp,
    'energy': energy,
    'maxEnergy': tacticalEnergyPerTurn,
    'range': kind.range,
    'minimumRange': kind.minimumRange,
    'weapon': kind.weapon,
    'movement': kind.movement,
    'mana': mana,
    'maxMana': maxMana,
    'completed': completed,
    'overwatch': overwatch,
    'handSize': hand.length,
    'drawCount': drawPile.length,
    'discardCount': discardPile.length,
    'terrainMovementCosts': terrainMovementCosts,
    if (sprite != null) 'sprite': sprite,
    'trapCharges': trapCharges,
    'route': [for (final point in route) point.toJson()],
    if (includePrivate) 'hand': [for (final card in hand) card.toJson()],
    if (includePrivate)
      'drawPile': [for (final card in drawPile) card.toJson()],
    if (includePrivate)
      'discardPile': [for (final card in discardPile) card.toJson()],
    if (includePrivate) 'retainedCardId': retainedCardId,
  };
}

class TacticalTrap {
  const TacticalTrap({
    required this.ownerId,
    required this.x,
    required this.y,
    this.damage = 6,
  });

  final String ownerId;
  final int x;
  final int y;
  final int damage;

  Json toJson() => {'owner': ownerId, 'x': x, 'y': y, 'damage': damage};
}

/// Each player activates the three unit cards once per round. Each activation
/// has two action points and a private five-card hand.
///
/// Actions: `selectUnit`, `planRoute`, `playCard`, `retainCard`, `finishUnit`,
/// and `endTurn`.
class TacticalVoxelRPGSession implements GameSession {
  TacticalVoxelRPGSession(
    List<PlayerInfo> players, {
    int round = 0,
    Random? random,
  }) : _players = List.of(players),
       _random = random ?? Random(),
       // These public parameter names deliberately remain distinct from the
       // private fields used to store them.
       // ignore: prefer_initializing_formals
       _round = round {
    if (players.isEmpty || players.length > 6) {
      throw ArgumentError(
        'Tactical Voxel RPG needs between one and six players.',
      );
    }
    _map = TacticalMap.generate(_random, solo: players.length == 1);
    _turnOrder = [for (final player in players) player.id];
    if (players.length == 1) _turnOrder.add(tacticalAiId);
    const spawnSlots = {
      1: [0],
      2: [0, 5],
      3: [0, 2, 5],
      4: [0, 2, 3, 5],
      5: [0, 1, 2, 4, 5],
      6: [0, 1, 2, 3, 4, 5],
    };
    final slots = spawnSlots[players.length]!;
    for (var i = 0; i < players.length; i++) {
      _addTeam(players[i].id, _map.spawnTeams[slots[i]]);
    }
    if (players.length == 1) {
      _addTeam(tacticalAiId, _map.spawnTeams.last);
    }
    _selectedUnitId = null;
  }

  /// Exact map and unit state for engine tests and scripted scenarios.
  TacticalVoxelRPGSession.custom({
    required List<PlayerInfo> players,
    required TacticalMap map,
    required List<TacticalUnit> units,
    String? turnOwner,
    int round = 0,
  }) : _players = List.of(players),
       _random = Random(0),
       // ignore: prefer_initializing_formals
       _map = map,
       _units = List.of(units),
       _round = round {
    if (players.isEmpty || players.length > 6) {
      throw ArgumentError(
        'Tactical Voxel RPG needs between one and six players.',
      );
    }
    _turnOrder = [for (final player in players) player.id];
    if (players.length == 1 &&
        units.any((unit) => unit.ownerId == tacticalAiId)) {
      _turnOrder.add(tacticalAiId);
    }
    _turnIndex = turnOwner == null
        ? round % _turnOrder.length
        : _turnOrder.indexOf(turnOwner);
    if (_turnIndex < 0) throw ArgumentError('Unknown turn owner.');
    for (final unit in _units.where((unit) => unit.ownerId != tacticalAiId)) {
      _initializeCards(unit);
    }
    _selectedUnitId = null;
  }

  final List<PlayerInfo> _players;
  final Random _random;
  late TacticalMap _map;
  List<TacticalUnit> _units = [];
  final List<TacticalTrap> _traps = [];
  late List<String> _turnOrder;
  int _turnIndex = 0;
  int _round = 0;
  String? _selectedUnitId;
  bool _over = false;
  String? _winnerId;
  Json? _lastAction;
  int _eventId = 0;
  final List<Json> _recentActions = [];

  String get _turnOwner => _turnOrder[_turnIndex];
  TacticalUnit? get _selectedUnit => _unitById(_selectedUnitId);
  bool get _isAiTurn => _turnOwner == tacticalAiId;

  void _addTeam(String owner, List<GridPoint> spawns) {
    const classes = [
      TacticalClass.closeCombat,
      TacticalClass.ranged,
      TacticalClass.trapper,
    ];
    const slimeSprites = ['acid', 'dark', 'fire', 'plasma', 'water'];
    const playerNames = ['Aldric', 'Seren', 'Mora'];
    const playerRoles = ['THE OATHKEEPER', 'THE WAYFARER', 'THE HEXWEAVER'];
    const enemyNames = ['Hollow guard', 'Hollow archer', 'Blight hound'];
    const enemyHp = [18, 16, 14];
    for (var i = 0; i < classes.length; i++) {
      final isEnemy = owner == tacticalAiId;
      final sprite = isEnemy
          ? slimeSprites[_random.nextInt(slimeSprites.length)]
          : null;
      final unit = TacticalUnit(
        id: '$owner-${classes[i].name}',
        ownerId: owner,
        kind: classes[i],
        x: spawns[i].x,
        y: spawns[i].y,
        hp: isEnemy ? enemyHp[i] : classes[i].startingHp,
        maxHp: isEnemy ? enemyHp[i] : classes[i].maximumHp,
        mana: isEnemy ? 0 : classes[i].maximumMana,
        maxMana: isEnemy ? 0 : classes[i].maximumMana,
        displayName: isEnemy ? enemyNames[i] : playerNames[i],
        role: isEnemy ? 'THE HOLLOWED' : playerRoles[i],
        sprite: sprite,
      );
      _units.add(unit);
      if (!isEnemy) _initializeCards(unit);
    }
  }

  @override
  bool get isOver => _over;

  @override
  void applyAction(String playerId, Json action) {
    if (isOver) throw const GameActionException('The mission is over.');
    if (!_players.any((player) => player.id == playerId)) {
      throw const GameActionException('You are not in this mission.');
    }
    if (playerId != _turnOwner) {
      throw const GameActionException("It's the other team's turn.");
    }
    switch (action['type']) {
      case 'selectUnit':
        _selectUnit(playerId, action);
      case 'planRoute':
        _planRoute(playerId, action);
      case 'playCard':
        _playCard(playerId, action);
      case 'retainCard':
        _retainCard(playerId, action);
      case 'finishUnit':
        _finishUnit(playerId, action);
      case 'endTurn':
        _endPlayerTurn(playerId);
      default:
        throw const GameActionException('Unknown move.');
    }
  }

  void _selectUnit(String playerId, Json action) {
    final unitId = action['unit'];
    final unit = unitId is String ? _unitById(unitId) : null;
    if (unit == null || unit.ownerId != playerId) {
      throw const GameActionException('Choose one of your units.');
    }
    if (unit.completed) {
      throw const GameActionException(
        'That unit has already acted this round.',
      );
    }
    if (_selectedUnitId != null && _selectedUnitId != unit.id) {
      throw const GameActionException(
        'Finish the active unit before switching.',
      );
    }
    _selectedUnitId = unit.id;
  }

  void _planRoute(String playerId, Json action) {
    final unit = _actionUnit(playerId, action);
    if (unit.energy <= 0 || unit.completed) {
      throw const GameActionException('That unit has no energy left.');
    }
    final route = _readRoute(action['path']);
    _validateRoute(unit, route);
    unit.route = route;
    _selectedUnitId = unit.id;
  }

  TacticalUnit _actionUnit(String playerId, Json action) {
    final requestedId = action['unit'];
    final unit = requestedId is String ? _unitById(requestedId) : _selectedUnit;
    if (unit == null ||
        unit.ownerId != playerId ||
        unit.id != _selectedUnitId ||
        unit.completed) {
      throw const GameActionException('Select one of your units first.');
    }
    return unit;
  }

  List<GridPoint> _readRoute(Object? value) {
    if (value is! List<Object?>) {
      throw const GameActionException('A route must be a list of map tiles.');
    }
    try {
      return [for (final point in value) GridPoint.fromJson(point)];
    } on FormatException {
      throw const GameActionException('A route contains an invalid tile.');
    }
  }

  void _advanceTurn() {
    if (isOver) return;
    final previousOwner = _turnOwner;
    if (previousOwner != tacticalAiId) {
      for (final unit in _units.where(
        (unit) => unit.ownerId == previousOwner,
      )) {
        _prepareCardsForNextTurn(unit);
      }
    }
    _turnIndex = (_turnIndex + 1) % _turnOrder.length;
    if (_turnIndex == 0) _round++;
    final owner = _turnOwner;
    for (final unit in _units.where((unit) => unit.ownerId == owner)) {
      unit.energy = tacticalEnergyPerTurn;
      unit.completed = false;
      unit.overwatch = false;
      unit.route = [];
      if (owner != tacticalAiId) _drawCards(unit);
    }
    _selectedUnitId = null;
    if (_isAiTurn) {
      _runAiTurn();
      if (!isOver) _advanceTurn();
    }
  }

  void _endPlayerTurn(String playerId) {
    final team = _units.where((unit) => unit.ownerId == playerId);
    if (team.isEmpty || team.any((unit) => !unit.completed)) {
      throw const GameActionException(
        'Finish every unit before ending the round.',
      );
    }
    _advanceTurn();
  }

  bool _inWeaponRange(TacticalUnit attacker, TacticalUnit target) {
    final distance = _distance(attacker.point, target.point);
    return distance >= attacker.kind.minimumRange &&
        distance <= attacker.kind.range;
  }

  void _attackAi(TacticalUnit attacker, TacticalUnit target) {
    target.hp = max(0, target.hp - 3);
    attacker.energy--;
    attacker.completed = true;
    final hp = max(0, target.hp);
    final x = target.x;
    final y = target.y;
    if (target.hp <= 0) _units.remove(target);
    _recordLastAction({
      'type': 'attack',
      'unit': attacker.id,
      'target': target.id,
      'animation': switch (attacker.kind) {
        TacticalClass.closeCombat => 'melee',
        TacticalClass.ranged => 'ranged',
        TacticalClass.trapper => 'special',
      },
      'damage': 3,
      'targetHp': hp,
      'x': x,
      'y': y,
    });
    _checkOutcome();
  }

  bool _triggerTrap(TacticalUnit unit) {
    final index = _traps.indexWhere(
      (trap) =>
          trap.x == unit.x && trap.y == unit.y && trap.ownerId != unit.ownerId,
    );
    if (index < 0) return false;
    _traps.removeAt(index);
    unit.hp -= 6;
    _recordLastAction({
      'type': 'trapHit',
      'unit': unit.id,
      'damage': 6,
      'targetHp': max(0, unit.hp),
      'x': unit.x,
      'y': unit.y,
    });
    if (unit.hp <= 0) _units.remove(unit);
    _checkOutcome();
    return true;
  }

  bool _triggerOverwatch(TacticalUnit movingUnit) {
    final watcher = _units
        .where((unit) => unit.ownerId != movingUnit.ownerId && unit.overwatch)
        .where((unit) => _inWeaponRange(unit, movingUnit))
        .firstOrNull;
    if (watcher == null) return false;
    watcher.overwatch = false;
    movingUnit.hp = max(0, movingUnit.hp - 8);
    _recordLastAction({
      'type': 'overwatchHit',
      'unit': watcher.id,
      'target': movingUnit.id,
      'damage': 8,
      'targetHp': movingUnit.hp,
      'x': movingUnit.x,
      'y': movingUnit.y,
    });
    if (movingUnit.hp <= 0) _units.remove(movingUnit);
    _checkOutcome();
    return true;
  }

  void _checkOutcome() {
    final owners = _units.map((unit) => unit.ownerId).toSet();
    if (owners.length <= 1) {
      _winnerId = owners.firstOrNull;
      _over = true;
    }
  }

  void _recordLastAction(Json action) {
    _lastAction = {...action, 'event': ++_eventId};
    _recentActions.add(_lastAction!);
    if (_recentActions.length > 32) _recentActions.removeAt(0);
  }

  TacticalUnit? _unitById(String? id) {
    if (id == null) return null;
    for (final unit in _units) {
      if (unit.id == id) return unit;
    }
    return null;
  }

  TacticalUnit? _unitAt(GridPoint point) {
    for (final unit in _units) {
      if (unit.point == point) return unit;
    }
    return null;
  }

  TacticalTrap? _trapAt(GridPoint point) {
    for (final trap in _traps) {
      if (trap.x == point.x && trap.y == point.y) return trap;
    }
    return null;
  }

  bool _isEnemy(TacticalUnit a, TacticalUnit b) => a.ownerId != b.ownerId;

  int _distance(GridPoint a, GridPoint b) =>
      (a.x - b.x).abs() + (a.y - b.y).abs();

  @override
  Json tableView() {
    final selected = _selectedUnit;
    final reachable = <GridPoint>[];
    if (selected != null && !_isAiTurn && selected.energy > 0) {
      for (final tile in _map.tiles) {
        if (!tile.passable ||
            _unitAt(GridPoint(tile.x, tile.y)) != null ||
            GridPoint(tile.x, tile.y) == selected.point) {
          continue;
        }
        final route = _map.findPath(
          selected.point,
          GridPoint(tile.x, tile.y),
          blocked: (point) => _unitAt(point) != null,
          movementCost: (point) => selected.movementCostFor(_map.tileAt(point)),
          maxCost: selected.kind.movement * tacticalMovementScale,
        );
        if (route != null) reachable.add(GridPoint(tile.x, tile.y));
      }
    }
    return {
      'width': _map.width,
      'height': _map.height,
      'round': _round,
      'seed': _map.seed,
      'phase': isOver ? 'over' : 'battle',
      'solo': _players.length == 1,
      'tiles': [for (final tile in _map.tiles) tile.toJson()],
      'units': [for (final unit in _units) unit.toJson()],
      'traps': [for (final trap in _traps) trap.toJson()],
      'turn': _isAiTurn ? null : _turnOwner,
      'activeUnit': selected?.id,
      'reachable': [for (final point in reachable) point.toJson()],
      'lastAction': _lastAction,
      'recentActions': List<Json>.unmodifiable(_recentActions),
      'canEndTurn':
          !_isAiTurn &&
          _units
              .where((unit) => unit.ownerId == _turnOwner)
              .every((unit) => unit.completed),
      'winner': _winnerId,
    };
  }

  @override
  Json viewFor(String playerId) => {
    ...tableView(),
    'units': [
      for (final unit in _units)
        unit.toJson(includePrivate: unit.ownerId == playerId),
    ],
    'myUnits': [
      for (final unit in _units)
        if (unit.ownerId == playerId) unit.id,
    ],
    'canAct': !isOver && _turnOwner == playerId,
  };

  @override
  Json? get result {
    if (!isOver) return null;
    final winner = _winnerId;
    if (winner == null || winner == tacticalAiId) {
      return {'winnerIds': <String>[], 'summary': 'The opposing team wins.'};
    }
    final player = _players.firstWhere((entry) => entry.id == winner);
    return {
      'winnerIds': [winner],
      'summary': '${player.nickname} wins in round $_round!',
    };
  }
}

extension on TacticalUnit {
  GridPoint get point => GridPoint(x, y);
}
