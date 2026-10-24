part of 'tacticalvoxelrpg_view.dart';

extension _TacticalInteraction on _TacticalVoxelRPGViewState {
  GridPoint? _mapPointAt(
    Offset global,
    double tileSize,
    int mapWidth,
    int mapHeight,
  ) {
    final renderObject = _mapViewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return null;
    final local = renderObject.globalToLocal(global);
    final scene = _mapTransform.toScene(local);
    final pitch = tileSize + 1 / mapWidth;
    final mapLeft = (renderObject.size.width - tileSize * mapWidth) / 2;
    final mapTop = (renderObject.size.height - tileSize * mapHeight) / 2;
    final x = ((scene.dx - mapLeft) / pitch).floor();
    final y = ((scene.dy - mapTop) / pitch).floor();
    if (x < 0 || x >= mapWidth || y < 0 || y >= mapHeight) return null;
    return GridPoint(x, y);
  }

  Map<String, Object?>? _unitAtMapPoint(
    List<Map<String, Object?>> units,
    GridPoint point,
  ) {
    final tileUnit = _unitAtUnits(units, point);
    if (tileUnit != null) return tileUnit;
    Map<String, Object?>? nearest;
    var nearestDistance = double.infinity;
    for (final unit in units) {
      if (_characterPortraitFor(unit) == null) continue;
      final x = unit['x']! as int;
      final y = unit['y']! as int;
      final verticalOffset = y - point.y;
      final horizontalOffset = (x - point.x).abs();
      if (verticalOffset < 0 || verticalOffset > 2 || horizontalOffset > 1) {
        continue;
      }
      final distance = verticalOffset + horizontalOffset * 1.5;
      if (distance < nearestDistance) {
        nearest = unit;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  void _selectCard(Json card) {
    final view = widget.ctx.view;
    final active = _activeUnit(_objects(view['units']), view);
    if (active == null) return;
    if (view['canAct'] != true ||
        (active['energy'] as int) < (card['cost'] as int) ||
        card['kind'] == 'skill' && (active['mana'] as int) < 1) {
      return;
    }
    final kind = card['kind'];
    if (kind == 'overwatch') {
      _useCard(active, card);
      return;
    }
    _updateState(() {
      _selectedCardId = card['id'] as int;
      _draftRoute.clear();
      _drawingRoute = false;
      _mode = switch (kind) {
        'move' => 'route',
        'attack' => 'attack',
        'skill' => 'skill',
        'trap' => 'trap',
        _ => null,
      };
    });
  }

  void _useCard(
    Map<String, Object?> active,
    Json card, {
    List<GridPoint>? path,
    String? target,
    GridPoint? point,
  }) {
    final action = <String, Object?>{
      'type': 'playCard',
      'unit': active['id'],
      'cardId': card['id'],
      if (path != null) 'path': [for (final step in path) step.toJson()],
      'target': ?target,
      'x': ?point?.x,
      'y': ?point?.y,
    };
    widget.ctx.sendAction(action);
    _updateState(() {
      _selectedCardId = null;
      _mode = null;
      _draftRoute.clear();
      _drawingRoute = false;
    });
  }

  void _finishActive(Map<String, Object?> active) {
    widget.ctx.sendAction({'type': 'finishUnit', 'unit': active['id']});
    _updateState(() {
      _selectedCardId = null;
      _mode = null;
      _draftRoute.clear();
    });
  }

  void _retainCard(int cardId) {
    final view = widget.ctx.view;
    final active = _activeUnit(_objects(view['units']), view);
    if (active == null) return;
    widget.ctx.sendAction({
      'type': 'retainCard',
      'unit': active['id'],
      'cardId': cardId,
    });
    _updateState(() {
      _selectedCardId = null;
      _mode = null;
      _draftRoute.clear();
    });
  }

  void _pointerDown(GridPoint? point) {
    _drawingRoute = false;
    final view = widget.ctx.view;
    final active = _activeUnit(_objects(view['units']), view);
    if (view['canAct'] != true || _mode != 'route' || active == null) return;
    if (point != null && _draftRoute.lastOrNull == point) return;
    if (point != null) {
      final origin = GridPoint(active['x']! as int, active['y']! as int);
      if ((point.x - origin.x).abs() <= 1 &&
          point.y >= origin.y - 2 &&
          point.y <= origin.y + 1) {
        _draftRoute.clear();
        _drawingRoute = true;
      }
    }
  }

  void _pointerMove(GridPoint? point) {
    if (!_drawingRoute || point == null) return;
    final currentView = widget.ctx.view;
    final activeUnit = _activeUnit(_objects(currentView['units']), currentView);
    if (activeUnit != null &&
        point == GridPoint(activeUnit['x']! as int, activeUnit['y']! as int)) {
      if (_draftRoute.isNotEmpty) {
        _updateState(_draftRoute.clear);
      }
      return;
    }
    final routeIndex = _draftRoute.indexOf(point);
    if (routeIndex >= 0) {
      if (routeIndex < _draftRoute.length - 1) {
        _updateState(
          () => _draftRoute.removeRange(routeIndex + 1, _draftRoute.length),
        );
      }
      return;
    }
    final view = widget.ctx.view;
    final units = _objects(view['units']);
    final active = _activeUnit(units, view);
    if (active == null) return;
    final mapWidth = view['width'] as int? ?? tacticalMapWidth;
    final origin = GridPoint(active['x']! as int, active['y']! as int);
    final tiles = _objects(view['tiles']);
    final movement = active['movement'] as int;
    final profile = active['terrainMovementCosts'];
    int costOf(Map<String, Object?> routeTile) {
      if (profile is Map<Object?, Object?>) {
        final cost = profile[routeTile['terrain']];
        if (cost is num) return cost.toInt();
      }
      return tacticalMovementScale;
    }

    var routeCost = _draftRoute.fold<int>(
      0,
      (total, step) => total + costOf(tiles[step.y * mapWidth + step.x]),
    );
    var previous = _draftRoute.isEmpty ? origin : _draftRoute.last;
    final additions = <GridPoint>[];
    while (previous != point) {
      final next = _stepToward(previous, point);
      if (next == null ||
          next.x < 0 ||
          next.x >= mapWidth ||
          next.y < 0 ||
          next.y >= (view['height'] as int? ?? tacticalMapHeight)) {
        break;
      }
      final tile = tiles[next.y * mapWidth + next.x];
      if (tile['passable'] != true ||
          _unitAtUnits(units, next) != null ||
          routeCost + costOf(tile) > movement * tacticalMovementScale) {
        break;
      }
      routeCost += costOf(tile);
      additions.add(next);
      previous = next;
    }
    if (additions.isNotEmpty) {
      _updateState(() => _draftRoute.addAll(additions));
    }
  }

  void _pointerUp(GridPoint? point, Map<String, Object?>? unit) {
    final view = widget.ctx.view;
    final units = _objects(view['units']);
    final active = _activeUnit(units, view);
    if (view['canAct'] != true) return;
    if (_mode == 'pan') return;
    if (_drawingRoute && _draftRoute.isNotEmpty) {
      _updateState(() => _drawingRoute = false);
      return;
    }
    final routeDestination =
        _mode == 'route' &&
        point != null &&
        _unitAtUnits(units, point) == null &&
        (_draftRoute.lastOrNull == point ||
            _points(view['reachable']).contains(point));
    if (unit != null && unit['owner'] == widget.ctx.myId && !routeDestination) {
      _updateState(() {
        _selectedCardId = null;
        _mode = null;
        _drawingRoute = false;
        _draftRoute.clear();
      });
      if (active == null && unit['completed'] != true) {
        widget.ctx.sendAction({'type': 'selectUnit', 'unit': unit['id']});
      }
      return;
    }
    if (_mode == 'route' && point != null && active != null) {
      final selectedRoute = _draftRoute;
      if (selectedRoute.isNotEmpty && selectedRoute.last == point) {
        final card = _objects(active['hand'])
            .where((entry) => entry['id'] == _selectedCardId)
            .firstOrNull;
        if (card != null) _useCard(active, card, path: selectedRoute);
        return;
      }
      final path = _routeToTile(
        GridPoint(active['x']! as int, active['y']! as int),
        point,
        active,
        units,
        _objects(view['tiles']),
        view['width'] as int? ?? tacticalMapWidth,
        view['height'] as int? ?? tacticalMapHeight,
      );
      if (path != null && path.isNotEmpty) {
        _updateState(() {
          _drawingRoute = false;
          _draftRoute
            ..clear()
            ..addAll(path);
        });
      }
      return;
    }
    if (active != null && _selectedCardId != null) {
      final card = _objects(active['hand'])
          .where((entry) => entry['id'] == _selectedCardId)
          .firstOrNull;
      if (card != null) {
        if (_mode == 'attack' || _mode == 'skill') {
          if (unit != null && unit['owner'] != widget.ctx.myId) {
            _useCard(active, card, target: unit['id'] as String);
          }
          return;
        }
        if (_mode == 'trap') {
          if (point != null) _useCard(active, card, point: point);
          return;
        }
        if (_mode == 'route') return;
      }
    }
    _updateState(() {
      _mode = null;
      _drawingRoute = false;
    });
  }
}
