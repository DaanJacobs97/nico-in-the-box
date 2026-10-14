import 'dart:convert';

/// Bump whenever a message shape changes so mismatched builds refuse to talk.
const int kProtocolVersion = 1;

/// TCP port the game server listens on (WebSocket at [kWebSocketPath]).
const int kGamePort = 47800;

/// UDP port hosts broadcast room announcements to.
const int kDiscoveryPort = 47801;

/// Identifier included in discovery packets so unrelated traffic is ignored.
const String kDiscoveryAppId = 'nicobox';

const String kWebSocketPath = '/ws';

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

  // server -> client
  static const welcome = 'welcome';
  static const lobby = 'lobby';
  static const gameState = 'gameState';
  static const gameOver = 'gameOver';
  static const notice = 'notice';
  static const error = 'error';
  static const kicked = 'kicked';
  static const closed = 'closed';
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
  const PlayerInfo({required this.id, required this.nickname});

  final String id;
  final String nickname;

  Json toJson() => {'id': id, 'nickname': nickname};

  factory PlayerInfo.fromJson(Json json) => PlayerInfo(
    id: json['id']! as String,
    nickname: json['nickname']! as String,
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
  });

  final String roomName;
  final String gameId;
  final List<PlayerInfo> players;
  final int minPlayers;
  final int maxPlayers;
  final String? hostId;
  final RoomPhase phase;

  bool get canStart => players.length >= minPlayers;

  String nicknameOf(String playerId) => players
      .firstWhere(
        (p) => p.id == playerId,
        orElse: () => PlayerInfo(id: playerId, nickname: '?'),
      )
      .nickname;

  Json toJson() => {
    'room': roomName,
    'game': gameId,
    'players': [for (final p in players) p.toJson()],
    'min': minPlayers,
    'max': maxPlayers,
    'hostId': hostId,
    'phase': phase.name,
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
    phase: RoomPhase.values.byName(json['phase']! as String),
  );
}
