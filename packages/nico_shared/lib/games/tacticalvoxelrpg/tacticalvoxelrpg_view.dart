import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../../net/protocol.dart';
import '../game_views.dart';
import 'tacticalvoxelrpg_game.dart';
import 'tacticalvoxelrpg_map.dart';

part 'tacticalvoxelrpg_sprite.dart';
part 'tacticalvoxelrpg_cell.dart';
part 'tacticalvoxelrpg_table.dart';
part 'tacticalvoxelrpg_board.dart';
part 'tacticalvoxelrpg_route.dart';

class TacticalVoxelRPGView extends StatefulWidget {
  const TacticalVoxelRPGView({super.key, required this.ctx});

  final GameViewContext ctx;

  @override
  State<TacticalVoxelRPGView> createState() => _TacticalVoxelRPGViewState();
}

class _TacticalVoxelRPGViewState extends State<TacticalVoxelRPGView> {
  final TransformationController _mapTransform = TransformationController();
  final GlobalKey _mapViewportKey = GlobalKey();
  String? _mode;
  bool _drawingRoute = false;
  int? _selectedCardId;
  final List<GridPoint> _draftRoute = [];

  @override
  void dispose() {
    _mapTransform.dispose();
    super.dispose();
  }

  void _zoomMap(double factor) {
    final current = _mapTransform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.7, 2.4).toDouble();
    final adjustment = next / current;
    _mapTransform.value = _mapTransform.value.clone()
      ..scaleByDouble(adjustment, adjustment, 1, 1);
  }

  void _resetMapZoom() {
    _mapTransform.value = vm.Matrix4.identity();
  }

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
    final x = (scene.dx / pitch).floor();
    final y = (scene.dy / pitch).floor();
    if (x < 0 || x >= mapWidth || y < 0 || y >= mapHeight) return null;
    return GridPoint(x, y);
  }

  void _selectCard(Json card) {
    final view = widget.ctx.view;
    final active = _activeUnit(_objects(view['units']), view);
    if (active == null) return;
    final kind = card['kind'];
    if (kind == 'overwatch') {
      _useCard(active, card);
      return;
    }
    setState(() {
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
    setState(() {
      _selectedCardId = null;
      _mode = null;
      _draftRoute.clear();
      _drawingRoute = false;
    });
  }

  void _finishActive(Map<String, Object?> active) {
    widget.ctx.sendAction({'type': 'finishUnit', 'unit': active['id']});
    setState(() {
      _selectedCardId = null;
      _mode = null;
      _draftRoute.clear();
    });
  }

  void _pointerDown(GridPoint? point) {
    _draftRoute.clear();
    _drawingRoute = false;
    final view = widget.ctx.view;
    final active = _activeUnit(_objects(view['units']), view);
    if (view['canAct'] == true &&
        _mode == 'route' &&
        active != null &&
        point == GridPoint(active['x']! as int, active['y']! as int)) {
      _drawingRoute = true;
    }
  }

  void _pointerMove(GridPoint? point) {
    if (!_drawingRoute || point == null || _draftRoute.contains(point)) return;
    final view = widget.ctx.view;
    final units = _objects(view['units']);
    final active = _activeUnit(units, view);
    if (active == null) return;
    final mapWidth = view['width'] as int? ?? tacticalMapWidth;
    final origin = GridPoint(active['x']! as int, active['y']! as int);
    final previous = _draftRoute.isEmpty ? origin : _draftRoute.last;
    final next = _stepToward(previous, point);
    if (next == null) return;
    final tiles = _objects(view['tiles']);
    final tile = tiles[next.y * mapWidth + next.x];
    if (tile['passable'] != true || _unitAtUnits(units, next) != null) return;
    final movement = active['movement'] as int;
    final profile = active['terrainMovementCosts'];
    int costOf(Map<String, Object?> routeTile) {
      if (profile is Map<Object?, Object?>) {
        final cost = profile[routeTile['terrain']];
        if (cost is num) return cost.toInt();
      }
      return tacticalMovementScale;
    }

    final routeCost = _draftRoute.fold<int>(
      0,
      (total, step) => total + costOf(tiles[step.y * mapWidth + step.x]),
    );
    if (routeCost + costOf(tile) <= movement * tacticalMovementScale) {
      setState(() => _draftRoute.add(next));
    }
  }

  void _pointerUp(GridPoint? point, Map<String, Object?>? unit) {
    final view = widget.ctx.view;
    final units = _objects(view['units']);
    final active = _activeUnit(units, view);
    if (view['canAct'] != true) return;
    if (_mode == 'pan') return;
    if (_drawingRoute && _draftRoute.isNotEmpty && active != null) {
      widget.ctx.sendAction({
        'type': 'planRoute',
        'unit': active['id'],
        'path': [for (final step in _draftRoute) step.toJson()],
      });
      setState(() {
        _drawingRoute = false;
        _draftRoute.clear();
      });
      return;
    }
    if (_mode == 'route' && point != null && active != null) {
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
        widget.ctx.sendAction({
          'type': 'planRoute',
          'unit': active['id'],
          'path': [for (final step in path) step.toJson()],
        });
        setState(() {
          _drawingRoute = false;
          _draftRoute.clear();
        });
      }
      return;
    }
    if (active == null && unit != null && unit['owner'] == widget.ctx.myId) {
      widget.ctx.sendAction({'type': 'selectUnit', 'unit': unit['id']});
      return;
    }
    if (active != null && _selectedCardId != null) {
      final cards = _objects(active['hand']);
      final card = cards
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
    setState(() {
      _mode = null;
      _drawingRoute = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.ctx.view;
    final units = _objects(view['units']);
    final tiles = _objects(view['tiles']);
    final traps = _objects(view['traps']);
    final reachable = _points(view['reachable']);
    final active = _activeUnit(units, view);
    final activeRoute = _points(active?['route']);
    final canAct = view['canAct'] == true;
    final turn = view['turn'] as String?;
    final damage = _lastDamage(view['lastAction']);
    final status = view['winner'] != null
        ? (view['winner'] == widget.ctx.myId ? 'Victory!' : 'Defeat')
        : canAct && active == null
        ? 'Your turn · choose an available unit'
        : canAct && _mode == 'route'
        ? 'Drag across the map to plot the active unit’s Strides route'
        : canAct && (_mode == 'attack' || _mode == 'skill')
        ? 'Choose an enemy inside the selected card’s range'
        : canAct && _mode == 'trap'
        ? activeRoute.isEmpty
              ? 'Choose an empty tile 1–3 steps away for the snare'
              : 'Tap an empty tile on the planned route, or within 3 steps'
        : canAct
        ? '${active?['name']} is active · play its cards, then finish the unit'
        : turn == null
        ? 'Battle'
        : '${widget.ctx.lobby.nicknameOf(turn)}’s turn';
    final energy = active?['energy'] as int? ?? 0;
    final hand = _objects(active?['hand']);
    final selectedCard = hand
        .where((card) => card['id'] == _selectedCardId)
        .firstOrNull;
    final ownUnits = units
        .where((unit) => unit['owner'] == widget.ctx.myId)
        .toList();
    final mapWidth = view['width'] as int? ?? tacticalMapWidth;
    final mapHeight = view['height'] as int? ?? tacticalMapHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = min(
          72.0,
          min(
            constraints.maxWidth / mapWidth,
            constraints.maxHeight / mapHeight,
          ),
        );
        final endRoundButton = _ActionButton(
          key: const ValueKey('tacticalvoxelrpg-end-turn'),
          label: 'End round',
          icon: Icons.skip_next,
          enabled: canAct && view['canEndTurn'] == true,
          onPressed: () => widget.ctx.sendAction({'type': 'endTurn'}),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Listener(
                key: _mapViewportKey,
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  final point = _mapPointAt(
                    event.position,
                    tileSize,
                    mapWidth,
                    mapHeight,
                  );
                  _pointerDown(point);
                },
                onPointerMove: (event) {
                  final point = _mapPointAt(
                    event.position,
                    tileSize,
                    mapWidth,
                    mapHeight,
                  );
                  _pointerMove(point);
                },
                onPointerUp: (event) {
                  final point = _mapPointAt(
                    event.position,
                    tileSize,
                    mapWidth,
                    mapHeight,
                  );
                  _pointerUp(
                    point,
                    point == null ? null : _unitAtUnits(units, point),
                  );
                },
                child: InteractiveViewer(
                  transformationController: _mapTransform,
                  constrained: false,
                  panEnabled: _mode == 'pan',
                  scaleEnabled: _mode == 'pan',
                  minScale: 0.7,
                  maxScale: 2.4,
                  boundaryMargin: const EdgeInsets.all(180),
                  child: _TacticalBoard(
                    tiles: tiles,
                    units: units,
                    traps: traps,
                    reachable: reachable,
                    route: [...activeRoute, ..._draftRoute],
                    friendlyOwner: widget.ctx.myId,
                    lastAction: view['lastAction'],
                    recentActions: _objects(view['recentActions']),
                    attackMode: _mode == 'attack' || _mode == 'skill',
                    tileSize: tileSize,
                    mapWidth: mapWidth,
                    mapHeight: mapHeight,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 64,
              left: 8,
              right: 8,
              child: SafeArea(
                bottom: false,
                child: IgnorePointer(
                  child: _OverlayPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            status,
                            key: const ValueKey('tacticalvoxelrpg-status'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('Round ${view['round']}'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (damage != null)
              Positioned(
                top: 118,
                left: 12,
                right: 12,
                child: SafeArea(
                  bottom: false,
                  child: Center(
                    child: _OverlayPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Text(
                        '${damage['damage']} damage · ${damage['targetHp']} HP remaining',
                        key: const ValueKey('tacticalvoxelrpg-damage-summary'),
                        style: const TextStyle(
                          color: Color(0xfff46f62),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (active != null || canAct)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: SafeArea(
                  top: false,
                  child: _OverlayPanel(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: active == null
                        ? Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 112,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    children: [
                                      for (final unit in ownUnits.where(
                                        (unit) => unit['completed'] != true,
                                      ))
                                        _UnitActivationCard(
                                          unit: unit,
                                          onTap: () => widget.ctx.sendAction({
                                            'type': 'selectUnit',
                                            'unit': unit['id'],
                                          }),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              endRoundButton,
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${active['name']} · HP ${active['hp']}/${active['maxHp']} · '
                                'AP $energy/${active['maxEnergy']} · Move ${active['movement']} · '
                                'Mana ${active['mana']}/${active['maxMana']} · ${active['weapon']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Text('ACTION HAND'),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${hand.length} hand · ${active['drawCount']} draw · '
                                      '${active['discardCount']} discard',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(
                                height: min(166, constraints.maxHeight * 0.25),
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  children: [
                                    for (final card in hand)
                                      _TacticalHandCard(
                                        card: card,
                                        movement: active['movement'] as int,
                                        selected: card['id'] == _selectedCardId,
                                        retained:
                                            card['id'] ==
                                            active['retainedCardId'],
                                        onTap: () => _selectCard(card),
                                        onRetain: () => widget.ctx.sendAction({
                                          'type': 'retainCard',
                                          'unit': active['id'],
                                          'cardId': card['id'],
                                        }),
                                      ),
                                  ],
                                ),
                              ),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (selectedCard?['kind'] == 'move')
                                    _ActionButton(
                                      key: const ValueKey(
                                        'tacticalvoxelrpg-move',
                                      ),
                                      label: 'Play Strides',
                                      icon: Icons.route,
                                      enabled:
                                          canAct &&
                                          energy >=
                                              (selectedCard?['cost'] as int) &&
                                          activeRoute.isNotEmpty,
                                      onPressed: () => _useCard(
                                        active,
                                        selectedCard!,
                                        path: activeRoute,
                                      ),
                                    ),
                                  _ActionButton(
                                    key: const ValueKey(
                                      'tacticalvoxelrpg-finish-unit',
                                    ),
                                    label: 'Finish unit',
                                    icon: Icons.check_circle_outline,
                                    enabled: canAct,
                                    onPressed: () => _finishActive(active),
                                  ),
                                  endRoundButton,
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            Positioned(
              right: 8,
              top: 72,
              child: _MapZoomControls(
                keyPrefix: 'tacticalvoxelrpg',
                onZoomIn: () => _zoomMap(1.25),
                onZoomOut: () => _zoomMap(0.8),
                onReset: _resetMapZoom,
              ),
            ),
            Positioned(
              right: 68,
              top: 72,
              child: _ActionButton(
                key: const ValueKey('tacticalvoxelrpg-pan-map'),
                label: _mode == 'pan' ? 'Stop panning' : 'Pan map',
                icon: Icons.pan_tool_alt,
                selected: _mode == 'pan',
                enabled: true,
                onPressed: () =>
                    setState(() => _mode = _mode == 'pan' ? null : 'pan'),
              ),
            ),
          ],
        );
      },
    );
  }
}
