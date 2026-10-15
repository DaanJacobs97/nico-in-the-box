import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/main.dart';
import 'package:nico_in_the_box/screens/join_screen.dart';
import 'package:nico_shared/games/color_clash/color_clash_game.dart';
import 'package:nico_shared/games/color_clash/color_clash_view.dart';
import 'package:nico_shared/games/game_views.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_view.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/widgets/nickname_dialog.dart';

const _lobby = LobbyState(
  roomName: 'r',
  gameId: 'tictactoe',
  players: [
    PlayerInfo(id: 'h', nickname: 'Nico'),
    PlayerInfo(id: 'g', nickname: 'Daan'),
  ],
  minPlayers: 2,
  maxPlayers: 2,
  hostId: 'h',
  phase: RoomPhase.playing,
);

void main() {
  testWidgets('home screen offers host and join', (tester) async {
    await tester.pumpWidget(const NicoInTheBoxApp());
    expect(find.text('Nico in the Box'), findsOneWidget);
    expect(find.text('Host a game'), findsOneWidget);
    expect(find.text('Join a game'), findsOneWidget);
  });

  testWidgets('nickname dialog validates and returns the trimmed name', (
    tester,
  ) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showNicknameDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Join'));
    await tester.pump();
    expect(find.textContaining('Use 1–'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  Nico  ');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(result, 'Nico');
  });

  testWidgets('tic tac toe view sends a place action on my turn', (
    tester,
  ) async {
    final sent = <Json>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicTacToeView(
            ctx: GameViewContext(
              view: {
                'board': List<String?>.filled(9, null),
                'marks': {'h': 'X', 'g': 'O'},
                'turn': 'h',
                'winner': null,
                'winLine': null,
                'draw': false,
              },
              myId: 'h',
              lobby: _lobby,
              sendAction: sent.add,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Your turn (X)'), findsOneWidget);
    await tester.tap(find.byType(InkWell).at(4));
    expect(sent, [
      {'type': 'place', 'cell': 4},
    ]);
  });

  testWidgets('color clash view renders a real hand and plays a card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = ColorClashSession(const [
      PlayerInfo(id: 'h', nickname: 'Nico'),
      PlayerInfo(id: 'g', nickname: 'Daan'),
    ], random: Random(5));
    final view = session.viewFor('h');
    final sent = <Json>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorClashView(
            ctx: GameViewContext(
              view: view,
              myId: 'h',
              lobby: _lobby,
              sendAction: sent.add,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Your turn!'), findsOneWidget);
    expect(find.text('Draw (${view['drawPile']})'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.style));
    expect(sent.last, {'type': 'draw'});
  });

  test('manual address parsing', () {
    expect(parseManualAddress('192.168.1.20'), ('192.168.1.20', kGamePort));
    expect(parseManualAddress(' 10.0.0.2:5000 '), ('10.0.0.2', 5000));
    expect(parseManualAddress(''), isNull);
    expect(parseManualAddress('10.0.0.2:abc'), isNull);
    expect(parseManualAddress('10.0.0.2:70000'), isNull);
    // The Caster's address defaults to the Caster port.
    expect(parseManualAddress('10.0.0.5', defaultPort: kCasterPort), (
      '10.0.0.5',
      kCasterPort,
    ));
  });
}
