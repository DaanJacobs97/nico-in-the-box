import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/game_views.dart';
import 'package:nico_shared/games/seasiege/seasiege_fleet.dart';
import 'package:nico_shared/games/seasiege/seasiege_game.dart';
import 'package:nico_shared/games/seasiege/seasiege_view.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/shared_screen_view.dart';

const ann = PlayerInfo(id: 'a', nickname: 'Ann');
const bob = PlayerInfo(id: 'b', nickname: 'Bob');

const lobby = LobbyState(
  roomName: 'Party',
  gameId: 'seasiege',
  players: [ann, bob],
  minPlayers: 2,
  maxPlayers: 2,
  hostId: 'a',
  hostName: 'Ann',
  phase: RoomPhase.playing,
);

/// Ships on even rows from column A: carrier 0-4 ... destroyer 80-81.
final rowsFleet = [
  for (final (i, type) in ShipType.values.indexed)
    Ship(type, row: i * 2, col: 0),
];

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

Widget viewOf(
  SeaSiegeSession session, {
  bool compact = false,
  List<Json>? sent,
}) => SeaSiegeView(
  ctx: GameViewContext(
    view: session.viewFor('a'),
    myId: 'a',
    lobby: lobby,
    sendAction: (action) => sent?.add(action),
    compact: compact,
  ),
);

Finder cell(String prefix, int index) => find.byKey(ValueKey('$prefix-$index'));

