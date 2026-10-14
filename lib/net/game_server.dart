import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../games/game_session.dart';
import '../games/registry.dart';
import 'protocol.dart';

class _Connection {
  _Connection(this.socket);

  final WebSocket socket;
  PlayerInfo? player;
  // Cancelled in GameServer._drop.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? subscription;
  Timer? helloTimeout;

  void send(String type, [Json body = const {}]) {
    if (socket.readyState == WebSocket.open) {
      socket.add(encodeMessage(type, body));
    }
  }
}

/// Host-authoritative room server. Runs on the host's device; every player
/// (including the host, over loopback) connects as a WebSocket client.
///
/// The host proves who they are by sending [hostToken] in their hello, so
/// host-only commands cannot be issued by anyone else.
class GameServer extends ChangeNotifier {
  GameServer({required this.roomName, required this._game, Random? random})
    : _random = random ?? Random.secure(),
      hostToken = _randomToken(random ?? Random.secure());

  final String roomName;
  final String hostToken;
  final Random _random;
  GameDefinition _game;

  HttpServer? _http;
  final List<_Connection> _connections = [];
  String? _hostId;
  int _nextPlayerId = 1;
  RoomPhase _phase = RoomPhase.lobby;
  GameSession? _session;
  int _round = 0;
  bool _closed = false;

  GameDefinition get game => _game;
  RoomPhase get phase => _phase;
  int get port => _http!.port;
  bool get isRunning => _http != null && !_closed;

  List<PlayerInfo> get players => [
    for (final c in _connections)
      if (c.player != null) c.player!,
  ];

  /// Whether a new (non-host) player could join right now.
  bool get acceptingPlayers =>
      _phase == RoomPhase.lobby && _seatsTaken < _game.maxPlayers;

  /// Seats in use, counting one reserved for the host until they connect.
  int get _seatsTaken => players.length + (_hostId == null ? 1 : 0);

  static String _randomToken(Random random) =>
      List.generate(16, (_) => random.nextInt(256).toRadixString(16)).join();

