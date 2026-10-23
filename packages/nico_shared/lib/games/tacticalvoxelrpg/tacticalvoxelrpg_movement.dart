part of 'tacticalvoxelrpg_game.dart';

extension _TacticalVoxelRPGMovement on TacticalVoxelRPGSession {
  void _validateRoute(TacticalUnit unit, List<GridPoint> route) {
    var previous = unit.point;
    var cost = 0;
    final seen = <GridPoint>{};
    for (final point in route) {
      if (!_map.inBounds(point) || !_map.tileAt(point).passable) {
        throw const GameActionException('That route crosses a wall.');
      }
      if (_distance(previous, point) != 1) {
        throw const GameActionException('Route tiles must touch edge to edge.');
      }
      if (_unitAt(point) != null && point != unit.point) {
        throw const GameActionException(
          'That route is blocked by another unit.',
        );
      }
      if (!seen.add(point)) {
        throw const GameActionException(
          'A route cannot loop back over itself.',
        );
      }
      cost += unit.movementCostFor(_map.tileAt(point));
      if (cost > unit.kind.movement * tacticalMovementScale) {
        throw const GameActionException(
          'That route exceeds this unit’s movement range.',
        );
      }
      previous = point;
    }
  }

  void _runAiTurn() {
    final enemies = _units
        .where((unit) => unit.ownerId == tacticalAiId)
        .toList();
    for (final enemy in enemies) {
      if (isOver || !_units.contains(enemy)) break;
      final targets = _units.where((unit) => _isEnemy(enemy, unit)).toList();
      if (targets.isEmpty) break;
      targets.sort(
        (a, b) => _distance(
          enemy.point,
          a.point,
        ).compareTo(_distance(enemy.point, b.point)),
      );
      final target = targets.first;
      if (_inWeaponRange(enemy, target)) {
        _attackAi(enemy, target);
      } else {
        final route = _pathToAttackPosition(enemy, target);
        if (route != null && route.isNotEmpty) {
          final movement = _routePrefixWithinMovement(enemy, route);
          if (movement.isNotEmpty && enemy.energy > 0) {
            _moveAi(enemy, movement);
            if (_units.contains(enemy)) {
              final nearby = targets
                  .where((unit) => _units.contains(unit))
                  .where((unit) => _inWeaponRange(enemy, unit))
                  .firstOrNull;
              if (nearby != null && enemy.energy > 0) _attackAi(enemy, nearby);
            }
          }
        }
      }
      if (_units.contains(enemy)) enemy.completed = true;
    }
    _checkOutcome();
  }

  List<GridPoint> _routePrefixWithinMovement(
    TacticalUnit unit,
    List<GridPoint> route,
  ) {
    var cost = 0;
    final result = <GridPoint>[];
    for (final point in route) {
      final stepCost = unit.movementCostFor(_map.tileAt(point));
      if (cost + stepCost > unit.kind.movement * tacticalMovementScale) break;
      cost += stepCost;
      result.add(point);
    }
    return result;
  }

  List<GridPoint>? _pathToAttackPosition(
    TacticalUnit unit,
    TacticalUnit target,
  ) {
    List<GridPoint>? best;
    final minX = max(0, target.x - unit.kind.range);
    final maxX = min(tacticalMapWidth - 1, target.x + unit.kind.range);
    final minY = max(0, target.y - unit.kind.range);
    final maxY = min(tacticalMapHeight - 1, target.y + unit.kind.range);
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final point = GridPoint(x, y);
        final distance = _distance(point, target.point);
        if (distance < unit.kind.minimumRange || distance > unit.kind.range) {
          continue;
        }
        if (!_map.tileAt(point).passable || _unitAt(point) != null) continue;
        final route = _map.findPath(
          unit.point,
          point,
          blocked: (candidate) => _unitAt(candidate) != null,
          movementCost: (candidate) =>
              unit.movementCostFor(_map.tileAt(candidate)),
        );
        if (route != null &&
            (best == null ||
                _map.routeCost(
                      route,
                      movementCost: (candidate) =>
                          unit.movementCostFor(_map.tileAt(candidate)),
                    ) <
                    _map.routeCost(
                      best,
                      movementCost: (candidate) =>
                          unit.movementCostFor(_map.tileAt(candidate)),
                    ))) {
          best = route;
        }
      }
    }
    return best;
  }

  void _moveAi(TacticalUnit unit, List<GridPoint> route) {
    final from = unit.point;
    unit.energy--;
    _recordLastAction({
      'type': 'move',
      'unit': unit.id,
      'from': from.toJson(),
      'x': route.last.x,
      'y': route.last.y,
      'energy': unit.energy,
      'path': [for (final point in route) point.toJson()],
    });
    for (final point in route) {
      unit.x = point.x;
      unit.y = point.y;
      _triggerTrap(unit);
      if (_units.contains(unit)) _triggerOverwatch(unit);
      if (!_units.contains(unit)) break;
    }
  }
}
