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

    final budget = (active['movement'] as int) * tacticalMovementScale;
    final bestCost = <GridPoint, int>{origin: 0};
    final open = <({GridPoint point, int cost, List<GridPoint> path})>[
      (point: origin, cost: 0, path: const []),
    ];
    while (open.isNotEmpty) {
      open.sort((a, b) => a.cost.compareTo(b.cost));
      final current = open.removeAt(0);
      if (current.cost != bestCost[current.point]) continue;
      if (current.point == target) return current.path;
      for (final next in [
        GridPoint(current.point.x + 1, current.point.y),
        GridPoint(current.point.x - 1, current.point.y),
        GridPoint(current.point.x, current.point.y + 1),
        GridPoint(current.point.x, current.point.y - 1),
      ]) {
        if (next.x < 0 ||
            next.x >= mapWidth ||
            next.y < 0 ||
            next.y >= mapHeight ||
            _unitAtUnits(units, next) != null) {
          continue;
        }
        final tile = tiles[next.y * mapWidth + next.x];
        if (tile['passable'] != true) continue;
        final nextCost = current.cost + costOf(tile);
        if (nextCost > budget || nextCost >= (bestCost[next] ?? 0x7fffffff)) {
          continue;
        }
        bestCost[next] = nextCost;
        open.add((point: next, cost: nextCost, path: [...current.path, next]));
      }
    }
    return null;
  }
}
