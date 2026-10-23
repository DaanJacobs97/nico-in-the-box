import 'dart:math';

import '../../net/protocol.dart';
import '../game_session.dart';
import 'seasiege_fleet.dart';

const seaSiegeDefinition = GameDefinition(
  id: 'seasiege',
  name: 'Sea Siege',
  description: 'Hide your fleet, then hunt theirs. Sink all five ships to win.',
  minPlayers: 2,
  // The engine already handles a free-for-all (every shot names a target and
  // sunk fleets are skipped). Raising this also needs a target picker in the
  // player view, a 3-4 board table and tests.
  maxPlayers: 2,
  category: GameCategory.grid,
  options: [
    GameOption(
      id: 'shootAgain',
      label: 'Hit = shoot again',
      description: 'A hit earns another shot. Off: always take turns.',
    ),
  ],
  createSession: _create,
);

GameSession _create(
  List<PlayerInfo> players,
  int round,
  Random random,
  GameOptions options,
) => SeaSiegeSession(
  players,
  round: round,
  random: random,
  shootAgain: options.flag('shootAgain'),
);

/// One player's side: their ships and the shots fired at them.
class _Sea {
  _Sea(this.fleet);

  List<Ship> fleet;
  bool ready = false;

  /// Shots fired at this board, in order: cell -> the ship hit, or null.
  final Map<int, ShipType?> shots = {};

  bool isSunk(Ship ship) => ship.cells.every(shots.containsKey);
  bool get defeated => fleet.every(isSunk);
}

/// Phases: `placing` (everyone arranges their fleet at once), `battle`
/// (turns), `over`.
///
/// Actions while placing:
/// - `{'type': 'shuffle'}`: a new random layout
/// - `{'type': 'move', 'ship': 'cruiser', 'row': 0-9, 'col': 0-9,
///   'vertical': bool}`: put a ship's bow at a cell, running right or down
/// - `{'type': 'ready'}` / `{'type': 'unready'}`: lock or unlock the fleet;
///   the battle starts when everyone is ready
///
/// In battle: `{'type': 'fire', 'cell': 0-99, 'target': playerId}`. The
/// target may be left out when there is only one opponent.
class SeaSiegeSession implements GameSession {
  SeaSiegeSession(
    List<PlayerInfo> players, {
    int round = 0,
    Random? random,
    this.shootAgain = false,
  }) : _players = players,
       _random = random ?? Random(),
       _turn = round % players.length {
    for (final p in players) {
      _seas[p.id] = _Sea(randomFleet(_random));
    }
  }

  /// A battle already under way with these exact fleets, for tests.
  SeaSiegeSession.custom(
    List<PlayerInfo> players, {
    required Map<String, List<Ship>> fleets,
    String? turn,
    this.shootAgain = false,
  }) : _players = players,
       _random = Random(0),
       _phase = 'battle',
       _turn = turn == null ? 0 : players.indexWhere((p) => p.id == turn) {
    for (final p in players) {
      _seas[p.id] = _Sea(fleets[p.id]!)..ready = true;
    }
  }

  /// The "Hit = shoot again" option.
  final bool shootAgain;

  final List<PlayerInfo> _players;
  final Random _random;
  final Map<String, _Sea> _seas = {};
  String _phase = 'placing';
  int _turn;
  String? _winnerId;

  /// Newest last; the views send the last few.
  final List<Json> _log = [];

  String get _turnId => _players[_turn].id;

  @override
  bool get isOver => _phase == 'over';

  @override
  void applyAction(String playerId, Json action) {
    final sea = _seas[playerId];
    if (sea == null) {
      throw const GameActionException('You are not playing this game.');
    }
    if (isOver) throw const GameActionException('The game is over.');
    final type = action['type'];
    if (_phase == 'placing') {
      _place(sea, type, action);
    } else if (type == 'fire') {
      _fire(playerId, action);
    } else {
      throw const GameActionException('The battle has started.');
    }
  }

  void _place(_Sea sea, Object? type, Json action) {
    if (type == 'fire') {
      throw const GameActionException('Wait until everyone is ready.');
    }
    if (type == 'unready') {
      sea.ready = false;
      return;
    }
    if (sea.ready) {
      throw const GameActionException('Your fleet is locked. Tap Unready.');
    }
    switch (type) {
      case 'shuffle':
        sea.fleet = randomFleet(_random);
      case 'move':
        sea.fleet = _moved(sea.fleet, action);
      case 'ready':
        sea.ready = true;
        if (_seas.values.every((s) => s.ready)) _phase = 'battle';
      default:
        throw const GameActionException('Unknown move.');
    }
  }

