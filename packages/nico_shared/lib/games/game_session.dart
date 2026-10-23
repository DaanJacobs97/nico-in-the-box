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

/// The host's choices for a game's [GameOption]s, by option id: a `bool` for a
/// switch, a [GameChoice.id] for a choice.
typedef GameOptions = Map<String, Object>;

/// Reading [GameOptions] in an engine.
extension GameOptionValues on GameOptions {
  /// The switch [id], or false when it isn't set.
  bool flag(String id) => this[id] == true;

  /// The chosen [GameChoice.id] of the choice [id], or [fallback] when it
  /// isn't set.
  String choice(String id, String fallback) =>
      this[id] is String ? this[id]! as String : fallback;
}

/// One of the values a choice [GameOption] offers.
class GameChoice {
  const GameChoice(this.id, this.label);

  /// The value in [GameOptions], such as `wins`.
  final String id;

  /// What the host and players see, such as "First to x wins".
  final String label;
}

/// A rule the host sets in the lobby: a switch (on or off), such as "a hit
/// earns another shot", or with [GameOption.choice] one of a few values,
/// such as how many hands to play. The engine reads the chosen value from
/// the [GameOptions] passed to [GameDefinition.createSession].
class GameOption {
  const GameOption({
    required this.id,
    required this.label,
    this.description = '',
    bool this.defaultValue = false,
  }) : choices = const [];

  /// Pick one of [choices]; starts on [defaultChoice] (a [GameChoice.id]).
  const GameOption.choice({
    required this.id,
    required this.label,
    required this.choices,
    required String defaultChoice,
    this.description = '',
  }) : defaultValue = defaultChoice;

  /// Key in [GameOptions], such as `shootAgain`. Unique per game.
  final String id;

  /// Short label, such as "Hit = shoot again".
  final String label;

  /// One line under the option explaining the rule.
  final String description;

  /// The values to pick from; empty for a switch.
  final List<GameChoice> choices;

  /// `bool` for a switch, a [GameChoice.id] for a choice.
  final Object defaultValue;

  bool get isChoice => choices.isNotEmpty;

  /// What [value] reads as, such as "on" or "First to x wins".
  String describe(Object? value) {
    final current = value ?? defaultValue;
    if (!isChoice) return current == true ? 'on' : 'off';
    for (final c in choices) {
      if (c.id == current) return c.label;
    }
    return '$current';
  }
}

/// The kind of game, by what you play with. The host's game pickers group games
/// by it, in this order, and leave out categories no game uses yet.
enum GameCategory {
  card('Card games'),
  board('Board games'),
  grid('Grid games'),
  gambling('Gambling games'),
  adventure('Adventure games');

  const GameCategory(this.label);

  final String label;
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
    required this.category,
    required this.createSession,
    this.options = const [],
  });

  final String id;
  final String name;
  final String description;

  /// Where the game sits in the host's game pickers.
  final GameCategory category;
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
  /// unknown option id, a switch that isn't set to a bool, or a choice set to
  /// something it doesn't offer.
  GameOptions updateOptions(GameOptions current, Object? changes) {
    if (changes is! Map<String, Object?>) {
      throw const FormatException('Options must be an object.');
    }
    final next = {...defaultOptions, ...current};
    for (final MapEntry(:key, :value) in changes.entries) {
      final option = options.where((o) => o.id == key).firstOrNull;
      if (option == null) {
        throw FormatException('$name has no option "$key".');
      }
      if (option.isChoice) {
        if (!option.choices.any((c) => c.id == value)) {
          throw FormatException('"$key" can\'t be "$value".');
        }
      } else if (value is! bool) {
        throw FormatException('"$key" must be on or off.');
      }
      next[key] = value!;
    }
    return next;
  }

  /// The active rules as text, such as `['Hit = shoot again: on']`, for
  /// lobbies and shared screens.
  List<String> describeOptions(GameOptions values) => [
    for (final o in options) '${o.label}: ${o.describe(values[o.id])}',
  ];
}
