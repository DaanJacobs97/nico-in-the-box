import 'dart:math';

import '../../net/protocol.dart';

/// Sea Siege boards are [kSeaSize] × [kSeaSize]. Cells are numbered
/// `row * kSeaSize + col`, so cell 0 is A1 and cell 99 is J10.
const int kSeaSize = 10;

const _columns = 'ABCDEFGHIJ';

/// "D4" for column D, row 4.
String cellName(int cell) =>
    '${_columns[cell % kSeaSize]}${cell ~/ kSeaSize + 1}';

/// The five ships every fleet has, largest first.
enum ShipType {
  carrier('Carrier', 5),
  battleship('Battleship', 4),
  cruiser('Cruiser', 3),
  submarine('Submarine', 3),
  destroyer('Destroyer', 2);

  const ShipType(this.label, this.size);

  final String label;
  final int size;
}

/// A placed ship: its bow at ([row], [col]), running right or down.
class Ship {
  const Ship(
    this.type, {
    required this.row,
    required this.col,
    this.vertical = false,
  });

  final ShipType type;
  final int row;
  final int col;
  final bool vertical;

  List<int> get cells => [
    for (var i = 0; i < type.size; i++)
      vertical ? (row + i) * kSeaSize + col : row * kSeaSize + col + i,
  ];

  bool get inBounds =>
      row >= 0 &&
      col >= 0 &&
      (vertical ? row + type.size : row + 1) <= kSeaSize &&
      (vertical ? col + 1 : col + type.size) <= kSeaSize;

  bool overlaps(Ship other) => cells.any(other.cells.contains);

  Ship movedTo({required int row, required int col, required bool vertical}) =>
      Ship(type, row: row, col: col, vertical: vertical);

  Json toJson() => {
    'id': type.name,
    'name': type.label,
    'size': type.size,
    'row': row,
    'col': col,
    'vertical': vertical,
    'cells': cells,
  };
}

/// Whether [fleet] has every ship type once, all on the board and apart.
bool isValidFleet(List<Ship> fleet) {
  if (fleet.length != ShipType.values.length) return false;
  if (fleet.map((s) => s.type).toSet().length != fleet.length) return false;
  for (var i = 0; i < fleet.length; i++) {
    if (!fleet[i].inBounds) return false;
    for (var j = i + 1; j < fleet.length; j++) {
      if (fleet[i].overlaps(fleet[j])) return false;
    }
  }
  return true;
}

/// A random valid fleet. Ships may touch, as in the board game.
List<Ship> randomFleet(Random random) {
  final fleet = <Ship>[];
  for (final type in ShipType.values) {
    while (true) {
      final vertical = random.nextBool();
      final ship = Ship(
        type,
        vertical: vertical,
        row: random.nextInt(vertical ? kSeaSize - type.size + 1 : kSeaSize),
        col: random.nextInt(vertical ? kSeaSize : kSeaSize - type.size + 1),
      );
      if (!fleet.any(ship.overlaps)) {
        fleet.add(ship);
        break;
      }
    }
  }
  return fleet;
}
