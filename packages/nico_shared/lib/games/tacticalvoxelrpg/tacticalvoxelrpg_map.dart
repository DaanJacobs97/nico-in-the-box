import 'dart:collection';
import 'dart:math';

import '../../net/protocol.dart';

const int tacticalMapWidth = 40;
const int tacticalMapHeight = 30;
const int tacticalSoloMapWidth = 15;
const int tacticalSoloMapHeight = 15;

class GridPoint {
  const GridPoint(this.x, this.y);

  final int x;
  final int y;

  factory GridPoint.fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['x'] is! int ||
        value['y'] is! int) {
      throw const FormatException('Route coordinates must be integer tiles.');
    }
    return GridPoint(value['x']! as int, value['y']! as int);
  }

  Json toJson() => {'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      other is GridPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

class VoxelTile {
  const VoxelTile({
    required this.x,
    required this.y,
    required this.terrain,
    this.biome = 'grassland',
    this.elevation = 0,
  });

  final int x;
  final int y;
  final String terrain;
  final String biome;
  final int elevation;

  bool get passable => terrain != 'cliff' && terrain != 'wall';

  Json toJson() => {
    'x': x,
    'y': y,
    'terrain': terrain,
    'biome': biome,
    'elevation': elevation,
    'passable': passable,
  };
}

class _BiomeAnchor {
  const _BiomeAnchor(this.x, this.y, this.biome);

  final int x;
  final int y;
  final String biome;
}

class _CellData {
  _CellData({
    required this.terrain,
    required this.biome,
    required this.elevation,
  });

  String terrain;
  String biome;
  int elevation;
}

/// A seeded tactical map with biome regions, a connected river, cliffs,
/// roads and protected spawn clearings.
class TacticalMap {
  TacticalMap._({
    required this.seed,
    required this.width,
    required this.height,
    required this.tiles,
    required this.spawnTeams,
  });

  factory TacticalMap.generate(Random random, {bool solo = false}) {
    final width = solo ? tacticalSoloMapWidth : tacticalMapWidth;
    final height = solo ? tacticalSoloMapHeight : tacticalMapHeight;
    final seed = random.nextInt(0x7fffffff);
    final rng = Random(seed);
    final anchors = solo
        ? [
            _BiomeAnchor(3 + rng.nextInt(2), 3 + rng.nextInt(2), 'grassland'),
            _BiomeAnchor(11 + rng.nextInt(2), 3 + rng.nextInt(2), 'forest'),
            _BiomeAnchor(3 + rng.nextInt(2), 11 + rng.nextInt(2), 'highland'),
            _BiomeAnchor(11 + rng.nextInt(2), 11 + rng.nextInt(2), 'wetland'),
          ]
        : _biomeAnchors(rng);
    final cells = List<_CellData>.generate(
      width * height,
      (_) => _CellData(terrain: 'grass', biome: 'grassland', elevation: 0),
    );

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final scores = <({double score, String biome})>[];
        for (var i = 0; i < anchors.length; i++) {
          final anchor = anchors[i];
          final warpX =
              (_valueNoise(x * 0.045, y * 0.045, seed + i * 173) - 0.5) * 8;
          final warpY =
              (_valueNoise(x * 0.045, y * 0.045, seed + i * 317) - 0.5) * 8;
          final dx = x + warpX - anchor.x;
          final dy = y + warpY - anchor.y;
          scores.add((score: dx * dx + dy * dy, biome: anchor.biome));
        }
        scores.sort((a, b) => a.score.compareTo(b.score));
        final primary = scores.first;
        final secondary = scores[1];
        final broadNoise = _valueNoise(x * 0.05, y * 0.05, seed + 997);
        final detailNoise = _valueNoise(x * 0.14, y * 0.14, seed + 1999);
        final ecotone = secondary.score - primary.score < 70;
        final biome = ecotone ? 'ecotone' : primary.biome;
        final elevation =
            (broadNoise * 3 +
                    detailNoise +
                    switch (primary.biome) {
                      'highland' => 2.0,
                      'wetland' => -1.0,
                      _ => 0.0,
                    })
                .round()
                .clamp(0, 6)
                .toInt();
        final terrain = _surfaceFor(
          primary.biome,
          elevation,
          detailNoise,
          ecotone,
        );
        cells[_index(x, y, width)] = _CellData(
          terrain: terrain,
          biome: biome,
          elevation: elevation,
        );
      }
    }

    _markCliffs(cells, width, height);
    _carveRiver(cells, seed, width, height);

    final spawnCenters = solo
        ? const [GridPoint(3, 3), GridPoint(11, 11)]
        : const [
            GridPoint(3, 3),
            GridPoint(20, 3),
            GridPoint(36, 3),
            GridPoint(3, 26),
            GridPoint(20, 26),
            GridPoint(36, 26),
          ];
    final spawnTeams = [
      for (final center in spawnCenters)
        center.x < width ~/ 2
            ? [
                center,
                GridPoint(center.x + 2, center.y),
                GridPoint(center.x, center.y + 2),
              ]
            : [
                center,
                GridPoint(center.x - 2, center.y),
                GridPoint(center.x, center.y - 2),
              ],
    ];
    _clearSpawns(cells, spawnCenters, width, height);
    _carveRoads(cells, spawnCenters, seed, width, height);

    return TacticalMap._(
      seed: seed,
      width: width,
      height: height,
      tiles: [
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++)
            VoxelTile(
              x: x,
              y: y,
              terrain: cells[_index(x, y, width)].terrain,
              biome: cells[_index(x, y, width)].biome,
              elevation: cells[_index(x, y, width)].elevation,
            ),
      ],
      spawnTeams: spawnTeams,
    );
  }

  factory TacticalMap.custom(
    List<VoxelTile> tiles, {
    int width = tacticalMapWidth,
    int height = tacticalMapHeight,
  }) => TacticalMap._(
    seed: 0,
    width: width,
    height: height,
    tiles: List.of(tiles),
    spawnTeams: const [],
  );

  final int seed;
  final int width;
  final int height;
  final List<VoxelTile> tiles;
  final List<List<GridPoint>> spawnTeams;

  static int _index(int x, int y, int width) => y * width + x;

  static List<_BiomeAnchor> _biomeAnchors(Random random) => [
    _BiomeAnchor(7 + random.nextInt(5), 7 + random.nextInt(4), 'grassland'),
    _BiomeAnchor(18 + random.nextInt(5), 6 + random.nextInt(5), 'forest'),
    _BiomeAnchor(31 + random.nextInt(4), 7 + random.nextInt(5), 'highland'),
    _BiomeAnchor(7 + random.nextInt(5), 21 + random.nextInt(4), 'forest'),
    _BiomeAnchor(19 + random.nextInt(5), 20 + random.nextInt(5), 'grassland'),
    _BiomeAnchor(31 + random.nextInt(4), 21 + random.nextInt(5), 'wetland'),
  ];

  static String _surfaceFor(
    String biome,
    int elevation,
    double detailNoise,
    bool ecotone,
  ) {
    if (ecotone) return 'brush';
    return switch (biome) {
      'forest' => detailNoise > 0.34 ? 'forest' : 'grass',
      'highland' => elevation >= 4 ? 'rock' : 'grass',
      'wetland' => 'marsh',
      _ => detailNoise > 0.65 ? 'deepGrass' : 'grass',
    };
  }

  static void _markCliffs(List<_CellData> cells, int width, int height) {
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final cell = cells[_index(x, y, width)];
        if (cell.biome != 'highland' || cell.elevation < 4) continue;
        final adjacentHeights = [
          cells[_index(x - 1, y, width)].elevation,
          cells[_index(x + 1, y, width)].elevation,
          cells[_index(x, y - 1, width)].elevation,
          cells[_index(x, y + 1, width)].elevation,
        ];
        if (adjacentHeights.any((height) => cell.elevation - height >= 1)) {
          cell.terrain = 'cliff';
        }
      }
    }
  }

  static double _riverX(int y, int seed, int width, int height) {
    final t = y / (height - 1);
    final drift =
        sin(t * pi * 2) * width * 0.175 +
        sin(t * pi * 4 + 0.7) * width * 0.0625;
    final noise = (_valueNoise(0, y * 0.09, seed + 5003) - 0.5) * width * 0.1;
    return width * 0.18 + width * 0.64 * t + drift + noise;
  }

  static void _carveRiver(
    List<_CellData> cells,
    int seed,
    int width,
    int height,
  ) {
    for (var y = 2; y < height - 2; y++) {
      final center = _riverX(
        y,
        seed,
        width,
        height,
      ).round().clamp(2, width - 3);
      final riverWidth = _valueNoise(0, y * 0.13, seed + 7001) > 0.68 ? 2 : 1;
      for (var x = center - riverWidth; x <= center + riverWidth; x++) {
        final cell = cells[_index(x, y, width)];
        cell.biome = 'river';
        cell.terrain = x == center ? 'water' : 'bank';
        cell.elevation = min(cell.elevation, 1);
      }
    }
    for (final y in [(height * 0.3).round(), (height * 0.7).round()]) {
      final center = _riverX(
        y,
        seed,
        width,
        height,
      ).round().clamp(2, width - 3);
      for (var x = center - 2; x <= center + 2; x++) {
        final cell = cells[_index(x, y, width)];
        cell.biome = 'river';
        cell.terrain = 'bridge';
      }
    }
  }

  static void _clearSpawns(
    List<_CellData> cells,
    List<GridPoint> centers,
    int width,
    int height,
  ) {
    for (final center in centers) {
      for (
        var y = max(0, center.y - 3);
        y <= min(height - 1, center.y + 3);
        y++
      ) {
        for (
          var x = max(0, center.x - 3);
          x <= min(width - 1, center.x + 3);
          x++
        ) {
          final cell = cells[_index(x, y, width)];
          if (cell.terrain == 'water' || cell.terrain == 'cliff') {
            cell.terrain = 'grass';
          }
          cell.elevation = 1;
        }
      }
    }
  }

  static void _carveRoads(
    List<_CellData> cells,
    List<GridPoint> centers,
    int seed,
    int width,
    int height,
  ) {
    final roadY = <int>[];
    for (var x = 0; x < width; x++) {
      roadY.add(
        (height / 2 +
                sin(x * 0.1) * 3 +
                (_valueNoise(x * 0.08, 1, seed + 9001) - 0.5) * 3)
            .round()
            .clamp(2, height - 3),
      );
    }
    for (var x = 0; x < width; x++) {
      _roadCell(cells, GridPoint(x, roadY[x]), width);
    }
    for (final center in centers) {
      final target = GridPoint(center.x, roadY[center.x]);
      _carveBend(cells, center, GridPoint(center.x, target.y), width);
    }
  }

  static void _carveBend(
    List<_CellData> cells,
    GridPoint from,
    GridPoint to,
    int width,
  ) {
    var point = from;
    _roadCell(cells, point, width);
    while (point.y != to.y) {
      point = GridPoint(point.x, point.y + (to.y > point.y ? 1 : -1));
      _roadCell(cells, point, width);
    }
    while (point.x != to.x) {
      point = GridPoint(point.x + (to.x > point.x ? 1 : -1), point.y);
      _roadCell(cells, point, width);
    }
  }

  static void _roadCell(List<_CellData> cells, GridPoint point, int width) {
    final cell = cells[_index(point.x, point.y, width)];
    if (cell.terrain == 'water' || cell.terrain == 'cliff') {
      cell.terrain = 'bridge';
      cell.biome = 'river';
    } else {
      cell.terrain = 'path';
    }
  }

  static double _valueNoise(double x, double y, int seed) {
    final x0 = x.floor();
    final y0 = y.floor();
    final tx = _smooth(x - x0);
    final ty = _smooth(y - y0);
    final a = _hashNoise(x0, y0, seed);
    final b = _hashNoise(x0 + 1, y0, seed);
    final c = _hashNoise(x0, y0 + 1, seed);
    final d = _hashNoise(x0 + 1, y0 + 1, seed);
    final top = a + (b - a) * tx;
    final bottom = c + (d - c) * tx;
    return top + (bottom - top) * ty;
  }

  static double _smooth(double value) => value * value * (3 - 2 * value);

  static double _hashNoise(int x, int y, int seed) {
    var value =
        _mul32(x, 73856093) ^ _mul32(y, 19349663) ^ _mul32(seed, 83492791);
    value = _mul32(value ^ (value >>> 13), 1274126177);
    return (value & 0x7fffffff) / 0x7fffffff;
  }

  /// `(a * b) mod 2^32`, the same on every platform. A plain `a * b` would
  /// overflow 64 bits natively but lose precision in browsers (where ints are
  /// doubles), so browser screens would generate a different map.
  static int _mul32(int a, int b) {
    final low = (a & 0xffff) * b;
    final high = (((a >>> 16) & 0xffff) * b) & 0xffff;
    return (low + (high << 16)) & 0xffffffff;
  }

  bool inBounds(GridPoint point) =>
      point.x >= 0 && point.x < width && point.y >= 0 && point.y < height;

  VoxelTile tileAt(GridPoint point) => tiles[point.y * width + point.x];

  Iterable<GridPoint> neighbors(GridPoint point) sync* {
    for (final (dx, dy) in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
      final next = GridPoint(point.x + dx, point.y + dy);
      if (inBounds(next)) yield next;
    }
  }

  List<GridPoint>? findPath(
    GridPoint start,
    GridPoint target, {
    required bool Function(GridPoint) blocked,
    int Function(GridPoint) movementCost = _defaultMovementCost,
    int? maxCost,
  }) {
    final costs = <GridPoint, int>{start: 0};
    final previous = <GridPoint, GridPoint>{};
    final open = SplayTreeSet<({GridPoint point, int cost})>((a, b) {
      final byCost = a.cost.compareTo(b.cost);
      if (byCost != 0) return byCost;
      final byY = a.point.y.compareTo(b.point.y);
      return byY != 0 ? byY : a.point.x.compareTo(b.point.x);
    })..add((point: start, cost: 0));
    while (open.isNotEmpty) {
      final currentEntry = open.first;
      open.remove(currentEntry);
      final current = currentEntry.point;
      if (currentEntry.cost != costs[current]) continue;
      if (current == target) break;
      if (maxCost != null && currentEntry.cost >= maxCost) continue;
      for (final next in neighbors(current)) {
        if (!tileAt(next).passable || (next != target && blocked(next))) {
          continue;
        }
        final nextCost = currentEntry.cost + movementCost(next);
        if (maxCost != null && nextCost > maxCost) continue;
        if (nextCost >= (costs[next] ?? 0x7fffffff)) continue;
        costs[next] = nextCost;
        previous[next] = current;
        open.add((point: next, cost: nextCost));
      }
    }
    if (!costs.containsKey(target)) return null;
    final route = <GridPoint>[];
    var point = target;
    while (point != start) {
      route.add(point);
      point = previous[point]!;
    }
    return route.reversed.toList();
  }

  static int _defaultMovementCost(GridPoint _) => 1000;

  int routeCost(
    Iterable<GridPoint> route, {
    int Function(GridPoint)? movementCost,
  }) => route.fold(
    0,
    (cost, point) => cost + (movementCost?.call(point) ?? 1000),
  );
}
