import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'sea_effects.dart';
import 'seasiege_fleet.dart';
import 'seasiege_sprites.dart';

const _selectedColor = Color(0xFFFFB300);
const _hitColor = Color(0xFFE53935);
const _missColor = Color(0xFFE3F2FD);
const _previewColor = Color(0xFF43A047);

/// A 10×10 board with A–J / 1–10 labels, sized to fit its space. Draws
/// the [fleet] as ship sprites ([sunk] ones as wrecks), hits, misses and a
/// dragged ship's [preview]. Gestures are handled for the whole board and
/// reported as squares: [onTap], [onDoubleTap] and the three drag
/// callbacks. The water under it moves ([SeaWater]).
class SeaGrid extends StatelessWidget {
  const SeaGrid({
    super.key,
    this.hits = const {},
    this.misses = const {},
    this.fleet = const [],
    this.sunk = const {},
    this.selectedShip,
    this.preview,
    this.previewValid = true,
    this.highlighted = false,
    this.flashes = const [],
    this.onTap,
    this.onDoubleTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.keyPrefix = 'sea',
  });

  final Set<int> hits;
  final Set<int> misses;
  final List<Ship> fleet;

  /// Ids (`ShipType.name`) of the [fleet] ships that are sunk.
  final Set<String> sunk;
  final String? selectedShip;

  /// Where a dragged ship would land, drawn faintly over green or red
  /// squares.
  final Ship? preview;
  final bool previewValid;

  /// The board being fired at: a gold frame and glow.
  final bool highlighted;

  /// New shots on this board; each square pulses once.
  final List<FreshShot> flashes;

  final void Function(int cell)? onTap;

  /// Setting this delays single taps by the double-tap timeout.
  final void Function(int cell)? onDoubleTap;
  final void Function(int cell)? onDragStart;

  /// The square under the finger, clamped onto the board.
  final void Function(int cell)? onDragUpdate;
  final VoidCallback? onDragEnd;

  /// Cells get the key `<keyPrefix>-<cell>`, for tests and bots. Ships get
  /// `<keyPrefix>-ship-<id>`.
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
          child: _board(cell),
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

