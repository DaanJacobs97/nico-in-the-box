import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/color_clash/color_clash_game.dart';
import 'package:nico_shared/games/color_clash/color_clash_view.dart';
import 'package:nico_shared/games/game_views.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_game.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_view.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/shared_screen_view.dart';
import 'package:nico_shared/widgets/display_settings_editor.dart';

const ann = PlayerInfo(id: 'a', nickname: 'Ann');
const bob = PlayerInfo(id: 'b', nickname: 'Bob');

LobbyState lobbyOf(
  String gameId, {
  RoomPhase phase = RoomPhase.playing,
  int max = 2,
}) => LobbyState(
  roomName: 'Party',
  gameId: gameId,
  players: const [ann, bob],
  minPlayers: 2,
  maxPlayers: max,
  hostId: 'a',
  hostName: 'Ann',
  phase: phase,
);

Future<void> pumpBig(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('Color Clash player view', () {
    final session = ColorClashSession(const [ann, bob], random: Random(5));

    Widget view({required bool compact, List<Json>? sent}) => ColorClashView(
      ctx: GameViewContext(
        view: session.viewFor('a'),
        myId: 'a',
        lobby: lobbyOf('colorclash', max: 4),
        sendAction: (action) => sent?.add(action),
        compact: compact,
      ),
    );

    testWidgets('full view shows the table', (tester) async {
      await pumpBig(tester, view(compact: false));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('draw-pile')), findsOneWidget);
      expect(find.textContaining('Bob · 7'), findsOneWidget);
      expect(find.byKey(const ValueKey('compact-status')), findsNothing);
    });

    testWidgets('compact view keeps only status, buttons and hand', (
      tester,
    ) async {
      final sent = <Json>[];
      await pumpBig(tester, view(compact: true, sent: sent));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('draw-pile')), findsNothing);
      expect(find.textContaining('Bob · 7'), findsNothing);
      expect(find.text('Your turn!'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('hand-card-'),
        ),
        findsNWidgets(7),
      );

      await tester.tap(find.byKey(const ValueKey('draw-button')));
      expect(sent, [
        {'type': 'draw'},
      ]);
    });
  });

  testWidgets('Color Clash table shows counts and no hand', (tester) async {
    final session = ColorClashSession(const [ann, bob], random: Random(9));
    await pumpBig(
      tester,
      ColorClashTable(
        ctx: TableContext(
          table: session.tableView(),
          lobby: lobbyOf('colorclash'),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Ann · 7'), findsOneWidget);
    expect(find.textContaining('Bob · 7'), findsOneWidget);
    expect(find.text("Ann's turn"), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('hand-card-'),
      ),
      findsNothing,
    );
  });

  testWidgets('Tic Tac Toe table names X and O and the winner', (tester) async {
    final game = TicTacToeSession(const [ann, bob]);
    for (final (who, cell) in [
      ('a', 0),
      ('b', 3),
      ('a', 1),
      ('b', 4),
      ('a', 2),
    ]) {
      game.applyAction(who, {'type': 'place', 'cell': cell});
    }
    await pumpBig(
      tester,
      TicTacToeTable(
        ctx: TableContext(table: game.tableView(), lobby: lobbyOf('tictactoe')),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('X  Ann   vs   Bob  O'), findsOneWidget);
    expect(find.text('Ann wins!'), findsOneWidget);
  });

  group('SharedScreenView', () {
    testWidgets('waits for the first update', (tester) async {
      await pumpBig(tester, const SharedScreenView(state: null));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('lobby lists players and free seats', (tester) async {
      await pumpBig(
        tester,
        SharedScreenView(
          state: DisplayState(
            lobby: lobbyOf('colorclash', phase: RoomPhase.lobby, max: 4),
          ),
        ),
      );
      expect(find.text('Party'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Free seat'), findsNWidgets(2));
    });

    testWidgets('game shows the table, then the result', (tester) async {
      final game = TicTacToeSession(const [ann, bob]);
      await pumpBig(
        tester,
        SharedScreenView(
          state: DisplayState(
            lobby: lobbyOf('tictactoe'),
            gameId: 'tictactoe',
            table: game.tableView(),
          ),
        ),
      );
      expect(find.byType(TicTacToeTable), findsOneWidget);
      expect(find.textContaining('Waiting for the host'), findsNothing);

      await pumpBig(
        tester,
        SharedScreenView(
          state: DisplayState(
            lobby: lobbyOf('tictactoe', phase: RoomPhase.finished),
            gameId: 'tictactoe',
            table: game.tableView(),
            result: const {'summary': 'Ann wins!'},
          ),
        ),
      );
      expect(find.text('🎉 Ann wins!'), findsOneWidget);
      expect(find.text('Waiting for the host…'), findsOneWidget);
    });
  });

  group('DisplaySettingsEditor', () {
    testWidgets('switch and screen choice update the settings', (tester) async {
      var value = DisplaySettings.off;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => DisplaySettingsEditor(
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Where is the shared screen?'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('single-screen-switch')));
      await tester.pumpAndSettle();
      expect(value.enabled, isTrue);
      expect(ScreenChoice.of(value), ScreenChoice.browser);

      await tester.tap(find.text('This device'));
      await tester.pumpAndSettle();
      expect(value.hostIsScreen, isTrue);

      // The Caster isn't available yet, so tapping it changes nothing.
      await tester.tap(find.text('Caster (soon)'));
      await tester.pumpAndSettle();
      expect(ScreenChoice.of(value), ScreenChoice.thisDevice);

      // Turning the screen off seats the host again.
      await tester.tap(find.byKey(const ValueKey('single-screen-switch')));
      await tester.pumpAndSettle();
      expect(value.hostIsScreen, isFalse);
    });
  });
}
