import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';
import 'sea_grid.dart';
import 'seasiege_fleet.dart';
import 'seasiege_table.dart';

/// What a Sea Siege player sees: their own fleet while placing, then the
/// enemy board to fire at above their own board. Both boards are inputs or
/// private, so compact mode only drops the shot log.
class SeaSiegeView extends StatefulWidget {
  const SeaSiegeView({super.key, required this.ctx});

  final GameViewContext ctx;

  @override
  State<SeaSiegeView> createState() => _SeaSiegeViewState();
}

class _SeaSiegeViewState extends State<SeaSiegeView> {
  /// The ship the player tapped while placing, to move or rotate.
  String? _selected;

  /// Why the last placement didn't happen, shown in the hint line.
  String? _hint;

  /// The ship being dragged, and which of its squares was grabbed.
  ({Ship ship, int grip})? _drag;

  /// Where the dragged ship would land right now.
  Ship? _dragAt;

  GameViewContext get ctx => widget.ctx;

  @override
  Widget build(BuildContext context) {
    final view = ctx.view;
    final fleet = [for (final s in view['fleet']! as List<Object?>) s! as Json];
    final boards = view['boards']! as Json;
    final myBoard = SeaBoard.fromJson(boards[ctx.myId]! as Json);
    final theme = Theme.of(context);

    if (view['phase'] == 'placing') return _placing(fleet, theme);

    final winner = view['winner'] as String?;
    final turn = view['turn'] as String?;
    final myTurn = turn == ctx.myId;
    final order = (view['order']! as List<Object?>).cast<String>();
    // Two players: the other one. A free-for-all would add a target picker.
    final enemyId = order.firstWhere(
      (id) =>
          id != ctx.myId &&
          ((boards[id]! as Json)['afloat']! as List<Object?>).isNotEmpty,
      orElse: () => order.firstWhere((id) => id != ctx.myId),
    );
    final enemy = SeaBoard.fromJson(boards[enemyId]! as Json);
    final log = view['log']! as List<Object?>;

    final String status;
    if (winner != null) {
      status = winner == ctx.myId
          ? 'You win!'
          : '${ctx.nicknameOf(winner)} wins!';
    } else if (myTurn) {
      status = 'Your turn: fire!';
    } else {
      status = '${ctx.nicknameOf(turn!)} is aiming…';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            status,
            key: const ValueKey('seasiege-status'),
            style: theme.textTheme.headlineSmall,
          ),
        ),
        Text("${ctx.nicknameOf(enemyId)}'s fleet"),
        Expanded(
          flex: 3,
          child: SeaGrid(
            keyPrefix: 'sea-enemy',
            hits: enemy.hits,
            misses: enemy.misses,
            fleet: enemy.sunk,
            sunk: enemy.sunkIds,
            onTap: myTurn
                ? (cell) {
                    if (enemy.isShot(cell)) return;
                    ctx.sendAction({
                      'type': 'fire',
                      'target': enemyId,
                      'cell': cell,
                    });
                  }
                : null,
          ),
        ),
        const Text('Your fleet'),
        Expanded(
          flex: 2,
          child: SeaGrid(
            keyPrefix: 'sea-own',
            hits: myBoard.hits,
            misses: myBoard.misses,
            fleet: [for (final s in fleet) Ship.fromJson(s)],
            sunk: myBoard.sunkIds,
          ),
        ),
        if (!ctx.compact && log.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(describeShot(log.last! as Json, ctx.nicknameOf)),
          ),
      ],
    );
  }

  Widget _placing(List<Json> fleetJson, ThemeData theme) {
    final view = ctx.view;
    final ready = (view['ready']! as Json)[ctx.myId] == true;
    final fleet = [for (final s in fleetJson) Ship.fromJson(s)];
    final selected = ready ? null : _selected;
    Ship? shipAt(int cell) =>
        fleet.where((s) => s.cells.contains(cell)).firstOrNull;
    Ship? shipNamed(String? id) =>
        fleet.where((s) => s.type.name == id).firstOrNull;

    void send(Ship ship) => ctx.sendAction({
      'type': 'move',
      'ship': ship.type.name,
      'row': ship.row,
      'col': ship.col,
      'vertical': ship.vertical,
    });

    /// Places [wanted] or, if it doesn't fit, the nearest spot that does.
    void place(Ship wanted, String what) {
      final placed = wanted.nudgeToFit(fleet);
      if (placed == null) {
        setState(() => _hint = 'No room for the ${wanted.type.label} $what.');
        return;
      }
      setState(() => _hint = null);
      send(placed);
    }

    void turn(Ship ship, int pivot) =>
        place(ship.rotatedAround(pivot), 'to turn there');

    void tap(int cell) {
      final hit = shipAt(cell);
      final ship = shipNamed(selected);
      if (hit != null) {
        setState(() {
          _selected = hit.type.name == selected ? null : hit.type.name;
          _hint = null;
        });
      } else if (ship != null) {
        place(
          ship.movedTo(
            row: cell ~/ kSeaSize,
            col: cell % kSeaSize,
            vertical: ship.vertical,
          ),
          'there',
        );
      }
    }

    void dragStart(int cell) {
      final ship = shipAt(cell);
      if (ship == null) return;
      setState(() {
        _drag = (ship: ship, grip: ship.cells.indexOf(cell));
        _dragAt = ship;
        _selected = ship.type.name;
        _hint = null;
      });
    }

    void dragUpdate(int cell) {
      final drag = _drag;
      if (drag == null) return;
      final r = cell ~/ kSeaSize;
      final c = cell % kSeaSize;
      final ship = drag.ship;
      setState(
        () => _dragAt = ship.movedTo(
          row: ship.vertical ? r - drag.grip : r,
          col: ship.vertical ? c : c - drag.grip,
          vertical: ship.vertical,
        ),
      );
    }

    void dragEnd() {
      final drag = _drag;
      final target = _dragAt;
      setState(() {
        _drag = null;
        _dragAt = null;
      });
      if (drag == null || target == null) return;
      if (target.row == drag.ship.row && target.col == drag.ship.col) return;
      if (target.fitsAmong(fleet)) {
        send(target);
      } else {
        setState(() => _hint = "The ${target.type.label} doesn't fit there.");
      }
    }

    final ship = shipNamed(selected);
    final dragging = _dragAt;
    final String help;
    if (ready) {
      help = 'Tap Unready to change it.';
    } else if (_hint != null) {
      help = _hint!;
    } else if (ship != null) {
      help =
          '${ship.type.label}: drag it, tap a square, or double-tap to turn.';
    } else {
      help = 'Drag a ship to move it, double-tap to turn it, or Shuffle.';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            ready ? 'Ready! Waiting for the others…' : 'Place your fleet',
            key: const ValueKey('seasiege-status'),
            style: theme.textTheme.headlineSmall,
          ),
        ),
        Text(help, key: const ValueKey('seasiege-hint')),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SeaGrid(
              keyPrefix: 'sea-own',
              // The dragged ship is lifted off the board into the preview.
              fleet: [
                for (final s in fleet)
                  if (s.type != dragging?.type) s,
              ],
              selectedShip: selected,
              preview: dragging,
              previewValid: dragging?.fitsAmong(fleet) ?? true,
              onTap: ready ? null : tap,
              onDoubleTap: ready
                  ? null
                  : (cell) {
                      final hit = shipAt(cell);
                      if (hit != null) turn(hit, cell);
                    },
              onDragStart: ready ? null : dragStart,
              onDragUpdate: ready ? null : dragUpdate,
              onDragEnd: ready ? null : dragEnd,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('sea-rotate'),
                icon: const Icon(Icons.rotate_90_degrees_cw),
                label: const Text('Rotate'),
                onPressed: ship == null
                    ? null
                    : () => turn(ship, ship.cells[ship.type.size ~/ 2]),
              ),
              OutlinedButton.icon(
                key: const ValueKey('sea-shuffle'),
                icon: const Icon(Icons.shuffle),
                label: const Text('Shuffle'),
                onPressed: ready
                    ? null
                    : () {
                        setState(() => _hint = null);
                        ctx.sendAction({'type': 'shuffle'});
                      },
              ),
              FilledButton.icon(
                key: const ValueKey('sea-ready'),
                icon: Icon(ready ? Icons.lock_open : Icons.check),
                label: Text(ready ? 'Unready' : 'Ready'),
                onPressed: () {
                  setState(() {
                    _selected = null;
                    _hint = null;
                  });
                  ctx.sendAction({'type': ready ? 'unready' : 'ready'});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
