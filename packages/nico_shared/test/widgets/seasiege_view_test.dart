import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/game_views.dart';
import 'package:nico_shared/games/seasiege/sea_grid.dart';
import 'package:nico_shared/games/seasiege/seasiege_fleet.dart';
import 'package:nico_shared/games/seasiege/seasiege_game.dart';
import 'package:nico_shared/games/seasiege/seasiege_sprites.dart';
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
    // rowsFleet: carrier 0-4, battleship 20-23, cruiser 40-42,
    // submarine 60-62, destroyer 80-81.
    Json placingView({bool ready = false}) {
      const empty = {
        'hits': <int>[],
        'misses': <int>[],
        'sunk': <Json>[],
        'afloat': <String>[],
      };
      return {
        'phase': 'placing',
        'order': ['a', 'b'],
        'ready': {'a': ready, 'b': false},
        'boards': {'a': empty, 'b': empty},
        'turn': null,
        'winner': null,
        'shootAgain': false,
        'log': <Json>[],
        'fleet': [for (final s in rowsFleet) s.toJson()],
      };
    }

    Widget placing(List<Json> sent, {bool ready = false}) => SeaSiegeView(
      ctx: GameViewContext(
        view: placingView(ready: ready),
        myId: 'a',
        lobby: lobby,
        sendAction: sent.add,
      ),
    );

    Json moveOf(Ship s) => {
      'type': 'move',
      'ship': s.type.name,
      'row': s.row,
      'col': s.col,
      'vertical': s.vertical,
    };

    // Single taps wait out the double-tap window.
    Future<void> tapCell(WidgetTester tester, int index) async {
      await tester.tap(cell('sea-own', index));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> doubleTapCell(WidgetTester tester, int index) async {
      await tester.tap(cell('sea-own', index));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(cell('sea-own', index));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a random fleet renders on a phone', (tester) async {
      final session = SeaSiegeSession(const [ann, bob], random: Random(3));
      await pumpAt(tester, phone, viewOf(session));
      expect(tester.takeException(), isNull);
      expect(find.text('Place your fleet'), findsOneWidget);
    });

    testWidgets('tap a ship, then a square, to move it', (tester) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, placing(sent));
      await tapCell(tester, 81);
      expect(find.textContaining('Destroyer: drag it'), findsOneWidget);
      await tapCell(tester, 55);
      expect(sent, [moveOf(const Ship(ShipType.destroyer, row: 5, col: 5))]);
    });

    testWidgets('a tapped square that does not fit is nudged', (tester) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, placing(sent));
      await tapCell(tester, 0); // select the carrier
      await tapCell(tester, 38); // D... would run off the right edge
      final expected = const Ship(
        ShipType.carrier,
        row: 3,
        col: 8,
      ).nudgeToFit(rowsFleet)!;
      expect(expected.fitsAmong(rowsFleet), isTrue);
      expect(sent, [moveOf(expected)]);
    });

    testWidgets('double-tap turns a ship around the tapped square', (
      tester,
    ) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, placing(sent));
      await doubleTapCell(tester, 80);
      expect(sent, [
        moveOf(const Ship(ShipType.destroyer, row: 8, col: 0, vertical: true)),
      ]);
    });

    testWidgets('a turn that does not fit is nudged into place', (
      tester,
    ) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, placing(sent));
      // Turning the carrier around C1 would stick out above the board.
      await doubleTapCell(tester, 2);
      final expected = rowsFleet.first.rotatedAround(2).nudgeToFit(rowsFleet)!;
      expect(expected.vertical, isTrue);
      expect(sent, [moveOf(expected)]);
    });

    testWidgets('Rotate turns the selected ship around its middle', (
      tester,
    ) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, placing(sent));
      await tapCell(tester, 40);
      await tester.tap(find.byKey(const ValueKey('sea-rotate')));
      expect(sent, [
        moveOf(const Ship(ShipType.cruiser, row: 3, col: 1, vertical: true)),
      ]);
    });

    testWidgets('drag a ship by any square to move it', (tester) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, placing(sent));
      final from = tester.getCenter(cell('sea-own', 81)); // destroyer's tail
      final to = tester.getCenter(cell('sea-own', 55));
      await tester.timedDragFrom(
        from,
        to - from,
        const Duration(milliseconds: 300),
      );
      await tester.pump();
      expect(sent, [moveOf(const Ship(ShipType.destroyer, row: 5, col: 4))]);
    });

    testWidgets('a one-square drag works on a small phone', (tester) async {
      final sent = <Json>[];
      await pumpAt(tester, const Size(360, 640), placing(sent));
      final from = tester.getCenter(cell('sea-own', 81));
      final to = tester.getCenter(cell('sea-own', 82));
      expect((to - from).distance, lessThan(36), reason: 'below default slop');
      final gesture = await tester.startGesture(from);
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();
      expect(sent, [moveOf(const Ship(ShipType.destroyer, row: 8, col: 1))]);
    });

    testWidgets('dragging shows a preview, red where it cannot go', (
      tester,
    ) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, placing(sent));
      Color? colorOf(int index) =>
          ((tester.widget<Container>(cell('sea-own', index)).decoration!
                  as BoxDecoration)
              .color);

      // Move in small steps, as a finger does.
      Future<void> glide(TestGesture g, Offset from, Offset to) async {
        for (var i = 1; i <= 10; i++) {
          await g.moveTo(Offset.lerp(from, to, i / 10)!);
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      final start = tester.getCenter(cell('sea-own', 80));
      final over55 = tester.getCenter(cell('sea-own', 55));
      final gesture = await tester.startGesture(start);
      await glide(gesture, start, over55);
      expect(colorOf(55), const Color(0xFF43A047), reason: 'green: fits');
      expect(colorOf(80), isNot(const Color(0xFF90A4AE)), reason: 'lifted');

      await glide(gesture, over55, tester.getCenter(cell('sea-own', 2)));
      expect(
        colorOf(2),
        const Color(0xFFE53935),
        reason: 'red: on the carrier',
      );

      await gesture.up();
      await tester.pump();
      expect(sent, isEmpty, reason: 'an invalid drop sends nothing');
      expect(find.text("The Destroyer doesn't fit there."), findsOneWidget);
      expect(
        colorOf(80),
        const Color(0xFFFFB300),
        reason: 'snapped back, still selected',
      );
    });

    testWidgets('shuffle and ready send their actions', (tester) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, placing(sent));
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('sea-rotate')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('sea-shuffle')));
      await tester.tap(find.byKey(const ValueKey('sea-ready')));
      expect(sent, [
        {'type': 'shuffle'},
        {'type': 'ready'},
      ]);
    });

    testWidgets('a ready fleet is locked until Unready', (tester) async {
      final sent = <Json>[];
      await pumpAt(tester, phone, placing(sent, ready: true));
      expect(find.text('Ready! Waiting for the others…'), findsOneWidget);
      await tapCell(tester, 0);
      await doubleTapCell(tester, 80);
      await tester.dragFrom(
        tester.getCenter(cell('sea-own', 80)),
        const Offset(0, -100),
      );
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
      expect(find.textContaining('Afloat'), findsNothing);
      expect(cell('table-b', 80), findsOneWidget);
    });

    testWidgets('only sunk ships are drawn, as wrecks on moving water', (
      tester,
    ) async {
      final session =
          SeaSiegeSession.custom(
              const [ann, bob],
              fleets: {'a': rowsFleet, 'b': rowsFleet},
              shootAgain: true,
            )
            ..applyAction('a', fire(80))
            ..applyAction('a', fire(81))
            ..applyAction('a', fire(0));
      await pumpScreen(tester, session.tableView());
      final wreck = tester.widget<ShipSprite>(
        find.byKey(const ValueKey('table-b-ship-destroyer')),
      );
      expect(wreck.sunk, isTrue);
      expect(find.byType(ShipSprite), findsOneWidget, reason: 'afloat: hidden');
      expect(find.byType(SeaWater), findsNWidgets(2));
    });

    Future<void> pumpBattle(
      WidgetTester tester,
      Size size, {
      String hostId = 'a',
    }) {
      final session = SeaSiegeSession.custom(
        const [ann, bob],
        fleets: {'a': rowsFleet, 'b': rowsFleet},
      );
      return pumpAt(
        tester,
        size,
        SharedScreenView(
          state: DisplayState(
            lobby: LobbyState(
              roomName: 'Party',
              gameId: 'seasiege',
              players: const [ann, bob],
              minPlayers: 2,
              maxPlayers: 2,
              hostId: hostId,
              hostName: '',
              phase: RoomPhase.playing,
            ),
            gameId: 'seasiege',
            table: session.tableView(),
          ),
        ),
      );
    }

    testWidgets('boards sit side by side in landscape, stacked in portrait', (
      tester,
    ) async {
      Axis direction() => tester
          .widget<Flex>(find.byKey(const ValueKey('sea-boards')))
          .direction;
      await pumpBattle(tester, const Size(1920, 1080));
      expect(direction(), Axis.horizontal);
      await pumpBattle(tester, const Size(1080, 1920));
      expect(tester.takeException(), isNull);
      expect(direction(), Axis.vertical);
    });

    testWidgets('both boards are the same size at any width', (tester) async {
      final session =
          SeaSiegeSession.custom(
              const [ann, bob],
              fleets: {'a': rowsFleet, 'b': rowsFleet},
              shootAgain: true,
            )
            ..applyAction('a', fire(80))
            ..applyAction('a', fire(81));
      // Ann has lost a ship and Bob hasn't; their boards still match.
      for (var width = 1000.0; width <= 2400; width += 100) {
        await pumpAt(
          tester,
          Size(width, 800),
          SharedScreenView(
            state: DisplayState(
              lobby: lobby,
              gameId: 'seasiege',
              table: session.tableView(),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(cell('table-a', 0)),
          tester.getSize(cell('table-b', 0)),
          reason: 'at $width px wide',
        );
      }
    });

    testWidgets("the host's board comes first", (tester) async {
      Offset at(String text) => tester.getCenter(find.text(text));
      await pumpBattle(tester, const Size(1920, 1080), hostId: 'b');
      expect(at("Bob's fleet").dx, lessThan(at("Ann's fleet").dx));
      await pumpBattle(tester, const Size(1080, 1920), hostId: 'b');
      expect(at("Bob's fleet").dy, lessThan(at("Ann's fleet").dy));
      await pumpBattle(tester, const Size(1920, 1080));
      expect(at("Ann's fleet").dx, lessThan(at("Bob's fleet").dx));
    });
  });

  testWidgets('players see their own fleet as sprites on moving water', (
    tester,
  ) async {
    final session =
        SeaSiegeSession.custom(
            const [ann, bob],
            fleets: {'a': rowsFleet, 'b': rowsFleet},
            turn: 'b',
            shootAgain: true,
          )
          ..applyAction('b', fire(80))
          ..applyAction('b', fire(81));
    await pumpAt(tester, phone, viewOf(session));
    for (final type in ShipType.values) {
      expect(find.byKey(ValueKey('sea-own-ship-${type.name}')), findsOneWidget);
    }
    expect(
      tester
          .widget<ShipSprite>(
            find.byKey(const ValueKey('sea-own-ship-destroyer')),
          )
          .sunk,
      isTrue,
    );
    expect(find.byKey(const ValueKey('sea-enemy-ship-carrier')), findsNothing);
    expect(find.byType(SeaWater), findsNWidgets(2));
  });
}

Json fire(int cell) => {'type': 'fire', 'cell': cell};