  /// Layers, bottom up: water, squares, ships, then the shot markers.
  Widget _board(double cell) {
    final selected = {
      for (final ship in fleet)
        if (ship.type.name == selectedShip) ...ship.cells,
    };
    final previewCells = {...?preview?.cellsOnBoard};
    Widget square(int index) => Container(
      key: ValueKey('$keyPrefix-$index'),
      width: cell,
      height: cell,
      decoration: BoxDecoration(
        color: previewCells.contains(index)
            ? (previewValid ? _previewColor : _hitColor)
            : selected.contains(index)
            ? _selectedColor
            : null,
        border: Border.all(color: Colors.black26, width: 0.5),
      ),
    );
    Widget placed(Ship ship, Widget child) => Positioned(
      left: ship.col * cell,
      top: ship.row * cell,
      width: ship.vertical ? cell : ship.type.size * cell,
      height: ship.vertical ? ship.type.size * cell : cell,
      child: child,
    );
    final marker = cell * 0.45;
    return Container(
      width: cell * kSeaSize,
      height: cell * kSeaSize,
      // Painted outside and over the board, so the glow never changes its
      // size.
      decoration: BoxDecoration(
        boxShadow: highlighted
            ? [BoxShadow(color: seaTurnColor, blurRadius: cell * 0.6)]
            : null,
      ),
      foregroundDecoration: highlighted
          ? BoxDecoration(border: Border.all(color: seaTurnColor, width: 3))
          : null,
      child: Stack(
        children: [
          const Positioned.fill(child: SeaWater()),
          Column(
            children: [
              for (var r = 0; r < kSeaSize; r++)
                Row(
                  children: [
                    for (var c = 0; c < kSeaSize; c++) square(r * kSeaSize + c),
                  ],
                ),
            ],
          ),
          // Drawing only: taps and drags land on the squares underneath.
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: [
                  for (final ship in fleet)
                    placed(
                      ship,
                      ShipSprite(
                        key: ValueKey('$keyPrefix-ship-${ship.type.name}'),
                        ship: ship,
                        sunk: sunk.contains(ship.type.name),
                      ),
                    ),
                  if (preview case final ship?)
                    placed(
                      ship,
                      Opacity(opacity: 0.6, child: ShipSprite(ship: ship)),
                    ),
                  for (final (cells, color) in [
                    (hits, _hitColor),
                    (misses, _missColor),
                  ])
                    for (final index in cells)
                      Positioned(
                        left: (index % kSeaSize + 0.5) * cell - marker / 2,
                        top: (index ~/ kSeaSize + 0.5) * cell - marker / 2,
                        width: marker,
                        height: marker,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black54),
                          ),
                        ),
                      ),
                  for (final flash in flashes)
                    Positioned(
                      key: ValueKey('$keyPrefix-flash-${flash.shot['n']}'),
                      left: (flash.cell % kSeaSize - 0.5) * cell,
                      top: (flash.cell ~/ kSeaSize - 0.5) * cell,
                      width: cell * 2,
                      height: cell * 2,
                      child: _Flash(life: flash.life),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ring that grows and fades over the first third of a shot's [life].
class _Flash extends StatelessWidget {
  const _Flash({required this.life});

  final Animation<double> life;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: life,
    builder: (context, _) {
      final t = (life.value * 3).clamp(0.0, 1.0);
      if (t >= 1) return const SizedBox.shrink();
      // Starts on the square (the box is two squares wide) and grows.
      return FractionallySizedBox(
        widthFactor: 0.4 + 0.6 * t,
        heightFactor: 0.4 + 0.6 * t,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 1 - t),
              width: 3,
            ),
          ),
        ),
      );
    },
  );
}

/// Slowly moving water:a deep-blue gradient, drifting wave lines and a
/// light shimmer sweeping across. Still when the system asks for less
/// motion.
class SeaWater extends StatefulWidget {
  const SeaWater({super.key});

  @override
  State<SeaWater> createState() => _SeaWaterState();
}

class _SeaWaterState extends State<SeaWater>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(child: CustomPaint(painter: _WaterPainter(_controller)));
}

class _WaterPainter extends CustomPainter {
  _WaterPainter(this.time) : super(repaint: time);

  /// 0 to 1, over and over.
  final Animation<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final rect = Offset.zero & size;
    canvas
      ..clipRect(rect)
      ..drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E88E5), Color(0xFF1565C0), Color(0xFF0D47A1)],
          ).createShader(rect),
      );

    // Wave lines, each row drifting a little out of step with the next.
    const rows = 14;
    final wave = Paint()
      ..color = const Color(0x2EFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1, size.height * 0.005);
    final length = size.width / 3;
    final height = size.height / rows * 0.18;
    for (var j = 0; j < rows; j++) {
      final y0 = (j + 0.5) * size.height / rows;
      final phase = 2 * pi * (t + j * 0.37) * (j.isEven ? 1 : -1);
      final path = Path()..moveTo(0, y0 + height * sin(phase));
      for (var x = 0.0; x <= size.width; x += size.width / 60) {
        path.lineTo(x, y0 + height * sin(2 * pi * x / length + phase));
      }
      canvas.drawPath(path, wave);
    }

    // A soft band of light sweeping from left to right.
    final band = size.width * 0.7;
    final left = -band + t * (size.width + band);
    final bandRect = Rect.fromLTWH(left, 0, band, size.height);
    canvas.drawRect(
      bandRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x00FFFFFF), Color(0x1FFFFFFF), Color(0x00FFFFFF)],
        ).createShader(bandRect),
    );
  }

  @override
  bool shouldRepaint(_WaterPainter old) => old.time != time;
}
