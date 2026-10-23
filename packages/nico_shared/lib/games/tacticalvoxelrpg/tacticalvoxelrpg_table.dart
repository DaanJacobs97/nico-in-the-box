part of 'tacticalvoxelrpg_view.dart';

class TacticalVoxelRPGTable extends StatefulWidget {
  const TacticalVoxelRPGTable({super.key, required this.ctx});

  final TableContext ctx;

  @override
  State<TacticalVoxelRPGTable> createState() => _TacticalVoxelRPGTableState();
}

class _TacticalVoxelRPGTableState extends State<TacticalVoxelRPGTable> {
  final _camera = TransformationController();
  double _viewportWidth = 0;
  double _viewportHeight = 0;
  double _tileSize = 42;

  void _zoomBy(double factor) {
    final current = _camera.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.6, 1.8).toDouble();
    final adjustment = next / current;
    _camera.value = _camera.value.clone()
      ..scaleByDouble(adjustment, adjustment, 1, 1);
  }

  void _resetZoom() {
    _camera.value = vm.Matrix4.identity();
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TacticalVoxelRPGTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.ctx.table['lastAction'];
    final action = widget.ctx.table['lastAction'];
    if (action is Map<Object?, Object?> && action != previous) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _followAction(action),
      );
    }
  }

  void _followAction(Map<Object?, Object?> action) {
    final origin = action['type'] == 'move'
        ? action['from'] as Map<Object?, Object?>?
        : null;
    final x = origin?['x'] ?? action['x'];
    final y = origin?['y'] ?? action['y'];
    if (x is! int || y is! int || !mounted) return;
    final zoom = _camera.value.getMaxScaleOnAxis();
    _camera.value = vm.Matrix4.identity()
      ..translateByDouble(
        _viewportWidth / 2 - (x + 0.5) * _tileSize * zoom,
        _viewportHeight / 2 - (y + 0.5) * _tileSize * zoom,
        0,
        1,
      )
      ..scaleByDouble(zoom, zoom, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.ctx.table;
    final units = _objects(table['units']);
    final tiles = _objects(table['tiles']);
    final traps = _objects(table['traps']);
    final action = table['lastAction'];
    final damage = _lastDamage(action);
    final turn = table['turn'] as String?;
    final title = table['winner'] != null
        ? (table['winner'] == tacticalAiId ? 'AI victory' : 'Mission complete')
        : turn == null
        ? 'Battle'
        : '${widget.ctx.lobby.nicknameOf(turn)}’s turn';
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.biggest.shortestSide / 600).clamp(1.0, 1.8);
        _viewportWidth = constraints.maxWidth;
        _viewportHeight = constraints.maxHeight - 100 * scale;
        _tileSize = min(32, _viewportWidth / tacticalMapWidth);
        final width = _tileSize * tacticalMapWidth;
        final height = _tileSize * tacticalMapHeight;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.all(8 * scale),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 24 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 20 * scale),
                  Text(
                    'Round ${table['round']}',
                    style: TextStyle(fontSize: 16 * scale),
                  ),
                  if (damage != null) ...[
                    SizedBox(width: 18 * scale),
                    Text(
                      '−${damage['damage']} HP  ·  ${damage['targetHp']} remaining',
                      key: const ValueKey('tacticalvoxelrpg-damage-summary'),
                      style: TextStyle(
                        color: const Color(0xffff7168),
                        fontSize: 16 * scale,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      transformationController: _camera,
                      constrained: false,
                      minScale: 0.6,
                      maxScale: 1.8,
                      boundaryMargin: EdgeInsets.all(max(width, height) / 2),
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: _TacticalBoard(
                          tiles: tiles,
                          units: units,
                          traps: traps,
                          reachable: const [],
                          route: const [],
                          friendlyOwner: null,
                          lastAction: action,
                          recentActions: _objects(table['recentActions']),
                          attackMode: false,
                          tileSize: _tileSize,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 14 * scale,
                    bottom: 14 * scale,
                    child: _MapZoomControls(
                      keyPrefix: 'tacticalvoxelrpg-table',
                      onZoomIn: () => _zoomBy(1.2),
                      onZoomOut: () => _zoomBy(0.83),
                      onReset: _resetZoom,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(8 * scale),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 14 * scale,
                runSpacing: 4,
                children: [
                  for (final unit in units)
                    _UnitHealth(unit: unit, scale: scale),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UnitHealth extends StatelessWidget {
  const _UnitHealth({required this.unit, required this.scale});

  final Map<String, Object?> unit;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final ai = unit['owner'] == tacticalAiId;
    final health = (unit['hp'] as int) / (unit['maxHp'] as int);
    final color = ai ? const Color(0xffff7168) : const Color(0xffffd166);
    return SizedBox(
      width: 128 * scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${unit['name']}  ${unit['hp']} HP · ${unit['energy']} energy · Move ${unit['movement']}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12 * scale),
          ),
          LinearProgressIndicator(
            value: health,
            minHeight: 5 * scale,
            color: color,
            backgroundColor: Colors.white24,
          ),
        ],
      ),
    );
  }
}

List<Map<String, Object?>> _objects(Object? value) =>
    (value as List<Object?>? ?? const []).cast<Map<String, Object?>>();

List<GridPoint> _points(Object? value) => [
  for (final point in (value as List<Object?>? ?? const []))
    GridPoint.fromJson(point),
];

Map<String, Object?>? _activeUnit(List<Map<String, Object?>> units, Json view) {
  for (final unit in units) {
    if (unit['id'] == view['activeUnit']) return unit;
  }
  return null;
}

Map<String, Object?>? _unitAtUnits(
  List<Map<String, Object?>> units,
  GridPoint point,
) {
  for (final unit in units) {
    if (unit['x'] == point.x && unit['y'] == point.y) return unit;
  }
  return null;
}

int? _lastDamageForCell(GridPoint point, Object? action) {
  final hit = _lastDamage(action);
  return hit != null && hit['x'] == point.x && hit['y'] == point.y
      ? hit['damage'] as int
      : null;
}

int? _lastEvent(Object? action) =>
    action is Map<Object?, Object?> ? action['event'] as int? : null;

Json? _lastDamage(Object? action) =>
    action is Map<Object?, Object?> &&
        (action['type'] == 'attack' || action['type'] == 'trapHit') &&
        action['damage'] is int
    ? action.cast<String, Object?>()
    : null;
