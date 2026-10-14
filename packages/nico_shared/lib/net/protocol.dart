import 'dart:convert';

/// Bump whenever a message shape changes so mismatched builds refuse to talk.
const int kProtocolVersion = 2;

/// TCP port the game server listens on (WebSocket at [kWebSocketPath]).
const int kGamePort = 47800;

/// UDP port hosts broadcast room announcements to.
const int kDiscoveryPort = 47801;

/// Identifier included in discovery packets so unrelated traffic is ignored.
const String kDiscoveryAppId = 'nicobox';

const String kWebSocketPath = '/ws';

/// Read-only WebSocket for shared screens (browser displays).
const String kDisplayPath = '/display';

const int kMaxNicknameLength = 16;

typedef Json = Map<String, Object?>;

/// Message `type` values.
abstract final class Msg {
  // client -> server
  static const hello = 'hello';
  static const action = 'action';

  // client -> server, host only
  static const start = 'start';
  static const restart = 'restart';
  static const endGame = 'endGame';
  static const kick = 'kick';
  static const changeGame = 'changeGame';
  static const closeRoom = 'closeRoom';
  static const setDisplay = 'setDisplay';

  // server -> client
  static const welcome = 'welcome';
  static const lobby = 'lobby';
  static const gameState = 'gameState';
  static const gameOver = 'gameOver';
  static const notice = 'notice';
  static const error = 'error';
  static const kicked = 'kicked';
  static const closed = 'closed';

  // server -> shared screens (and the host's device when it is the screen)
  static const display = 'display';
}

/// `code` values carried by [Msg.error].
abstract final class ErrorCode {
  static const protocolMismatch = 'protocolMismatch';
  static const invalidName = 'invalidName';
  static const nameTaken = 'nameTaken';
  static const roomFull = 'roomFull';
  static const gameInProgress = 'gameInProgress';
  static const notHost = 'notHost';
  static const invalidAction = 'invalidAction';
  static const notEnoughPlayers = 'notEnoughPlayers';
  static const tooManyPlayers = 'tooManyPlayers';
  static const unknownGame = 'unknownGame';
  static const badMessage = 'badMessage';
}

/// `reason` values carried by [Msg.closed].
abstract final class CloseReason {
  static const hostClosed = 'hostClosed';
  static const hostLeft = 'hostLeft';
}

/// Phase of a room, shared in every [Msg.lobby] message.
enum RoomPhase { lobby, playing, finished }

String encodeMessage(String type, [Json body = const {}]) =>
    jsonEncode({'type': type, ...body});

/// Decodes a raw message; throws [FormatException] if it isn't a typed object.
Json decodeMessage(Object? raw) {
  if (raw is! String) throw const FormatException('Expected a text frame');
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, Object?> || decoded['type'] is! String) {
    throw const FormatException('Expected an object with a type');
  }
  return decoded;
}

/// Trims [raw] and returns it if it is a valid nickname, otherwise null.
String? normalizeNickname(String raw) {
  final name = raw.trim();
  if (name.isEmpty || name.length > kMaxNicknameLength) return null;
  return name;
}

class PlayerInfo {
  const PlayerInfo({
    required this.id,
    required this.nickname,
    this.isWeb = false,
  });

  final String id;
  final String nickname;

  /// Playing from a browser rather than the app (shown as an icon).
  final bool isWeb;

  Json toJson() => {'id': id, 'nickname': nickname, if (isWeb) 'web': true};

  factory PlayerInfo.fromJson(Json json) => PlayerInfo(
    id: json['id']! as String,
    nickname: json['nickname']! as String,
    isWeb: json['web'] == true,
  );
}

/// Where the shared screen is shown when Single game screen is on.
enum DisplayTarget { browser, caster }

/// The host's Single game screen settings, part of every lobby update.
class DisplaySettings {
  const DisplaySettings({
    this.enabled = false,
    this.target = DisplayTarget.browser,
    this.hostPlays = true,
  });

  static const off = DisplaySettings();

  final bool enabled;
  final DisplayTarget target;

  /// False when the host's own device is the shared screen: the host keeps
  /// the session controls but takes no seat.
  final bool hostPlays;

  /// The host's device is the screen right now, so the host takes no seat.
  /// Only while the shared screen is on; switching it off seats the host.
  bool get hostIsScreen => enabled && !hostPlays;

  DisplaySettings copyWith({
    bool? enabled,
    DisplayTarget? target,
    bool? hostPlays,
  }) => DisplaySettings(
    enabled: enabled ?? this.enabled,
    target: target ?? this.target,
    hostPlays: hostPlays ?? this.hostPlays,
  );

