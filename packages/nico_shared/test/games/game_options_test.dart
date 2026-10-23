import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/widgets/game_options_editor.dart';

class _NoSession implements GameSession {
  @override
  void applyAction(String playerId, Json action) {}
  @override
  Json viewFor(String playerId) => {};
  @override
  Json tableView() => {};
  @override
  bool get isOver => false;
  @override
  Json? get result => null;
}

final game = GameDefinition(
  id: 'opts',
  name: 'Options',
  description: 'Test game.',
  minPlayers: 2,
  maxPlayers: 2,
  category: GameCategory.board,
  options: const [
    GameOption(
      id: 'again',
      label: 'Hit = shoot again',
      description: 'A hit earns another shot.',
    ),
    GameOption(id: 'fog', label: 'Fog', defaultValue: true),
    GameOption.choice(
      id: 'size',
      label: 'Board size',
      choices: [GameChoice('small', 'Small'), GameChoice('large', 'Large')],
      defaultChoice: 'small',
    ),
  ],
  createSession: (_, _, _, _) => _NoSession(),
);

void main() {
  group('GameDefinition options', () {
    test('defaults and text', () {
      expect(game.defaultOptions, {
        'again': false,
        'fog': true,
        'size': 'small',
      });
      expect(game.describeOptions(game.defaultOptions), [
        'Hit = shoot again: off',
        'Fog: on',
        'Board size: Small',
      ]);
      expect(game.options.last.isChoice, isTrue);
      expect(game.options.first.isChoice, isFalse);
    });

    test('updateOptions applies changes and keeps the rest', () {
      expect(
        game.updateOptions(game.defaultOptions, {
          'fog': false,
          'size': 'large',
        }),
        {'again': false, 'fog': false, 'size': 'large'},
      );
      // Missing values (e.g. from an older lobby) fall back to defaults.
      expect(game.updateOptions({}, {'again': true}), {
        'again': true,
        'fog': true,
        'size': 'small',
      });
    });

    test('updateOptions rejects bad input', () {
      for (final bad in <Object?>[
        {'nope': true},
        {'again': 'yes'},
        {'again': 1},
        {'size': 'huge'},
        {'size': true},
        {'size': null},
        ['again'],
        null,
      ]) {
        expect(
          () => game.updateOptions(game.defaultOptions, bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('lobby and display state carry options over the wire', () {
      const lobby = LobbyState(
        roomName: 'R',
        gameId: 'opts',
        players: [],
        minPlayers: 2,
        maxPlayers: 2,
        hostId: null,
        phase: RoomPhase.lobby,
        gameOptions: {'again': true, 'size': 'large'},
      );
      final back = DisplayState.fromJson(
        DisplayState(
          lobby: lobby,
          gameName: 'Options',
          rules: const ['Hit = shoot again: on'],
        ).toJson(),
      );
      expect(back.lobby.gameOptions, {'again': true, 'size': 'large'});
      expect(back.gameName, 'Options');
      expect(back.rules, ['Hit = shoot again: on']);
    });
  });

  test('engines read switches and choices with fallbacks', () {
    const GameOptions options = {'again': true, 'size': 'large'};
    expect(options.flag('again'), isTrue);
    expect(options.flag('missing'), isFalse);
    expect(options.choice('size', 'small'), 'large');
    expect(options.choice('missing', 'small'), 'small');
    expect(options.choice('again', 'small'), 'small', reason: 'not a choice');
  });

  group('GameOptionsEditor', () {
    Future<void> pump(WidgetTester tester, Widget child) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

    testWidgets('host flips a switch', (tester) async {
      final changes = <GameOptions>[];
      await pump(
        tester,
        GameOptionsEditor(
          game: game,
          values: game.defaultOptions,
          onChanged: changes.add,
        ),
      );
      expect(find.text('A hit earns another shot.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('game-option-again')));
      expect(changes, [
        {'again': true},
      ]);
    });

    testWidgets('host picks a choice', (tester) async {
      final changes = <GameOptions>[];
      await pump(
        tester,
        GameOptionsEditor(
          game: game,
          values: game.defaultOptions,
          onChanged: changes.add,
        ),
      );
      expect(find.text('Board size'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('game-option-size-large')));
      expect(changes, [
        {'size': 'large'},
      ]);
    });

    testWidgets('players see the rules read-only', (tester) async {
      await pump(
        tester,
        GameOptionsEditor(game: game, values: const {'again': true}),
      );
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Hit = shoot again'), findsOneWidget);
      expect(find.text('On'), findsNWidgets(2)); // 'fog' defaults to on.
      expect(find.text('Small'), findsOneWidget, reason: 'the default choice');
      expect(find.byType(SegmentedButton<String>), findsNothing);
    });
  });
}
