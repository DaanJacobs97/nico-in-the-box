import 'dart:math';

import '../net/protocol.dart';

/// Thrown by [GameSession.applyAction] when a move is not allowed.
/// The message is shown to the player who made it.
class GameActionException implements Exception {
  const GameActionException(this.message);

  final String message;

  @override
  String toString() => 'GameActionException: $message';
}

/// A running game. Pure Dart: no Flutter or networking, so it can be unit
/// tested directly. The server owns the only instance and sends each player
/// the result of [viewFor], which must hide information they may not see.
abstract class GameSession {
  /// Validates and applies [action] from [playerId], or throws
  /// [GameActionException].
  void applyAction(String playerId, Json action);

  /// The state as [playerId] is allowed to see it.
  Json viewFor(String playerId);

  /// The public state for a shared screen everyone can see. Must never
  /// include information hidden from any player, such as hands.
  Json tableView();

  bool get isOver;

  /// Final outcome once [isOver]: `{'winnerIds': [...], 'summary': '...'}`.
  Json? get result;
}

typedef GameSessionFactory = GameSession Function(
  List<PlayerInfo> players,
  int round,
  Random random,
);

/// Static description of a game, used by the host to pick one and by the
/// server to size the room and create sessions.
class GameDefinition {
  const GameDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.minPlayers,
    required this.maxPlayers,
    required this.createSession,
  });

  final String id;
  final String name;
  final String description;
  final int minPlayers;
  final int maxPlayers;

  /// [players] are in join order (host first); [round] starts at 0 and
  /// increments on every restart.
  final GameSessionFactory createSession;

  String get playerRange => minPlayers == maxPlayers
      ? '$minPlayers players'
      : '$minPlayers–$maxPlayers players';
}
