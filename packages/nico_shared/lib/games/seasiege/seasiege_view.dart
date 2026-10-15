import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';
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
    final enemySunk = shipCells(enemy.sunk);
    final mySunk = shipCells(myBoard.sunk).keys.toSet();
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
            ships: enemySunk,
            sunkCells: enemySunk.keys.toSet(),
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
            ships: shipCells(fleet),
            sunkCells: mySunk,
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

  Widget _placing(List<Json> fleet, ThemeData theme) {
    final view = ctx.view;
    final ready = (view['ready']! as Json)[ctx.myId] == true;
    final cells = shipCells(fleet);
    final selected = ready ? null : _selected;
    Json? shipById(String? id) => fleet.where((s) => s['id'] == id).firstOrNull;

    void move(Json ship, int row, int col, bool vertical) => ctx.sendAction({
      'type': 'move',
      'ship': ship['id'],
      'row': row,
      'col': col,
      'vertical': vertical,
    });

    void tap(int cell) {
      final hit = cells[cell];
      final ship = shipById(selected);
      if (hit != null) {
        setState(() => _selected = hit == selected ? null : hit);
      } else if (ship != null) {
        move(
          ship,
          cell ~/ kSeaSize,
          cell % kSeaSize,
          ship['vertical']! as bool,
        );
      }
    }

    final ship = shipById(selected);
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
        Text(
          ready
              ? 'Tap Unready to change it.'
              : ship == null
              ? 'Tap a ship to move or rotate it, or Shuffle.'
              : '${ship['name']}: tap a square for its front end.',
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SeaGrid(
              keyPrefix: 'sea-own',
              ships: cells,
              selectedShip: selected,
              onTap: ready ? null : tap,
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
                    : () => move(
                        ship,
                        ship['row']! as int,
                        ship['col']! as int,
                        !(ship['vertical']! as bool),
                      ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('sea-shuffle'),
                icon: const Icon(Icons.shuffle),
                label: const Text('Shuffle'),
                onPressed: ready
                    ? null
                    : () => ctx.sendAction({'type': 'shuffle'}),
              ),
              FilledButton.icon(
                key: const ValueKey('sea-ready'),
                icon: Icon(ready ? Icons.lock_open : Icons.check),
                label: Text(ready ? 'Unready' : 'Ready'),
                onPressed: () {
                  setState(() => _selected = null);
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
