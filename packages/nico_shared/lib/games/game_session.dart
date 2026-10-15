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
  GameOptions options,
);

/// The host's choices for a game's [GameOption]s, by option id.
typedef GameOptions = Map<String, bool>;

/// A rule the host can switch on or off in the lobby, such as "a hit earns
/// another shot". The engine reads the chosen value from the [GameOptions]
/// passed to [GameDefinition.createSession].
class GameOption {
  const GameOption({
    required this.id,
    required this.label,
    this.description = '',
    this.defaultValue = false,
  });

  /// Key in [GameOptions], such as `shootAgain`. Unique per game.
  final String id;

  /// Short switch label, such as "Hit = shoot again".
  final String label;

  /// One line under the switch explaining the rule.
  final String description;
  final bool defaultValue;
}

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
    this.options = const [],
  });

  final String id;
  final String name;
  final String description;
  final int minPlayers;
  final int maxPlayers;

  /// Players are in join order (host first). The round starts at 0 and
  /// increments on every restart. The options hold a value for every
  /// [GameOption] in [options].
  final GameSessionFactory createSession;

  /// Rules the host can switch in the lobby. Empty for most games.
  final List<GameOption> options;

  String get playerRange => minPlayers == maxPlayers
      ? '$minPlayers players'
      : '$minPlayers–$maxPlayers players';

  GameOptions get defaultOptions => {
    for (final o in options) o.id: o.defaultValue,
  };

  /// [current] with [changes] applied. Throws [FormatException] for an
  /// unknown option id or a value that isn't a bool.
  GameOptions updateOptions(GameOptions current, Object? changes) {
    if (changes is! Map<String, Object?>) {
      throw const FormatException('Options must be an object.');
    }
    final next = {...defaultOptions, ...current};
    for (final MapEntry(:key, :value) in changes.entries) {
      if (!next.containsKey(key)) {
        throw FormatException('$name has no option "$key".');
      }
      if (value is! bool) throw FormatException('"$key" must be on or off.');
      next[key] = value;
    }
    return next;
  }

  /// The active rules as text, such as `['Hit = shoot again: on']`, for
  /// lobbies and shared screens.
  List<String> describeOptions(GameOptions values) => [
    for (final o in options)
      '${o.label}: ${(values[o.id] ?? o.defaultValue) ? 'on' : 'off'}',
  ];
}