void main() {
  const phone = Size(400, 800);

  group('placing', () {
    late SeaSiegeSession session;
    late List<Ship> fleet;

    setUp(() {
      session = SeaSiegeSession(const [ann, bob], random: Random(3));
      fleet = [
        for (final s
            in (session.viewFor('a')['fleet']! as List<Object?>).cast<Json>())
          Ship(
            ShipType.values.byName(s['id']! as String),
            row: s['row']! as int,
            col: s['col']! as int,
            vertical: s['vertical']! as bool,
          ),
      ];
    });

    testWidgets('tap a ship, then a square, to move it', (tester) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, viewOf(session, sent: sent));
      expect(tester.takeException(), isNull);
      expect(find.text('Place your fleet'), findsOneWidget);

      final destroyer = fleet.firstWhere((s) => s.type == ShipType.destroyer);
      final taken = {for (final s in fleet) ...s.cells};
      final free = List.generate(
        100,
        (i) => i,
      ).firstWhere((i) => !taken.contains(i));
      await tester.tap(cell('sea-own', destroyer.cells.first));
      await tester.pump();
      expect(find.textContaining('Destroyer: tap a square'), findsOneWidget);
      await tester.tap(cell('sea-own', free));
      expect(sent.single, {
        'type': 'move',
        'ship': 'destroyer',
        'row': free ~/ 10,
        'col': free % 10,
        'vertical': destroyer.vertical,
      });
    });

    testWidgets('rotate, shuffle and ready send their actions', (tester) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, viewOf(session, sent: sent));
      final rotate = find.byKey(const ValueKey('sea-rotate'));
      expect(tester.widget<OutlinedButton>(rotate).onPressed, isNull);

      final carrier = fleet.first;
      await tester.tap(cell('sea-own', carrier.cells.last));
      await tester.pump();
      await tester.tap(rotate);
      await tester.tap(find.byKey(const ValueKey('sea-shuffle')));
      await tester.tap(find.byKey(const ValueKey('sea-ready')));
      expect(sent, [
        {
          'type': 'move',
          'ship': 'carrier',
          'row': carrier.row,
          'col': carrier.col,
          'vertical': !carrier.vertical,
        },
        {'type': 'shuffle'},
        {'type': 'ready'},
      ]);
    });

    testWidgets('a ready fleet is locked until Unready', (tester) async {
      session.applyAction('a', {'type': 'ready'});
      final sent = <Json>[];
      await pumpAt(tester, phone, viewOf(session, sent: sent));
      expect(find.text('Ready! Waiting for the others…'), findsOneWidget);
      await tester.tap(cell('sea-own', fleet.first.cells.first));
      await tester.tap(find.byKey(const ValueKey('sea-shuffle')));
      expect(sent, isEmpty);
      await tester.tap(find.text('Unready'));
      expect(sent, [
        {'type': 'unready'},
      ]);
    });
  });

  group('battle', () {
    SeaSiegeSession battle(String turn) => SeaSiegeSession.custom(
      const [ann, bob],
      fleets: {'a': rowsFleet, 'b': rowsFleet},
      turn: turn,
    );

    testWidgets('on your turn, tap the enemy board to fire', (tester) async {
      final session = battle('a');
      final sent = <Json>[];
      await pumpAt(tester, phone, viewOf(session, sent: sent));
      expect(tester.takeException(), isNull);
      expect(find.text('Your turn: fire!'), findsOneWidget);
      expect(find.text("Bob's fleet"), findsOneWidget);
      await tester.tap(cell('sea-enemy', 33));
      expect(sent, [
        {'type': 'fire', 'target': 'b', 'cell': 33},
      ]);
    });

    testWidgets('no firing at a square twice or out of turn', (tester) async {
      final session = battle('a')
        ..applyAction('a', fire(33))
        ..applyAction('b', fire(50));
      final sent = <Json>[];
      await pumpAt(tester, phone, viewOf(session, sent: sent));
      await tester.tap(cell('sea-enemy', 33));
      expect(sent, isEmpty, reason: 'already fired there');

      final waiting = battle('b');
      await pumpAt(tester, phone, viewOf(waiting, sent: sent));
      expect(find.text('Bob is aiming…'), findsOneWidget);
      await tester.tap(cell('sea-enemy', 0));
      expect(sent, isEmpty);
    });

    testWidgets('compact view keeps both boards but drops the log', (
      tester,
    ) async {
      final session = battle('a')..applyAction('a', fire(41));
      await pumpAt(tester, phone, viewOf(session));
      expect(find.text('Ann fired at B5: Hit! Cruiser.'), findsNothing);
      expect(find.text('You fired at B5: Hit! Cruiser.'), findsOneWidget);

      await pumpAt(tester, phone, viewOf(session, compact: true));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('fired at'), findsNothing);
      expect(cell('sea-enemy', 0), findsOneWidget);
      expect(cell('sea-own', 0), findsOneWidget);
    });
  });

  group('shared screen at TV size', () {
    Future<void> pumpScreen(WidgetTester tester, Json table) => pumpAt(
      tester,
      const Size(1920, 1080),
      SharedScreenView(
        state: DisplayState(lobby: lobby, gameId: 'seasiege', table: table),
      ),
    );

    testWidgets('while placing it shows who is ready', (tester) async {
      final session = SeaSiegeSession(const [ann, bob], random: Random(1))
        ..applyAction('b', {'type': 'ready'});
      await pumpScreen(tester, session.tableView());
      expect(tester.takeException(), isNull);
      expect(find.text('Ann: placing ships…'), findsOneWidget);
      expect(find.text('Bob: ready'), findsOneWidget);
    });

    testWidgets('in battle it shows both boards and the last shot', (
      tester,
    ) async {
      final session =
          SeaSiegeSession.custom(
              const [ann, bob],
              fleets: {'a': rowsFleet, 'b': rowsFleet},
              shootAgain: true,
            )
            ..applyAction('a', fire(80))
            ..applyAction('a', fire(81));
      await pumpScreen(tester, session.tableView());
      expect(tester.takeException(), isNull);
      expect(find.text("Ann's turn to fire"), findsOneWidget);
      expect(find.text('A hit earns another shot'), findsOneWidget);
      expect(find.text("Ann's fleet"), findsOneWidget);
      expect(find.text("Bob's fleet"), findsOneWidget);
      expect(
        find.text('Ann fired at B9: Hit! Destroyer sunk!'),
        findsOneWidget,
      );
      expect(
        find.text('Afloat: Carrier, Battleship, Cruiser, Submarine'),
        findsOneWidget,
      );
      expect(cell('table-b', 80), findsOneWidget);
    });
  });
}

Json fire(int cell) => {'type': 'fire', 'cell': cell};
