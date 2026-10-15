import 'dart:math';

import '../../net/protocol.dart';
import '../game_session.dart';

const ticTacToeDefinition = GameDefinition(
  id: 'tictactoe',
  name: 'Tic Tac Toe',
  description: 'Three in a row wins. Host versus one challenger.',
  minPlayers: 2,
  maxPlayers: 2,
  createSession: _create,
);

GameSession _create(
  List<PlayerInfo> players,
  int round,
  Random random,
  GameOptions options,
) => TicTacToeSession(players, round: round);

const _lines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
  [0, 3, 6], [1, 4, 7], [2, 5, 8], // columns
  [0, 4, 8], [2, 4, 6], // diagonals
];

/// Actions: `{'type': 'place', 'cell': 0..8}`.
///
/// The first player in join order is X on even rounds and O on odd rounds,
/// so the opening move alternates between rematches. X always moves first.
class TicTacToeSession implements GameSession {
  TicTacToeSession(List<PlayerInfo> players, {int round = 0})
    : assert(players.length == 2),
      _players = players,
      _xId = players[round.isEven ? 0 : 1].id,
      _oId = players[round.isEven ? 1 : 0].id;

  final List<PlayerInfo> _players;
  final String _xId;
  final String _oId;
  final List<String?> _board = List.filled(9, null);
  String _turn = 'X';
  String? _winnerMark;
  List<int>? _winLine;

  String _markOf(String playerId) => playerId == _xId ? 'X' : 'O';
  String _idOf(String mark) => mark == 'X' ? _xId : _oId;

  bool get _isDraw => _winnerMark == null && !_board.contains(null);

  @override
  bool get isOver => _winnerMark != null || _isDraw;

  @override
  void applyAction(String playerId, Json action) {
    if (playerId != _xId && playerId != _oId) {
      throw const GameActionException('You are not playing this game.');
    }
    if (isOver) throw const GameActionException('The game is over.');
    if (action['type'] != 'place') {
      throw const GameActionException('Unknown move.');
    }
    final cell = action['cell'];
    if (cell is! int || cell < 0 || cell > 8) {
      throw const GameActionException('Pick a square on the board.');
    }
    if (_markOf(playerId) != _turn) {
      throw const GameActionException("It's not your turn.");
    }
    if (_board[cell] != null) {
      throw const GameActionException('That square is taken.');
    }

    _board[cell] = _turn;
    for (final line in _lines) {
      final a = _board[line[0]];
      if (a != null && a == _board[line[1]] && a == _board[line[2]]) {
        _winnerMark = a;
        _winLine = line;
        return;
      }
    }
    _turn = _turn == 'X' ? 'O' : 'X';
  }

  /// Nothing is hidden in Tic Tac Toe, so every view is the table view.
  @override
  Json viewFor(String playerId) => tableView();

  @override
  Json tableView() => {
    'board': List.of(_board),
    'marks': {_xId: 'X', _oId: 'O'},
    'turn': isOver ? null : _idOf(_turn),
    'winner': _winnerMark == null ? null : _idOf(_winnerMark!),
    'winLine': _winLine,
    'draw': _isDraw,
  };

  @override
  Json? get result {
    if (!isOver) return null;
    if (_winnerMark == null) {
      return {'winnerIds': <String>[], 'summary': "It's a draw!"};
    }
    final winnerId = _idOf(_winnerMark!);
    final name = _players.firstWhere((p) => p.id == winnerId).nickname;
    return {
      'winnerIds': [winnerId],
      'summary': '$name wins!',
    };
  }
}
