import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';
import 'seasiege_fleet.dart';

const _water = Color(0xFF1565C0);
const _shipColor = Color(0xFF90A4AE);
const _sunkColor = Color(0xFF4E342E);
const _selectedColor = Color(0xFFFFB300);
const _hitColor = Color(0xFFE53935);
const _missColor = Color(0xFFE3F2FD);
const _previewColor = Color(0xFF43A047);

/// One board as the views send it: shots plus any ships drawn on it.
class SeaBoard {
  SeaBoard.fromJson(Json board)
    : hits = {...(board['hits']! as List<Object?>).cast<int>()},
      misses = {...(board['misses']! as List<Object?>).cast<int>()},
      sunk = [for (final s in board['sunk']! as List<Object?>) s! as Json],
      afloat = (board['afloat']! as List<Object?>).cast<String>();

  final Set<int> hits;
  final Set<int> misses;
  final List<Json> sunk;
  final List<String> afloat;

  bool isShot(int cell) => hits.contains(cell) || misses.contains(cell);
}

/// Cells of [ships] (ship JSON with `id` and `cells`), by cell.
Map<int, String> shipCells(Iterable<Json> ships) => {
  for (final ship in ships)
    for (final cell in (ship['cells']! as List<Object?>).cast<int>())
      cell: ship['id']! as String,
};

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

/// A 10×10 board with A–J / 1–10 labels, sized to fit its space. Draws
/// [ships] (cell -> ship id), [sunkCells], hits, misses and a drag
/// [preview]. Gestures are handled for the whole board and reported as
/// squares: [onTap], [onDoubleTap] and the three drag callbacks.
class SeaGrid extends StatelessWidget {
  const SeaGrid({
    super.key,
    this.hits = const {},
    this.misses = const {},
    this.ships = const {},
    this.sunkCells = const {},
    this.selectedShip,
    this.preview = const {},
    this.previewValid = true,
    this.onTap,
    this.onDoubleTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.keyPrefix = 'sea',
  });

  final Set<int> hits;
  final Set<int> misses;
  final Map<int, String> ships;
  final Set<int> sunkCells;
  final String? selectedShip;

  /// Squares a dragged ship would cover, drawn green or red.
  final Set<int> preview;
  final bool previewValid;

  final void Function(int cell)? onTap;

  /// Setting this delays single taps by the double-tap timeout.
  final void Function(int cell)? onDoubleTap;
  final void Function(int cell)? onDragStart;

  /// The square under the finger, clamped onto the board.
  final void Function(int cell)? onDragUpdate;
  final VoidCallback? onDragEnd;

  /// Cells get the key `<keyPrefix>-<cell>`, for tests and bots.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final cell = (side / (kSeaSize + 1)).floorToDouble().clamp(8.0, 96.0);
        final label = TextStyle(
          fontSize: cell * 0.45,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
        Widget labelBox(String text) => SizedBox(
          width: cell,
          height: cell,
          child: Center(child: Text(text, style: label)),
        );
        int at(Offset local) {
          final r = (local.dy / cell).floor().clamp(0, kSeaSize - 1);
          final c = (local.dx / cell).floor().clamp(0, kSeaSize - 1);
          return r * kSeaSize + c;
        }

        var doubleTapAt = 0;
        final tap = onTap;
        final doubleTap = onDoubleTap;
        final dragStart = onDragStart;
        final dragUpdate = onDragUpdate;
        final dragEnd = onDragEnd;
        final board = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: tap == null ? null : (d) => tap(at(d.localPosition)),
          onDoubleTapDown: doubleTap == null
              ? null
              : (d) => doubleTapAt = at(d.localPosition),
          onDoubleTap: doubleTap == null ? null : () => doubleTap(doubleTapAt),
          onPanStart: dragStart == null
              ? null
              : (d) => dragStart(at(d.localPosition)),
          onPanUpdate: dragUpdate == null
              ? null
              : (d) => dragUpdate(at(d.localPosition)),
          onPanEnd: dragEnd == null ? null : (_) => dragEnd(),
          onPanCancel: dragEnd,
          // Report the square the finger first touched (the ship being
          // grabbed), not where it had moved to once the drag was detected.
          dragStartBehavior: DragStartBehavior.down,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < kSeaSize; r++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var c = 0; c < kSeaSize; c++)
                      _cell(r * kSeaSize + c, cell),
                  ],
                ),
            ],
          ),
        );
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  labelBox(''),
                  for (var c = 0; c < kSeaSize; c++)
                    labelBox(cellName(c).substring(0, 1)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var r = 0; r < kSeaSize; r++) labelBox('${r + 1}'),
                    ],
                  ),
                  if (dragStart == null)
                    board
                  else
                    // Flutter starts a touch drag only after ~36 px, more than
                    // a whole square on a phone. Scale it to the square so a
                    // one-square drag works; taps still allow a little wobble.
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        gestureSettings: DeviceGestureSettings(
                          touchSlop: (cell * 0.3).clamp(6.0, kTouchSlop),
                        ),
                      ),
                      child: board,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _cell(int index, double size) {
    final ship = ships[index];
    final color = preview.contains(index)
        ? (previewValid ? _previewColor : _hitColor)
        : sunkCells.contains(index)
        ? _sunkColor
        : ship != null && ship == selectedShip
        ? _selectedColor
        : ship != null
        ? _shipColor
        : _water;
    final marker = hits.contains(index)
        ? _hitColor
        : misses.contains(index)
        ? _missColor
        : null;
    return Container(
      key: ValueKey('$keyPrefix-$index'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.black26, width: 0.5),
      ),
      child: marker == null
          ? null
          : Center(
              child: Container(
                width: size * 0.45,
                height: size * 0.45,
                decoration: BoxDecoration(
                  color: marker,
                  shape: BoxShape.circle,
                ),
              ),
            ),
    );
  }
}

/// Sea Siege on the shared screen: who is still placing, then every board
/// with its shots and sunk ships, whose turn it is and the last shots.
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
                child: Row(
                  children: [
                    for (final id in order)
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
    final sunk = shipCells(board.sunk);
    return Column(
      children: [
        Text(title, style: style.copyWith(fontWeight: FontWeight.w700)),
        Expanded(
          child: SeaGrid(
            hits: board.hits,
            misses: board.misses,
            ships: sunk,
            sunkCells: sunk.keys.toSet(),
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