  /// Binds to [port], trying the next few ports if it is taken.
  /// Pass `port: 0` to let the OS choose (used by tests).
  Future<void> start({
    int port = kGamePort,
    InternetAddress? address,
    int attempts = 10,
  }) async {
    final bindAddress = address ?? InternetAddress.anyIPv4;
    SocketException? lastError;
    for (var i = 0; i < (port == 0 ? 1 : attempts); i++) {
      try {
        _http = await HttpServer.bind(bindAddress, port == 0 ? 0 : port + i);
        break;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    if (_http == null) throw lastError!;
    _http!.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != kWebSocketPath ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    if (_closed) {
      await socket.close();
      return;
    }
    socket.pingInterval = const Duration(seconds: 5);
    final conn = _Connection(socket);
    _connections.add(conn);
    conn.helloTimeout = Timer(const Duration(seconds: 10), () {
      if (conn.player == null) _drop(conn);
    });
    conn.subscription = socket.listen(
      (raw) => _onMessage(conn, raw),
      onDone: () => _onDisconnect(conn),
      onError: (Object _) => _onDisconnect(conn),
      cancelOnError: true,
    );
  }

  void _onMessage(_Connection conn, Object? raw) {
    final Json msg;
    try {
      msg = decodeMessage(raw);
    } on FormatException {
      conn.send(Msg.error, {
        'code': ErrorCode.badMessage,
        'msg': 'Malformed message.',
      });
      return;
    }
    final type = msg['type']! as String;

    if (conn.player == null) {
      if (type == Msg.hello) {
        _onHello(conn, msg);
      } else {
        _reject(conn, ErrorCode.badMessage, 'Say hello first.');
      }
      return;
    }

    final playerId = conn.player!.id;
    if (type == Msg.action) {
      _onAction(conn, msg['action']);
      return;
    }

    const hostCommands = {
      Msg.start,
      Msg.restart,
      Msg.endGame,
      Msg.kick,
      Msg.changeGame,
      Msg.closeRoom,
    };
    if (!hostCommands.contains(type)) {
      conn.send(Msg.error, {
        'code': ErrorCode.badMessage,
        'msg': 'Unknown message "$type".',
      });
      return;
    }
    if (playerId != _hostId) {
      conn.send(Msg.error, {
        'code': ErrorCode.notHost,
        'msg': 'Only the host can do that.',
      });
      return;
    }
    switch (type) {
      case Msg.start:
        _startGame(conn, requirePhase: RoomPhase.lobby);
      case Msg.restart:
        if (_phase == RoomPhase.lobby) {
          _error(conn, ErrorCode.invalidAction, 'No game is running.');
        } else {
          _round++;
          _startGame(conn);
        }
      case Msg.endGame:
        _returnToLobby();
      case Msg.kick:
        _kick(conn, msg['playerId']);
      case Msg.changeGame:
        _changeGame(conn, msg['gameId']);
      case Msg.closeRoom:
        unawaited(close(reason: CloseReason.hostClosed));
    }
  }

  void _onHello(_Connection conn, Json msg) {
    if (msg['protocol'] != kProtocolVersion) {
      _reject(
        conn,
        ErrorCode.protocolMismatch,
        'This room runs a different app version.',
      );
      return;
    }
    final rawName = msg['nickname'];
    final nickname = rawName is String ? normalizeNickname(rawName) : null;
    if (nickname == null) {
      _reject(
        conn,
        ErrorCode.invalidName,
        'Nicknames must be 1â€“$kMaxNicknameLength characters.',
      );
      return;
    }
    final isHost = _hostId == null && msg['hostToken'] == hostToken;
    if (!isHost) {
      if (_phase != RoomPhase.lobby) {
        _reject(conn, ErrorCode.gameInProgress, 'A game is in progress.');
        return;
      }
      if (_seatsTaken >= _game.maxPlayers) {
        _reject(conn, ErrorCode.roomFull, 'The room is full.');
        return;
      }
    }
    final lower = nickname.toLowerCase();
    if (players.any((p) => p.nickname.toLowerCase() == lower)) {
      _reject(conn, ErrorCode.nameTaken, '"$nickname" is already taken.');
      return;
    }

    conn.helloTimeout?.cancel();
    final player = PlayerInfo(id: 'p${_nextPlayerId++}', nickname: nickname);
    conn.player = player;
    if (isHost) _hostId = player.id;
    conn.send(Msg.welcome, {'playerId': player.id, 'isHost': isHost});
    _broadcastLobby();
  }

  void _onAction(_Connection conn, Object? action) {
    final session = _session;
    if (session == null || _phase != RoomPhase.playing) {
      _error(conn, ErrorCode.invalidAction, 'No game is running.');
      return;
    }
    if (action is! Json) {
      _error(conn, ErrorCode.badMessage, 'Malformed action.');
      return;
    }
    try {
      session.applyAction(conn.player!.id, action);
    } on GameActionException catch (e) {
      _error(conn, ErrorCode.invalidAction, e.message);
      return;
    }
    if (session.isOver) _phase = RoomPhase.finished;
    _broadcastGameState();
    if (session.isOver) {
      _broadcastLobby();
      _broadcast(Msg.gameOver, {'result': session.result});
    }
  }

  void _startGame(_Connection conn, {RoomPhase? requirePhase}) {
    if (requirePhase != null && _phase != requirePhase) {
      _error(conn, ErrorCode.invalidAction, 'A game is already running.');
      return;
    }
    final current = players;
    if (current.length < _game.minPlayers) {
      _error(
        conn,
        ErrorCode.notEnoughPlayers,
        '${_game.name} needs at least ${_game.minPlayers} players.',
      );
      return;
    }
    _session = _game.createSession(current, _round, _random);
    _phase = RoomPhase.playing;
    _broadcastLobby();
    _broadcastGameState();
  }

  void _returnToLobby({String? notice}) {
    _session = null;
    _phase = RoomPhase.lobby;
    _broadcastLobby();
    if (notice != null) _broadcast(Msg.notice, {'msg': notice});
  }

  void _kick(_Connection hostConn, Object? playerId) {
    final target = _connections
        .where((c) => c.player != null && c.player!.id == playerId)
        .firstOrNull;
    if (target == null || target == hostConn) {
      _error(hostConn, ErrorCode.invalidAction, "You can't kick that player.");
      return;
    }
    target.send(Msg.kicked);
    _removePlayer(target, '${target.player!.nickname} was kicked.');
  }

  void _changeGame(_Connection conn, Object? gameId) {
    final next = gameId is String ? gameById(gameId) : null;
    if (next == null) {
      _error(conn, ErrorCode.unknownGame, 'Unknown game.');
      return;
    }
    if (_phase != RoomPhase.lobby) {
      _error(conn, ErrorCode.invalidAction, 'End the current game first.');
      return;
    }
    if (players.length > next.maxPlayers) {
      _error(
        conn,
        ErrorCode.tooManyPlayers,
        '${next.name} allows at most ${next.maxPlayers} players.',
      );
      return;
    }
    _game = next;
    _round = 0;
    _broadcastLobby();
  }

  void _reject(_Connection conn, String code, String message) {
    conn.send(Msg.error, {'code': code, 'msg': message});
    _drop(conn);
  }

  void _error(_Connection conn, String code, String message) =>
      conn.send(Msg.error, {'code': code, 'msg': message});

  void _onDisconnect(_Connection conn) {
    if (!_connections.contains(conn)) return;
    final player = conn.player;
    if (player == null) {
      _drop(conn);
    } else if (player.id == _hostId) {
      _drop(conn);
      unawaited(close(reason: CloseReason.hostLeft));
    } else {
      _removePlayer(conn, '${player.nickname} left.');
    }
  }

  /// Removes a joined player; a running game cannot continue without them.
  void _removePlayer(_Connection conn, String notice) {
    _drop(conn);
    if (_closed) return;
    if (_phase != RoomPhase.lobby) {
      _returnToLobby(notice: '$notice The game was ended.');
    } else {
      _broadcastLobby();
      _broadcast(Msg.notice, {'msg': notice});
    }
  }

  void _drop(_Connection conn) {
    _connections.remove(conn);
    conn.helloTimeout?.cancel();
    unawaited(conn.subscription?.cancel());
    unawaited(conn.socket.close());
  }

  LobbyState get lobbyState => LobbyState(
    roomName: roomName,
    gameId: _game.id,
    players: players,
    minPlayers: _game.minPlayers,
    maxPlayers: _game.maxPlayers,
    hostId: _hostId,
    phase: _phase,
  );

  void _broadcastLobby() {
    _broadcast(Msg.lobby, lobbyState.toJson());
    notifyListeners();
  }

  void _broadcastGameState() {
    final session = _session;
    if (session == null) return;
    for (final conn in _connections) {
      final player = conn.player;
      if (player == null) continue;
      conn.send(Msg.gameState, {
        'game': _game.id,
        'view': session.viewFor(player.id),
      });
    }
  }

  void _broadcast(String type, [Json body = const {}]) {
    for (final conn in _connections) {
      if (conn.player != null) conn.send(type, body);
    }
  }

  /// Tells every client the room is gone and stops listening.
  Future<void> close({String reason = CloseReason.hostClosed}) async {
    if (_closed) return;
    _closed = true;
    for (final conn in List.of(_connections)) {
      conn.send(Msg.closed, {'reason': reason});
      _drop(conn);
    }
    await _http?.close(force: true);
    notifyListeners();
  }
}