  Json toJson() => {
    'enabled': enabled,
    'target': target.name,
    'hostPlays': hostPlays,
  };

  factory DisplaySettings.fromJson(Json json) => DisplaySettings(
    enabled: json['enabled'] == true,
    target: DisplayTarget.values.byName(json['target']! as String),
    hostPlays: json['hostPlays'] != false,
  );

  @override
  bool operator ==(Object other) =>
      other is DisplaySettings &&
      other.enabled == enabled &&
      other.target == target &&
      other.hostPlays == hostPlays;

  @override
  int get hashCode => Object.hash(enabled, target, hostPlays);
}

/// What kind of shared screen is connected.
enum DisplayKind { browser, caster, host }

/// A connected shared screen, as listed in the lobby.
class DisplayInfo {
  const DisplayInfo({required this.kind, required this.name});

  final DisplayKind kind;
  final String name;

  Json toJson() => {'kind': kind.name, 'name': name};

  factory DisplayInfo.fromJson(Json json) => DisplayInfo(
    kind: DisplayKind.values.byName(json['kind']! as String),
    name: json['name']! as String,
  );
}

/// Snapshot of a room as broadcast to every client in [Msg.lobby].
class LobbyState {
  const LobbyState({
    required this.roomName,
    required this.gameId,
    required this.players,
    required this.minPlayers,
    required this.maxPlayers,
    required this.hostId,
    required this.phase,
    this.hostName = '',
    this.display = DisplaySettings.off,
    this.displays = const [],
  });

  final String roomName;
  final String gameId;

  /// Seated players. The host is among them unless their device is the
  /// shared screen ([DisplaySettings.hostPlays] is false).
  final List<PlayerInfo> players;
  final int minPlayers;
  final int maxPlayers;
  final String? hostId;
  final RoomPhase phase;

  /// The host's nickname, even when the host has no seat.
  final String hostName;

  final DisplaySettings display;

  /// Shared screens currently connected.
  final List<DisplayInfo> displays;

  bool get canStart => players.length >= minPlayers;

  /// Whether players should use their compact, hand-only layout: the shared
  /// screen is on *and* at least one screen is actually showing the table.
  bool get sharedScreenActive => display.enabled && displays.isNotEmpty;

  String nicknameOf(String playerId) {
    for (final p in players) {
      if (p.id == playerId) return p.nickname;
    }
    return playerId == hostId && hostName.isNotEmpty ? hostName : '?';
  }

  Json toJson() => {
    'room': roomName,
    'game': gameId,
    'players': [for (final p in players) p.toJson()],
    'min': minPlayers,
    'max': maxPlayers,
    'hostId': hostId,
    'hostName': hostName,
    'phase': phase.name,
    'display': display.toJson(),
    'displays': [for (final d in displays) d.toJson()],
  };

  factory LobbyState.fromJson(Json json) => LobbyState(
    roomName: json['room']! as String,
    gameId: json['game']! as String,
    players: [
      for (final p in json['players']! as List<Object?>)
        PlayerInfo.fromJson(p! as Json),
    ],
    minPlayers: json['min']! as int,
    maxPlayers: json['max']! as int,
    hostId: json['hostId'] as String?,
    hostName: json['hostName'] as String? ?? '',
    phase: RoomPhase.values.byName(json['phase']! as String),
    display: json['display'] == null
        ? DisplaySettings.off
        : DisplaySettings.fromJson(json['display']! as Json),
    displays: [
      for (final d in json['displays'] as List<Object?>? ?? const [])
        DisplayInfo.fromJson(d! as Json),
    ],
  );
}

/// Everything a shared screen draws, sent as [Msg.display] after every
/// change. Holds only public information: never a player's hand.
class DisplayState {
  const DisplayState({
    required this.lobby,
    this.gameId,
    this.table,
    this.result,
  });

  final LobbyState lobby;

  /// Set while a game is running or finished.
  final String? gameId;

  /// The game's `GameSession.tableView()`.
  final Json? table;

  /// The finished game's result, like [Msg.gameOver].
  final Json? result;

  Json toJson() => {
    'lobby': lobby.toJson(),
    'game': gameId,
    'table': table,
    'result': result,
  };

  factory DisplayState.fromJson(Json json) => DisplayState(
    lobby: LobbyState.fromJson(json['lobby']! as Json),
    gameId: json['game'] as String?,
    table: json['table'] as Json?,
    result: json['result'] as Json?,
  );
}
