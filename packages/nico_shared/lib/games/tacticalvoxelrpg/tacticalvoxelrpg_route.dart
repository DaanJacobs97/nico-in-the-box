part of 'tacticalvoxelrpg_view.dart';

extension _TacticalRoutePlanning on _TacticalVoxelRPGViewState {
  GridPoint? _stepToward(GridPoint from, GridPoint to) {
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    if (dx.abs() + dy.abs() <= 1) return to;
    if (dx != 0) return GridPoint(from.x + (dx > 0 ? 1 : -1), from.y);
    if (dy != 0) return GridPoint(from.x, from.y + (dy > 0 ? 1 : -1));
    return null;
  }

  List<GridPoint>? _routeToTile(
    GridPoint origin,
    GridPoint target,
    Map<String, Object?> active,
    List<Map<String, Object?>> units,
    List<Map<String, Object?>> tiles,
    int mapWidth,
    int mapHeight,
  ) {
    if (origin == target) return null;
    final profile = active['terrainMovementCosts'];
    int costOf(Map<String, Object?> tile) {
      if (profile is Map<Object?, Object?>) {
        final cost = profile[tile['terrain']];
        if (cost is num) return cost.toInt();
      }
      return tacticalMovementScale;
    }

    final path = <GridPoint>[];
    var current = origin;
    var routeCost = 0;
    while (current != target) {
      final next = _stepToward(current, target);
      if (next == null ||
          next.x < 0 ||
          next.x >= mapWidth ||
          next.y < 0 ||
          next.y >= mapHeight) {
        return null;
      }
      final tile = tiles[next.y * mapWidth + next.x];
      if (tile['passable'] != true || _unitAtUnits(units, next) != null) {
        return null;
      }
      routeCost += costOf(tile);
      if (routeCost > (active['movement'] as int) * tacticalMovementScale) {
        return null;
      }
      path.add(next);
      current = next;
    }
    return path;
  }
}
