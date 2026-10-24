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
part 'tacticalvoxelrpg_interaction.dart';
part 'tacticalvoxelrpg_hud.dart';
part 'tacticalvoxelrpg_hud_cards.dart';
part 'tacticalvoxelrpg_hud_activation.dart';
part 'tacticalvoxelrpg_hud_presenters.dart';
part 'tacticalvoxelrpg_selection.dart';
part 'tacticalvoxelrpg_selection_table.dart';

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
  bool _handCollapsed = false;
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

  void _updateState(VoidCallback update) {
    if (mounted) setState(update);
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.ctx.view;
    if (view['phase'] == 'selection') {
      return _TacticalUnitSelectionScreen(ctx: widget.ctx);
    }
    final units = _objects(view['units']);
    final tiles = _objects(view['tiles']);
    final traps = _objects(view['traps']);
    final availableMovement = _mode == 'route' && _selectedCardId != null;
    final reachable = availableMovement
        ? _points(view['reachable'])
        : <GridPoint>[];
    final active = _activeUnit(units, view);
    final targetingCard = _objects(active?['hand'])
        .where((card) => card['id'] == _selectedCardId)
        .firstOrNull;
    final activeRoute = _points(active?['route']);
    final canAct = view['canAct'] == true;
    final turn = view['turn'] as String?;
    final damage = _lastDamage(view['lastAction']);
    final myUnitIds = (view['myUnits'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toSet();
    final ownUnits = myUnitIds.isEmpty
        ? units.where((unit) => unit['owner'] == widget.ctx.myId).toList()
        : units.where((unit) => myUnitIds.contains(unit['id'])).toList();
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
        ? 'Choose a yellow square, or drag from your hero to draw a path.'
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
        final attackRange = <GridPoint>{};
        if (active != null && (_mode == 'attack' || _mode == 'skill')) {
          final minimum = _mode == 'skill' ? 1 : active['minimumRange'] as int;
          final maximum = _mode == 'skill' ? 4 : active['range'] as int;
          for (var y = 0; y < mapHeight; y++) {
            for (var x = 0; x < mapWidth; x++) {
              final distance =
                  (x - (active['x'] as int)).abs() +
                  (y - (active['y'] as int)).abs();
              if (distance >= minimum && distance <= maximum) {
                attackRange.add(GridPoint(x, y));
              }
            }
          }
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
        final visibleRoute = _mode == 'route' || _mode == 'trap'
            ? _draftRoute.isNotEmpty
                  ? _draftRoute
                  : activeRoute
            : <GridPoint>[];
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DragTarget<_TacticalDragPayload>(
                onWillAcceptWithDetails: (details) {
                  final payload = details.data;
                  if (_mapPointAt(
                        details.offset,
                        tileSize,
                        mapWidth,
                        mapHeight,
                      ) ==
                      null) {
                    return false;
                  }
                  if (payload.cardId != null) {
                    if (!canAct || active?['id'] != payload.unitId) {
                      return false;
                    }
                    final card = _objects(active?['hand'])
                        .where((entry) => entry['id'] == payload.cardId)
                        .firstOrNull;
                    return card != null &&
                        (active!['energy'] as int) >= (card['cost'] as int) &&
                        (card['kind'] != 'skill' ||
                            (active['mana'] as int) >= 1);
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
                              point == null
                                  ? null
                                  : _unitAtMapPoint(units, point),
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
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: Center(
                                child: _TacticalBoard(
                                  tiles: tiles,
                                  units: units,
                                  traps: traps,
                                  reachable: reachable,
                                  route: visibleRoute,
                                  lastAction: view['lastAction'],
                                  recentActions: _objects(
                                    view['recentActions'],
                                  ),
                                  attackTargets: attackTargets,
                                  attackRange: attackRange,
                                  trapTargets: trapTargets,
                                  tileSize: tileSize,
                                  mapWidth: mapWidth,
                                  mapHeight: mapHeight,
                                ),
                              ),
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
              top: 100,
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
              top: 168,
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
            if (_selectedCardId != null)
              Positioned(
                right: compact ? 12 : 245,
                top: compact ? 112 : 78,
                child: _OverlayPanel(
                  child: SizedBox(
                    width: compact ? 210 : 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HudLabel(
                          'PLAYING ${targetingCard?['name'] ?? 'CARD'}',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          switch (_mode) {
                            'route' => 'Choose a yellow square, or drag a path and click its endpoint.',
                            'attack' || 'skill' =>
                              'Choose a red-highlighted enemy to attack.',
                            'trap' => 'Choose a highlighted empty square.',
                            _ => 'Choose a valid target for this card.',
                          },
                          style: const TextStyle(
                            color: Color(0xffe0d5f0),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const ValueKey(
                              'tacticalvoxelrpg-cancel-targeting',
                            ),
                            onPressed: _cancelTargeting,
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                  units: ownUnits,
                  active: active,
                  hand: _objects(active?['hand']),
                  selectedCardId: _selectedCardId,
                  mode: _mode,
                  handCollapsed: _handCollapsed,
                  onToggleHand: () =>
                      setState(() => _handCollapsed = !_handCollapsed),
                  canAct: canAct,
                  canEndTurn: view['canEndTurn'] == true,
                  onInspectUnit: _inspectUnit,
                  onInspectCard: _inspectCard,
                  onRetainCard: _retainCard,
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
              top: _selectedCardId == null ? 72 : 205,
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