  List<Ship> _moved(List<Ship> fleet, Json action) {
    final shipId = action['ship'];
    final row = action['row'];
    final col = action['col'];
    final vertical = action['vertical'];
    final index = fleet.indexWhere((s) => s.type.name == shipId);
    if (index < 0 || row is! int || col is! int || vertical is! bool) {
      throw const GameActionException('Pick a ship and a square.');
    }
    final moved = fleet[index].movedTo(row: row, col: col, vertical: vertical);
    if (!moved.inBounds) {
      throw const GameActionException("The ship doesn't fit there.");
    }
    final others = [...fleet]..removeAt(index);
    if (others.any(moved.overlaps)) {
      throw const GameActionException('Ships can’t overlap.');
    }
    return [...others, moved]..sort((a, b) => a.type.index - b.type.index);
  }

  void _fire(String shooterId, Json action) {
    if (shooterId != _turnId) {
      throw const GameActionException("It's not your turn.");
    }
    final afloat = [
      for (final p in _players)
        if (p.id != shooterId && !_seas[p.id]!.defeated) p.id,
    ];
    final targetId =
        action['target'] ?? (afloat.length == 1 ? afloat.single : null);
    if (targetId is! String || !afloat.contains(targetId)) {
      throw const GameActionException('Pick a fleet to fire at.');
    }
    final cell = action['cell'];
    if (cell is! int || cell < 0 || cell >= kSeaSize * kSeaSize) {
      throw const GameActionException('Pick a square on the board.');
    }
    final target = _seas[targetId]!;
    if (target.shots.containsKey(cell)) {
      throw const GameActionException('You already fired there.');
    }

    final ship = target.fleet.where((s) => s.cells.contains(cell)).firstOrNull;
    target.shots[cell] = ship?.type;
    final sunk = ship != null && target.isSunk(ship);
    _log.add({
      'n': _log.length + 1,
      'shooter': shooterId,
      'target': targetId,
      'cell': cell,
      'result': ship == null ? 'miss' : (sunk ? 'sunk' : 'hit'),
      if (ship != null) 'ship': ship.type.label,
    });

    final standing = [
      for (final p in _players)
        if (!_seas[p.id]!.defeated) p.id,
    ];
    if (standing.length == 1) {
      _winnerId = standing.single;
      _phase = 'over';
      return;
    }
    if (ship != null && shootAgain) return;
    do {
      _turn = (_turn + 1) % _players.length;
    } while (_seas[_turnId]!.defeated);
  }

  /// Public state only: shots, sunk ships, who is ready. Ships that are
  /// still afloat never appear here.
  @override
  Json tableView() => {
    'phase': _phase,
    'order': [for (final p in _players) p.id],
    'ready': {for (final p in _players) p.id: _seas[p.id]!.ready},
    'boards': {for (final p in _players) p.id: _boardView(_seas[p.id]!)},
    'turn': _phase == 'battle' ? _turnId : null,
    'winner': _winnerId,
    'shootAgain': shootAgain,
    'log': _log.length > 5 ? _log.sublist(_log.length - 5) : List.of(_log),
  };

  Json _boardView(_Sea sea) => {
    'hits': [
      for (final MapEntry(:key, :value) in sea.shots.entries)
        if (value != null) key,
    ],
    'misses': [
      for (final MapEntry(:key, :value) in sea.shots.entries)
        if (value == null) key,
    ],
    'sunk': [
      for (final ship in sea.fleet)
        if (sea.isSunk(ship)) ship.toJson(),
    ],
    'afloat': [
      for (final ship in sea.fleet)
        if (!sea.isSunk(ship)) ship.type.label,
    ],
  };

  /// The table plus this player's own fleet.
  @override
  Json viewFor(String playerId) => {
    ...tableView(),
    'fleet': [
      for (final ship in _seas[playerId]?.fleet ?? const <Ship>[])
        ship.toJson(),
    ],
  };

  @override
  Json? get result {
    final winnerId = _winnerId;
    if (winnerId == null) return null;
    final name = _players.firstWhere((p) => p.id == winnerId).nickname;
    return {
      'winnerIds': [winnerId],
      'summary': '$name sank the whole fleet!',
    };
  }
}
