import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/game_views.dart';
import 'package:nico_shared/games/tacticalvoxelrpg/tacticalvoxelrpg_game.dart';
import 'package:nico_shared/games/tacticalvoxelrpg/tacticalvoxelrpg_map.dart';
import 'package:nico_shared/games/tacticalvoxelrpg/tacticalvoxelrpg_view.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/shared_screen_view.dart';

const vera = PlayerInfo(id: 'p1', nickname: 'Vera');

const lobby = LobbyState(
  roomName: 'Party',
  gameId: 'tacticalvoxelrpg',
  players: [vera],
  minPlayers: 1,
  maxPlayers: 6,
  hostId: 'p1',
  hostName: 'Vera',
  phase: RoomPhase.playing,
);

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('mobile view shows three units, energy and route controls', (
    tester,
  ) async {
    final session = TacticalVoxelRPGSession([vera], random: Random(4));
    await pumpAt(
      tester,
      const Size(400, 800),
      TacticalVoxelRPGView(
        ctx: GameViewContext(
          view: session.viewFor('p1'),
          myId: 'p1',
          lobby: lobby,
          sendAction: (_) {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Your turn · choose an available unit'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tacticalvoxelrpg-cell-3-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tacticalvoxelrpg-activate-p1-closeCombat')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tacticalvoxelrpg-pan-map')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tacticalvoxelrpg-zoom-in')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tacticalvoxelrpg-zoom-out')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tacticalvoxelrpg-zoom-reset')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tacticalvoxelrpg-zoom-in')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tacticalvoxelrpg-zoom-reset')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('tacticalvoxelrpg-end-turn')),
      findsOneWidget,
    );
  });

  testWidgets('end turn sends the action', (tester) async {
    final sent = <Json>[];
    final session = TacticalVoxelRPGSession([vera], random: Random(4));
    await pumpAt(
      tester,
      const Size(400, 800),
      TacticalVoxelRPGView(
        ctx: GameViewContext(
          view: {...session.viewFor('p1'), 'canEndTurn': true},
          myId: 'p1',
          lobby: lobby,
          sendAction: sent.add,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('tacticalvoxelrpg-end-turn')));
    expect(sent, [
      {'type': 'endTurn'},
    ]);
  });

  testWidgets('unit travels through its route over visible time', (
    tester,
  ) async {
    final session = TacticalVoxelRPGSession([vera], random: Random(4));
    TacticalVoxelRPGView view() => TacticalVoxelRPGView(
      ctx: GameViewContext(
        view: session.viewFor('p1'),
        myId: 'p1',
        lobby: lobby,
        sendAction: (_) {},
      ),
    );
    await pumpAt(tester, const Size(400, 800), view());
    session.applyAction('p1', {'type': 'selectUnit', 'unit': 'p1-closeCombat'});
    final hand =
        (session.viewFor('p1')['units']! as List<Object?>)
                .cast<Json>()
                .firstWhere((unit) => unit['id'] == 'p1-closeCombat')['hand']
            as List<Object?>;
    final strides = hand.cast<Json>().firstWhere(
      (card) => card['kind'] == 'move',
    );
    session
      ..applyAction('p1', {
        'type': 'planRoute',
        'unit': 'p1-closeCombat',
        'path': [
          const GridPoint(4, 3).toJson(),
          const GridPoint(4, 4).toJson(),
        ],
      })
      ..applyAction('p1', {
        'type': 'playCard',
        'unit': 'p1-closeCombat',
        'cardId': strides['id'],
      });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: view())));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 120));
    final actor = find.byKey(
      const ValueKey('tacticalvoxelrpg-sprite-p1-closeCombat'),
    );
    final start = tester.getCenter(
      find.byKey(const ValueKey('tacticalvoxelrpg-cell-3-3')),
    );
    final waypoint = tester.getCenter(
      find.byKey(const ValueKey('tacticalvoxelrpg-cell-4-3')),
    );
    final moving = tester.getCenter(actor);
    expect(moving.dx, greaterThan(start.dx));
    expect(moving.dx, lessThan(waypoint.dx));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tacticalvoxelrpg-cell-4-4')),
        matching: find.text('V'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('batched enemy movements animate one after another', (
    tester,
  ) async {
    final session = TacticalVoxelRPGSession([vera], random: Random(4));
    final initial = session.viewFor('p1');
    final units = (initial['units']! as List<Object?>).cast<Json>();
    final enemies = units
        .where((unit) => unit['owner'] == tacticalAiId)
        .toList();
    final first = enemies[0];
    final second = enemies[1];
    final firstFrom = GridPoint(first['x']! as int, first['y']! as int);
    final secondFrom = GridPoint(second['x']! as int, second['y']! as int);
    final firstTo = GridPoint(firstFrom.x - 1, firstFrom.y);
    final secondTo = GridPoint(secondFrom.x - 1, secondFrom.y);
    final actions = <Json>[
      {
        'event': 1,
        'type': 'move',
        'unit': first['id'],
        'from': firstFrom.toJson(),
        'x': firstTo.x,
        'y': firstTo.y,
        'path': [firstTo.toJson()],
      },
      {
        'event': 2,
        'type': 'move',
        'unit': second['id'],
        'from': secondFrom.toJson(),
        'x': secondTo.x,
        'y': secondTo.y,
        'path': [secondTo.toJson()],
      },
    ];
    final finalUnits = [
      for (final unit in units)
        if (unit['id'] == first['id'])
          {...unit, 'x': firstTo.x, 'y': firstTo.y}
        else if (unit['id'] == second['id'])
          {...unit, 'x': secondTo.x, 'y': secondTo.y}
        else
          unit,
    ];
    final updated = <String, Object?>{
      ...initial,
      'units': finalUnits,
      'recentActions': actions,
      'lastAction': actions.last,
    };
    TacticalVoxelRPGView view(Json state) => TacticalVoxelRPGView(
      ctx: GameViewContext(
        view: state,
        myId: 'p1',
        lobby: lobby,
        sendAction: (_) {},
      ),
    );

    await pumpAt(tester, const Size(400, 800), view(initial));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: view(updated))));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 120));
    final firstSprite = tester.getCenter(
      find.byKey(ValueKey('tacticalvoxelrpg-sprite-${first['id']}')),
    );
    final firstStart = tester.getCenter(
      find.byKey(
        ValueKey('tacticalvoxelrpg-cell-${firstFrom.x}-${firstFrom.y}'),
      ),
    );
    final firstDestination = tester.getCenter(
      find.byKey(ValueKey('tacticalvoxelrpg-cell-${firstTo.x}-${firstTo.y}')),
    );
    final secondSprite = tester.getCenter(
      find.byKey(ValueKey('tacticalvoxelrpg-sprite-${second['id']}')),
    );
    final secondStart = tester.getCenter(
      find.byKey(
        ValueKey('tacticalvoxelrpg-cell-${secondFrom.x}-${secondFrom.y}'),
      ),
    );
    expect(firstSprite.dx, lessThan(firstStart.dx));
    expect(firstSprite.dx, greaterThan(firstDestination.dx));
    expect(secondSprite.dx, closeTo(secondStart.dx, 1));

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 120));
    final secondDestination = tester.getCenter(
      find.byKey(ValueKey('tacticalvoxelrpg-cell-${secondTo.x}-${secondTo.y}')),
    );
    final secondMoving = tester.getCenter(
      find.byKey(ValueKey('tacticalvoxelrpg-sprite-${second['id']}')),
    );
    expect(secondMoving.dx, lessThan(secondStart.dx));
    expect(secondMoving.dx, greaterThan(secondDestination.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('route mode drags a path without panning the battlefield', (
    tester,
  ) async {
    final sent = <Json>[];
    final session = TacticalVoxelRPGSession([vera], random: Random(4));
    Widget view() => TacticalVoxelRPGView(
      ctx: GameViewContext(
        view: session.viewFor('p1'),
        myId: 'p1',
        lobby: lobby,
        sendAction: (action) {
          sent.add(action);
          session.applyAction('p1', action);
        },
      ),
    );
    await pumpAt(tester, const Size(400, 800), view());
    await tester.tap(find.byKey(const ValueKey('tacticalvoxelrpg-cell-3-3')));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: view())));
    await tester.tap(find.text('Strides').first);
    await tester.pump();
    expect(
      find.text('Drag across the map to plot the active unit’s Strides route'),
      findsOneWidget,
    );
    final from = tester.getCenter(
      find.byKey(const ValueKey('tacticalvoxelrpg-cell-3-3')),
    );
    final to = tester.getCenter(
      find.byKey(const ValueKey('tacticalvoxelrpg-cell-4-3')),
    );
    await tester.timedDragFrom(
      from,
      to - from,
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect(sent, [
      {'type': 'selectUnit', 'unit': 'p1-closeCombat'},
      {
        'type': 'planRoute',
        'unit': 'p1-closeCombat',
        'path': [const GridPoint(4, 3).toJson()],
      },
    ]);
  });

  testWidgets('shared screen shows the room map and active battle', (
    tester,
  ) async {
    final session = TacticalVoxelRPGSession([vera], random: Random(6));
    await pumpAt(
      tester,
      const Size(1920, 1080),
      SharedScreenView(
        state: DisplayState(
          lobby: lobby,
          gameId: 'tacticalvoxelrpg',
          table: session.tableView(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Vera’s turn'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tacticalvoxelrpg-cell-3-3')),
      findsOneWidget,
    );
  });

  testWidgets('enemy sprites load and animate on the shared battlefield', (
    tester,
  ) async {
    final session = TacticalVoxelRPGSession([vera], random: Random(6));
    final table = session.tableView();
    final enemy = (table['units']! as List<Object?>).cast<Json>().firstWhere(
      (unit) => unit['owner'] == tacticalAiId,
    );
    await pumpAt(
      tester,
      const Size(1920, 1080),
      SharedScreenView(
        state: DisplayState(
          lobby: lobby,
          gameId: 'tacticalvoxelrpg',
          table: table,
        ),
      ),
    );
    expect(find.byType(Image), findsAtLeastNWidgets(3));
    final spriteFinder = find.byKey(
      ValueKey('tacticalvoxelrpg-sprite-${enemy['id']}'),
    );
    final cellFinder = find.byKey(
      ValueKey('tacticalvoxelrpg-cell-${enemy['x']}-${enemy['y']}'),
    );
    final spriteRect = tester.getRect(spriteFinder);
    final cellRect = tester.getRect(cellFinder);
    final spriteSize = tester.getSize(spriteFinder);
    expect(spriteSize.width, greaterThan(cellRect.width * 1.5));
    expect((spriteRect.center.dx - cellRect.center.dx).abs(), lessThan(1));
    expect(
      (spriteRect.top + spriteRect.height * 120 / 128 - cellRect.bottom).abs(),
      lessThan(1),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
  });
}
