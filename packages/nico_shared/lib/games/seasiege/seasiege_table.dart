import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';
import 'sea_grid.dart';
import 'seasiege_fleet.dart';

/// One board as the views send it: shots plus the ships sunk on it.
class SeaBoard {
  SeaBoard.fromJson(Json board)
    : hits = {...(board['hits']! as List<Object?>).cast<int>()},
      misses = {...(board['misses']! as List<Object?>).cast<int>()},
      sunk = [
        for (final s in board['sunk']! as List<Object?>)
          Ship.fromJson(s! as Json),
      ],
      afloat = (board['afloat']! as List<Object?>).cast<String>();

  final Set<int> hits;
  final Set<int> misses;
  final List<Ship> sunk;
  final List<String> afloat;

  Set<String> get sunkIds => {for (final ship in sunk) ship.type.name};

  bool isShot(int cell) => hits.contains(cell) || misses.contains(cell);
}

/// [order] with the host first, otherwise unchanged.
List<String> hostFirst(List<String> order, String? hostId) => [
  ...order.where((id) => id == hostId),
  ...order.where((id) => id != hostId),
];

/// "Ann fired at D4: Hit! Cruiser sunk!" for a `log` entry.
String describeShot(Json shot, String Function(String playerId) nameOf) {
  final ship = shot['ship'];
  final outcome = switch (shot['result']) {
    'sunk' => 'Hit! $ship sunk!',
    'hit' => 'Hit! $ship.',
    _ => 'Miss.',
  };
  return '${nameOf(shot['shooter']! as String)} fired at '
      '${cellName(shot['cell']! as int)}: $outcome';
}

/// Sea Siege on the shared screen: who is still placing, then every board
/// (the host's first) on animated water with its shots and sunk ships,
/// whose turn it is and the last shots. Boards sit side by side on a wide
/// screen and stacked on a tall one.
class SeaSiegeTable extends StatelessWidget {
  const SeaSiegeTable({super.key, required this.ctx});

  final TableContext ctx;

  @override
  Widget build(BuildContext context) {
    final table = ctx.table;
    final order = (table['order']! as List<Object?>).cast<String>();
    final boards = table['boards']! as Json;
    final ready = (table['ready']! as Json).cast<String, bool>();
    final log = [for (final e in table['log']! as List<Object?>) e! as Json];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.biggest.shortestSide / 450).clamp(1.0, 2.5);
        final big = TextStyle(
          fontSize: 26 * scale,
          fontWeight: FontWeight.w700,
        );
        final normal = TextStyle(fontSize: 16 * scale);
        if (table['phase'] == 'placing') {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Captains, hide your fleets!', style: big),
                SizedBox(height: 16 * scale),
                for (final id in order)
                  Text(
                    '${ctx.nicknameOf(id)}: '
                    '${ready[id]! ? 'ready' : 'placing ships…'}',
                    style: TextStyle(fontSize: 22 * scale),
                  ),
              ],
            ),
          );
        }
        final winner = table['winner'] as String?;
        final turn = table['turn'] as String?;
        final landscape = constraints.maxWidth >= constraints.maxHeight;
        return Padding(
          padding: EdgeInsets.all(12 * scale),
          child: Column(
            children: [
              Text(
                winner != null
                    ? '${ctx.nicknameOf(winner)} wins!'
                    : "${ctx.nicknameOf(turn!)}'s turn to fire",
                style: big,
              ),
              if (table['shootAgain'] == true)
                Text('A hit earns another shot', style: normal),
              SizedBox(height: 8 * scale),
              Expanded(
                child: Flex(
                  key: const ValueKey('sea-boards'),
                  direction: landscape ? Axis.horizontal : Axis.vertical,
                  children: [
                    for (final id in hostFirst(order, ctx.lobby.hostId))
                      Expanded(
                        child: _BoardPanel(
                          title: "${ctx.nicknameOf(id)}'s fleet",
                          board: SeaBoard.fromJson(boards[id]! as Json),
                          keyPrefix: 'table-$id',
                          style: normal,
                        ),
                      ),
                  ],
                ),
              ),
              for (final shot in log.reversed.take(2))
                Text(describeShot(shot, ctx.nicknameOf), style: normal),
            ],
          ),
        );
      },
    );
  }
}

class _BoardPanel extends StatelessWidget {
  const _BoardPanel({
    required this.title,
    required this.board,
    required this.keyPrefix,
    required this.style,
  });

  final String title;
  final SeaBoard board;
  final String keyPrefix;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title, style: style.copyWith(fontWeight: FontWeight.w700)),
        Expanded(
          child: SeaGrid(
            hits: board.hits,
            misses: board.misses,
            fleet: board.sunk,
            sunk: board.sunkIds,
            animatedWater: true,
            keyPrefix: keyPrefix,
          ),
        ),
        Text(
          board.afloat.isEmpty
              ? 'Fleet sunk'
              : 'Afloat: ${board.afloat.join(', ')}',
          style: style,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
