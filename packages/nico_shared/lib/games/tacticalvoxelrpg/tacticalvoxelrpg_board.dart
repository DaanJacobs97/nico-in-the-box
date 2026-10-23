part of 'tacticalvoxelrpg_view.dart';

class _TacticalBoard extends StatefulWidget {
  const _TacticalBoard({
    required this.tiles,
    required this.units,
    required this.traps,
    required this.reachable,
    required this.route,
    required this.lastAction,
    required this.recentActions,
    required this.attackTargets,
    required this.trapTargets,
    required this.tileSize,
    required this.mapWidth,
    required this.mapHeight,
  });

  final List<Map<String, Object?>> tiles;
  final List<Map<String, Object?>> units;
  final List<Map<String, Object?>> traps;
  final List<GridPoint> reachable;
  final List<GridPoint> route;
  final Object? lastAction;
  final List<Map<String, Object?>> recentActions;
  final Set<String> attackTargets;
  final Set<GridPoint> trapTargets;
  final double tileSize;
  final int mapWidth;
  final int mapHeight;

  @override
  State<_TacticalBoard> createState() => _TacticalBoardState();
}

class _TacticalBoardState extends State<_TacticalBoard> {
  String? _movingUnitId;
  Offset? _movingPosition;
  final List<Map<String, Object?>> _movementQueue = [];
  final Map<String, Offset> _queuedStarts = {};
  int _lastSeenEvent = 0;
  bool _movementActive = false;

  double get _tilePitch => widget.tileSize + 1 / widget.mapWidth;
  double get _tileExtent => _tilePitch - 1;

  double _spriteLeft(double x) =>
      x * _tilePitch + _tileExtent / 2 - widget.tileSize * 0.9;

  double _spriteTop(double y) =>
      y * _tilePitch + _tileExtent - widget.tileSize * 1.8 * (120 / 128);

  @override
  void initState() {
    super.initState();
    _lastSeenEvent = widget.recentActions.fold<int>(
      0,
      (latest, action) => max(latest, action['event'] as int? ?? 0),
    );
  }

  @override
  void didUpdateWidget(covariant _TacticalBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _queueNewMovementEvents();
  }

  void _queueNewMovementEvents() {
    final unseen =
        widget.recentActions
            .where((action) => (action['event'] as int? ?? 0) > _lastSeenEvent)
            .toList()
          ..sort((a, b) => (a['event'] as int).compareTo(b['event'] as int));
    if (unseen.isEmpty) return;
    _lastSeenEvent = unseen.last['event'] as int;
    _movementQueue.addAll(unseen.where((action) => action['type'] == 'move'));
    _refreshQueuedStarts();
    if (!_movementActive) _startNextMovement(updateState: false);
  }

  void _refreshQueuedStarts() {
    _queuedStarts.clear();
    for (final action in _movementQueue) {
      final unitId = action['unit'];
      final from = action['from'];
      if (unitId is! String || from is! Map<Object?, Object?>) continue;
      final point = GridPoint.fromJson(from);
      _queuedStarts.putIfAbsent(
        unitId,
        () => Offset(point.x.toDouble(), point.y.toDouble()),
      );
    }
  }

  void _startNextMovement({bool updateState = true}) {
    if (_movementQueue.isEmpty) {
      _movementActive = false;
      _movingUnitId = null;
      _movingPosition = null;
      _refreshQueuedStarts();
      return;
    }
    final action = _movementQueue.removeAt(0);
    _refreshQueuedStarts();
    final unitId = action['unit'];
    final pathData = action['path'];
    if (unitId is! String || pathData is! List<Object?> || pathData.isEmpty) {
      _startNextMovement(updateState: updateState);
      return;
    }
    try {
      final start = GridPoint.fromJson(action['from']);
      final path = [for (final point in pathData) GridPoint.fromJson(point)];
      void setMovementState() {
        _movingUnitId = unitId;
        _movingPosition = Offset(start.x.toDouble(), start.y.toDouble());
        _movementActive = true;
      }

      if (updateState) {
        setState(setMovementState);
      } else {
        setMovementState();
      }
      unawaited(_animateMovement(path));
    } on FormatException {
      _startNextMovement(updateState: updateState);
    }
  }

