import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_game.dart';
import 'package:nico_shared/net/protocol.dart';

const host = PlayerInfo(id: 'h', nickname: 'Host');
const guest = PlayerInfo(id: 'g', nickname: 'Guest');

void place(GameSession game, String playerId, int cell) =>
    game.applyAction(playerId, {'type': 'place', 'cell': cell});

void main() {
  test('first player is X and moves first on round 0', () {
    final game = TicTacToeSession([host, guest]);
    final view = game.viewFor('h');
    expect(view['marks'], {'h': 'X', 'g': 'O'});
    expect(view['turn'], 'h');
  });

  test('marks swap on odd rounds so the opener alternates', () {
    final game = TicTacToeSession([host, guest], round: 1);
    expect(game.viewFor('h')['marks'], {'g': 'X', 'h': 'O'});
    expect(game.viewFor('h')['turn'], 'g');
  });

  test('rejects moves out of turn, on taken squares and off the board', () {
    final game = TicTacToeSession([host, guest]);
    expect(() => place(game, 'g', 0), throwsA(isA<GameActionException>()));
    place(game, 'h', 4);
    expect(() => place(game, 'g', 4), throwsA(isA<GameActionException>()));
    expect(() => place(game, 'g', 9), throwsA(isA<GameActionException>()));
    expect(
      () => game.applyAction('g', {'type': 'place', 'cell': '1'}),
      throwsA(isA<GameActionException>()),
    );
    expect(
      () => place(game, 'stranger', 0),
      throwsA(isA<GameActionException>()),
    );
  });

  test('detects a win and reports the winner', () {
    final game = TicTacToeSession([host, guest]);
    for (final (player, cell) in [
      ('h', 0),
      ('g', 3),
      ('h', 1),
      ('g', 4),
      ('h', 2),
    ]) {
      place(game, player, cell);
    }
    expect(game.isOver, isTrue);
    final view = game.viewFor('g');
    expect(view['winner'], 'h');
    expect(view['winLine'], [0, 1, 2]);
    expect(view['turn'], isNull);
    expect(game.result, {
      'winnerIds': ['h'],
      'summary': 'Host wins!',
    });
    expect(() => place(game, 'g', 5), throwsA(isA<GameActionException>()));
  });

  test('detects a draw', () {
    final game = TicTacToeSession([host, guest]);
    // X O X / X O O / O X X
    for (final (player, cell) in [
      ('h', 0),
      ('g', 1),
      ('h', 2),
      ('g', 4),
      ('h', 3),
      ('g', 5),
      ('h', 7),
      ('g', 6),
      ('h', 8),
    ]) {
      place(game, player, cell);
    }
    expect(game.isOver, isTrue);
    expect(game.viewFor('h')['draw'], isTrue);
    expect(game.result!['winnerIds'], isEmpty);
  });

  test('table view shows the same board as the players see', () {
    final game = TicTacToeSession([host, guest]);
    place(game, 'h', 4);
    expect(game.tableView(), game.viewFor('h'));
    expect((game.tableView()['board']! as List<Object?>)[4], 'X');
  });

  test('definition creates a session that honours the round', () {
    final game = ticTacToeDefinition.createSession(
      [host, guest],
      3,
      Random(1),
      const {},
    );
    expect(game.viewFor('h')['turn'], 'g');
  });
}
