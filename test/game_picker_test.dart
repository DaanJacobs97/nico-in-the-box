import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/net/game_server.dart';
import 'package:nico_in_the_box/screens/host_setup_screen.dart';
import 'package:nico_shared/games/blackjack/blackjack_game.dart';
import 'package:nico_shared/games/color_clash/color_clash_game.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/games/registry.dart';
import 'package:nico_shared/games/seasiege/seasiege_game.dart';
import 'package:nico_shared/games/tacticalvoxelrpg/tacticalvoxelrpg_game.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_game.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/screens/lobby_view.dart';
import 'package:nico_shared/widgets/game_category_header.dart';

Future<void> until(GameClient client, bool Function() condition) {
  if (condition()) return Future.value();
  final done = Completer<void>();
  void check() {
    if (!done.isCompleted && condition()) done.complete();
  }

  client.addListener(check);
  return done.future
      .timeout(const Duration(seconds: 15))
      .whenComplete(() => client.removeListener(check));
}

GameDefinition fake(String id, GameCategory category) => GameDefinition(
  id: id,
  name: id,
  description: '',
  minPlayers: 2,
  maxPlayers: 2,
  category: category,
  createSession: (players, round, random, options) =>
      throw UnimplementedError(),
);

void main() {
  group('categories', () {
    test('the games are grouped as decided, empty categories left out', () {
      expect(
        [
          for (final (category, games) in gamesByCategory())
            '${category.name}: ${games.map((g) => g.id).join(', ')}',
        ],
        [
          'card: colorclash',
          'grid: tictactoe, seasiege',
          'gambling: blackjack',
          'adventure: tacticalvoxelrpg',
        ],
      );
    });

    test('categories come in enum order, games in list order', () {
      final games = [
        fake('slots', GameCategory.gambling),
        fake('chess', GameCategory.board),
        fake('poker', GameCategory.card),
        fake('go', GameCategory.board),
      ];
      expect(
        [
          for (final (category, inCategory) in gamesByCategory(games))
            '${category.name}: ${inCategory.map((g) => g.id).join(', ')}',
        ],
        ['card: poker', 'board: chess, go', 'gambling: slots'],
      );
    });

    test('every category has its own name and icon', () {
      const values = GameCategory.values;
      expect(values.map((c) => c.label).toSet(), hasLength(values.length));
      expect(values.map(gameCategoryIcon).toSet(), hasLength(values.length));
      expect(values.every((c) => c.label.endsWith(' games')), isTrue);
    });
  });

  testWidgets('host setup lists the games under their category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HostSetupScreen()));
    await tester.pumpAndSettle();

    Finder header(GameCategory c) => find.byKey(ValueKey('category-${c.name}'));
    Finder tile(GameDefinition g) => find.byKey(ValueKey('pick-game-${g.id}'));
    expect(header(GameCategory.board), findsNothing);

    // Top to bottom: each header, then its games.
    final order = [
      header(GameCategory.card),
      tile(colorClashDefinition),
      header(GameCategory.grid),
      tile(ticTacToeDefinition),
      tile(seaSiegeDefinition),
      header(GameCategory.gambling),
      tile(blackjackDefinition),
      header(GameCategory.adventure),
      tile(tacticalVoxelRPGDefinition),
    ];
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, orderedEquals([...tops]..sort()));

    GameDefinition picked() => tester
        .widget<RadioGroup<GameDefinition>>(
          find.byType(RadioGroup<GameDefinition>),
        )
        .groupValue!;
    expect(picked(), ticTacToeDefinition, reason: 'still the default');
    await tester.tap(tile(seaSiegeDefinition));
    await tester.pump();
    expect(picked(), seaSiegeDefinition);
  });

  testWidgets('the lobby menu groups games and headers do nothing', (
    tester,
  ) async {
    final server = GameServer(roomName: 'Room', game: ticTacToeDefinition);
    late GameClient host;
    await tester.runAsync(() async {
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
      host = await GameClient.connect(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        nickname: 'Ann',
        hostToken: server.hostToken,
      );
      await until(host, () => host.lobby != null);
    });
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LobbyView(client: host)),
      ),
    );

    await tester.tap(find.byTooltip('Change game'));
    await tester.pumpAndSettle();
    Finder menuHeader(GameCategory c) =>
        find.byKey(ValueKey('menu-category-${c.name}'));
    for (final c in [
      GameCategory.card,
      GameCategory.grid,
      GameCategory.gambling,
      GameCategory.adventure,
    ]) {
      expect(menuHeader(c), findsOneWidget);
    }
    expect(menuHeader(GameCategory.board), findsNothing);
    expect(
      tester.getTopLeft(menuHeader(GameCategory.grid)).dy,
      lessThan(tester.getTopLeft(find.text('Sea Siege (2 players)')).dy),
    );

    // A header is not a choice: the menu stays open, the game unchanged.
    await tester.tap(menuHeader(GameCategory.card));
    await tester.pumpAndSettle();
    expect(find.text('Sea Siege (2 players)'), findsOneWidget);

    await tester.tap(find.text('Sea Siege (2 players)'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => until(host, () => host.lobby!.gameId == seaSiegeDefinition.id),
    );
    expect(server.game.id, seaSiegeDefinition.id);

    await tester.runAsync(() async {
      await host.leave();
      await server.close();
    });
  });
}
