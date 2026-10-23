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
part 'tacticalvoxelrpg_hud.dart';
part 'tacticalvoxelrpg_hud_cards.dart';
part 'tacticalvoxelrpg_hud_presenters.dart';

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
  bool _ignoreNextMapUp = false;
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
    final ownUnits = units
        .where((unit) => unit['owner'] == widget.ctx.myId)
        .toList();
    final portraitUnit =
        active ??
        ownUnits.where((unit) => unit['completed'] != true).firstOrNull ??
        ownUnits.firstOrNull;
    final mapWidth = view['width'] as int? ?? tacticalMapWidth;
    final mapHeight = view['height'] as int? ?? tacticalMapHeight;
    final phase = turn == tacticalAiId
        ? 'ENEMY PHASE'
        : '${widget.ctx.lobby.nicknameOf(turn ?? widget.ctx.myId).toUpperCase()} PHASE';
    final status = view['winner'] != null
        ? (view['winner'] == widget.ctx.myId ? 'Victory!' : 'Defeat')
        : canAct && active == null
        ? 'Choose a hero to begin their activation.'
        : canAct && _mode == 'route'
        ? 'Drag a route from the active hero to a highlighted tile.'
        : canAct && (_mode == 'attack' || _mode == 'skill')
        ? 'Choose an enemy inside the selected card’s range.'
        : canAct && _mode == 'trap'
        ? activeRoute.isEmpty
              ? 'Choose an empty tile 1–3 steps away for the snare.'
              : 'Tap an empty tile on the planned route, or within 3 steps.'
        : canAct
        ? '${active?['name']} is committed. Play actions, then finish the unit.'
        : turn == null
        ? 'Select a card to command your unit.'
        : '${widget.ctx.lobby.nicknameOf(turn)}’s turn.';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final tileSize = min(
          72.0,
          min(
            constraints.maxWidth / mapWidth,
            constraints.maxHeight / mapHeight,
          ),
        );
        final attackTargets = <String>{};
        if (active != null && (_mode == 'attack' || _mode == 'skill')) {
          final minimum = _mode == 'skill' ? 1 : active['minimumRange'] as int;
          final maximum = _mode == 'skill' ? 4 : active['range'] as int;
          for (final target in units.where(
            (unit) => unit['owner'] != widget.ctx.myId,
          )) {
            final distance =
                ((target['x'] as int) - (active['x'] as int)).abs() +
                ((target['y'] as int) - (active['y'] as int)).abs();
            if (distance >= minimum && distance <= maximum) {
              attackTargets.add(target['id'] as String);
            }
          }
        }
        final trapTargets = <GridPoint>{};
        if (active != null && _mode == 'trap') {
          for (var y = 0; y < mapHeight; y++) {
            for (var x = 0; x < mapWidth; x++) {
              final point = GridPoint(x, y);
              final distance =
                  (x - (active['x'] as int)).abs() +
                  (y - (active['y'] as int)).abs();
              final tile = tiles[y * mapWidth + x];
              final occupied =
                  _unitAtUnits(units, point) != null ||
                  traps.any((trap) => trap['x'] == x && trap['y'] == y);
              if (distance >= 1 &&
                  distance <= 3 &&
                  tile['passable'] == true &&
                  !occupied) {
                trapTargets.add(point);
              }
            }
          }
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DragTarget<_TacticalDragPayload>(
                onWillAcceptWithDetails: (details) {
                  final payload = details.data;
                  if (payload.cardId != null) {
                    return canAct && active?['id'] == payload.unitId;
                  }
                  final unit = units
                      .where((entry) => entry['id'] == payload.unitId)
                      .firstOrNull;
                  return canAct &&
                      active == null &&
                      unit != null &&
                      unit['owner'] == widget.ctx.myId &&
                      unit['completed'] != true;
                },
                onAcceptWithDetails: (details) {
                  final payload = details.data;
                  _ignoreNextMapUp = true;
                  if (payload.cardId == null) {
                    widget.ctx.sendAction({
                      'type': 'selectUnit',
                      'unit': payload.unitId,
                    });
                    return;
                  }
                  final card = _objects(active?['hand'])
                      .where((entry) => entry['id'] == payload.cardId)
                      .firstOrNull;
                  if (card != null) _selectCard(card);
                },
                builder:
                    (
                      BuildContext context,
                      List<_TacticalDragPayload?> candidates,
                      List<dynamic> rejected,
                    ) => Stack(
                      fit: StackFit.expand,
                      children: [
                        Listener(
                          key: _mapViewportKey,
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (event) {
                            _ignoreNextMapUp = false;
                            _pointerDown(
                              _mapPointAt(
                                event.position,
                                tileSize,
                                mapWidth,
                                mapHeight,
                              ),
                            );
                          },
                          onPointerMove: (event) => _pointerMove(
                            _mapPointAt(
                              event.position,
                              tileSize,
                              mapWidth,
                              mapHeight,
                            ),
                          ),
                          onPointerUp: (event) {
                            if (_ignoreNextMapUp) {
                              _ignoreNextMapUp = false;
                              return;
                            }
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
                            alignment: Alignment.center,
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
                              lastAction: view['lastAction'],
                              recentActions: _objects(view['recentActions']),
                              attackTargets: attackTargets,
                              trapTargets: trapTargets,
                              tileSize: tileSize,
                              mapWidth: mapWidth,
                              mapHeight: mapHeight,
                            ),
                          ),
                        ),
                        if (candidates.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xffd6bd84),
                                    width: 3,
                                  ),
                                  color: const Color(0x22101513),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [
                        Color(0x4d101513),
                        Color(0x00101513),
                        Color(0x00101513),
                        Color(0xb30d1311),
                      ],
                      stops: [0, 0.18, 0.54, compact ? 0.8 : 0.88],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 28,
              top: 78,
              child: IgnorePointer(
                child: SizedBox(
                  width: compact ? 230 : 330,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _HudLabel('CURRENT OBJECTIVE'),
                      const SizedBox(height: 5),
                      Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 17,
                          color: Color(0xffe0d5b4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 70,
              left: 0,
              right: 0,
              child: Center(
                child: _BattleStatusCard(
                  phase: phase,
                  turn: (view['round'] as int? ?? 0) + 1,
                ),
              ),
            ),
            Positioned(
              left: 28,
              top: 150,
              child: _SquadHealthRow(units: ownUnits, activeId: active?['id']),
            ),
            if (!compact && portraitUnit != null)
              Positioned(
                right: 25,
                top: 105,
                child: _TacticalPortraitPanel(
                  unit: portraitUnit,
                  action: view['lastAction'],
                ),
              ),
            if (damage != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: compact ? 345 : 350,
                child: Center(
                  child: _OverlayPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Text(
                      '−${damage['damage']} HP  ·  ${damage['targetHp']} remaining',
                      key: const ValueKey('tacticalvoxelrpg-damage-summary'),
                      style: const TextStyle(
                        color: Color(0xfff46f62),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _TacticalHud(
                  units: units,
                  ownerId: widget.ctx.myId,
                  active: active,
                  hand: _objects(active?['hand']),
                  selectedCardId: _selectedCardId,
                  mode: _mode,
                  canAct: canAct,
                  canEndTurn: view['canEndTurn'] == true,
                  onActivate: (id) =>
                      widget.ctx.sendAction({'type': 'selectUnit', 'unit': id}),
                  onSelectCard: _selectCard,
                  onRetainCard: (id) => widget.ctx.sendAction({
                    'type': 'retainCard',
                    'unit': active?['id'],
                    'cardId': id,
                  }),
                  onPan: () =>
                      setState(() => _mode = _mode == 'pan' ? null : 'pan'),
                  onFinish: () {
                    if (active != null) _finishActive(active);
                  },
                  onEndTurn: () => widget.ctx.sendAction({'type': 'endTurn'}),
                ),
              ),
            ),
            Positioned(
              right: compact ? 8 : 230,
              top: 72,
              child: _MapZoomControls(
                keyPrefix: 'tacticalvoxelrpg',
                onZoomIn: () => _zoomMap(1.25),
                onZoomOut: () => _zoomMap(0.8),
                onReset: _resetMapZoom,
              ),
            ),
          ],
        );
      },
    );
  }
}