  Future<void> _animateMovement(List<GridPoint> path) async {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    for (final point in path) {
      if (!mounted) return;
      setState(() {
        _movingPosition = Offset(point.x.toDouble(), point.y.toDouble());
      });
      await Future<void>.delayed(const Duration(milliseconds: 240));
    }
    if (!mounted) return;
    _startNextMovement();
    if (!_movementActive) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: widget.tileSize * widget.mapWidth,
      height: widget.tileSize * widget.mapHeight,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.mapWidth,
              mainAxisSpacing: 1,
              crossAxisSpacing: 1,
            ),
            itemCount: widget.mapWidth * widget.mapHeight,
            itemBuilder: (context, index) {
              final x = index % widget.mapWidth;
              final y = index ~/ widget.mapWidth;
              final point = GridPoint(x, y);
              final tile = widget.tiles[index];
              final unit = _unitAtUnits(widget.units, point);
              final trap = widget.traps.any(
                (entry) => entry['x'] == x && entry['y'] == y,
              );
              return _VoxelCell(
                key: ValueKey('tacticalvoxelrpg-cell-$x-$y'),
                terrain: tile['terrain'] as String,
                unit: unit,
                showUnit:
                    unit?['sprite'] is! String &&
                    _characterPortraitFor(unit) == null &&
                    unit?['id'] != _movingUnitId &&
                    !_queuedStarts.containsKey(unit?['id']),
                trap: trap,
                reachable: widget.reachable.contains(point),
                route: widget.route.contains(point),
                attackTarget:
                    unit != null &&
                    widget.attackTargets.contains(unit['id'] as String),
                trapTarget: widget.trapTargets.contains(point),
                damage: _lastDamageForCell(point, widget.lastAction),
                damageEvent: _lastEvent(widget.lastAction),
                unitAnimation: _slimeAnimationFor(unit, widget.lastAction),
                tileSize: widget.tileSize,
              );
            },
          ),
          for (final unit in widget.units.where(
            (unit) =>
                _characterPortraitFor(unit) != null ||
                unit['sprite'] is String ||
                unit['id'] == _movingUnitId ||
                _queuedStarts.containsKey(unit['id']),
          ))
            _unitOverlay(unit),
        ],
      ),
    ),
  );

  Widget _unitOverlay(Map<String, Object?> unit) {
    final moving = unit['id'] == _movingUnitId && _movingPosition != null;
    final position = moving
        ? _movingPosition!
        : _queuedStarts[unit['id']] ??
              Offset(
                (unit['x']! as int).toDouble(),
                (unit['y']! as int).toDouble(),
              );
    final portrait = _characterPortraitFor(unit);
    final slime = unit['sprite'] is String;
    final size = portrait != null
        ? widget.tileSize * 2.0
        : slime
        ? widget.tileSize * 1.8
        : _tileExtent;
    final height = portrait != null ? widget.tileSize * 2.65 : size;
    final left = portrait != null
        ? position.dx * _tilePitch + _tileExtent / 2 - size / 2
        : slime
        ? _spriteLeft(position.dx)
        : position.dx * _tilePitch;
    final top = portrait != null
        ? position.dy * _tilePitch + _tileExtent - height
        : slime
        ? _spriteTop(position.dy)
        : position.dy * _tilePitch;
    final contents = portrait != null
        ? _TacticalCharacterArt(
            asset: portrait,
            animation: _characterAnimationFor(
              unit,
              widget.lastAction,
              moving: moving,
            ),
            event: _lastEvent(widget.lastAction) ?? 0,
            width: size,
            height: height,
            attackDirection: _attackDirectionFor(unit),
          )
        : slime
        ? _TacticalSlimeSprite(
            sprite: unit['sprite']! as String,
            animation: moving
                ? 'walk'
                : _slimeAnimationFor(unit, widget.lastAction),
            event: _lastEvent(widget.lastAction) ?? 0,
            repeat: moving,
            size: size,
          )
        : _TacticalUnitMarker(unit: unit, size: size);
    return AnimatedPositioned(
      key: ValueKey('tacticalvoxelrpg-sprite-${unit['id']}'),
      duration: const Duration(milliseconds: 240),
      curve: Curves.linear,
      left: left,
      top: top,
      width: size,
      height: height,
      child: IgnorePointer(child: contents),
    );
  }

  double _attackDirectionFor(Map<String, Object?> unit) {
    final action = widget.lastAction;
    if (action is! Map<Object?, Object?> ||
        action['type'] != 'attack' ||
        action['unit'] != unit['id']) {
      return 1;
    }
    final targetX =
        action['x'] as int? ??
        widget.units
                .where((entry) => entry['id'] == action['target'])
                .firstOrNull?['x']
            as int?;
    if (targetX == null) return 1;
    return targetX >= (unit['x']! as int) ? 1 : -1;
  }
}
