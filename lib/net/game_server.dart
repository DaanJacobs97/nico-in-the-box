import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/games/registry.dart';
import 'package:nico_shared/net/protocol.dart';

import 'display_frontend.dart';
import 'web_files.dart';
import 'web_routes.dart';

part 'display_handle.dart';

class _Connection {
  _Connection(this.socket);

  final WebSocket socket;
  PlayerInfo? player;
  // Cancelled in GameServer._drop.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? subscription;
  Timer? helloTimeout;

  void send(String type, [Json body = const {}]) {
    if (socket.readyState != WebSocket.open) return;
    try {
      socket.add(encodeMessage(type, body));
    } on StateError {
      // Closing concurrently; the disconnect handler cleans up.
    }
  }
}

/// Host-authoritative room server. Runs on the host's device; every player
/// (including the host, over loopback) connects as a WebSocket client.
///
/// The host proves who they are by sending [hostToken] in their hello, so
/// host-only commands cannot be issued by anyone else.
class GameServer extends ChangeNotifier {
  GameServer({
    required this.roomName,
    required this._game,
    this.webClient,
    this.screenPage,
    this._display = DisplaySettings.off,
    Random? random,
  }) : _random = random ?? Random.secure(),
       hostToken = _randomToken(random ?? Random.secure());

  final String roomName;

  /// The browser player client served at `/play/`; null if this build of
  /// the app doesn't include it.
  final WebFiles? webClient;

  /// The shared screen page served at `/screen/`; null if not bundled.
  final DisplayFrontend? screenPage;
  final String hostToken;
  final Random _random;
  GameDefinition _game;

  /// The host's choices for [game]'s options; reset when the game changes.
  late GameOptions _gameOptions = _game.defaultOptions;

  HttpServer? _http;
  final List<_Connection> _connections = [];
  final List<DisplayHandle> _displays = [];
  DisplaySettings _display;
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

  DisplaySettings get display => _display;

  GameOptions get gameOptions => Map.unmodifiable(_gameOptions);

  /// Everyone who said hello, including a host without a seat.
  Iterable<PlayerInfo> get _everyone => [
    for (final c in _connections)
      if (c.player != null) c.player!,
  ];

  /// Seated players, in join order. The host sits out when their device is
  /// the shared screen.
  List<PlayerInfo> get players => [
    for (final p in _everyone)
      if (p.id != _hostId || !_display.hostIsScreen) p,
  ];

  bool get _hostIsScreen => _hostId != null && _display.hostIsScreen;

  /// Whether a new (non-host) player could join right now.
  bool get acceptingPlayers =>
      _phase == RoomPhase.lobby && _seatsTaken < _game.maxPlayers;

  /// Seats in use, counting one reserved for a playing host until they
  /// connect.
  int get _seatsTaken =>
      players.length + (_hostId == null && !_display.hostIsScreen ? 1 : 0);

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
    // Gzip responses for browsers that accept it (the web client is large).
    _http!.autoCompress = true;
    _http!.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    if (path == kWebSocketPath &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      await _upgradeToPlayer(request);
      return;
    }
    if (path == kDisplayPath &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      await _upgradeToDisplay(request);
      return;
    }
    try {
      await serveWebRequest(
        request,
        roomName: roomName,
        webClient: webClient,
        screenPage: screenPage,
      );
    } on Object {
      // The browser went away mid-response; nothing to clean up.
    }
  }

  /// A browser shared screen: read-only, so anything it sends is ignored.
  Future<void> _upgradeToDisplay(HttpRequest request) async {
    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } on Object {
      return;
    }
    if (_closed) {
      await socket.close();
      return;
    }
    socket.pingInterval = const Duration(seconds: 5);
    final browserCount = _displays
        .where((d) => d.info.kind == DisplayKind.browser)
        .length;
    final handle = attachDisplay(
      kind: DisplayKind.browser,
      name: 'Browser ${browserCount + 1}',
      send: (message) {
        if (socket.readyState == WebSocket.open) socket.add(message);
      },
      close: () => socket.close(),
    );
    socket.listen(
      (_) {},
      onDone: handle.detach,
      onError: (Object _) => handle.detach(),
      cancelOnError: true,
    );
  }

  /// Shows [message] to every player as a notice.
  void broadcastNotice(String message) =>
      _broadcast(Msg.notice, {'msg': message});

  /// Connects a shared screen. It immediately receives the current
  /// [Msg.display] state and every update after that until detached.
  DisplayHandle attachDisplay({
    required DisplayKind kind,
    required String name,
    required void Function(String message) send,
    Future<void> Function()? close,
  }) {
    late final DisplayHandle handle;
    handle = DisplayHandle._(
      DisplayInfo(kind: kind, name: name),
      send,
      close,
      onDetach: () {
        if (_displays.remove(handle) && !_closed) _broadcastLobby();
      },
    );
    _displays.add(handle);
    // The lobby lists the new screen; that broadcast also sends it the
    // current display state.
    _broadcastLobby();
    return handle;
  }

  Future<void> _upgradeToPlayer(HttpRequest request) async {
    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } on Object {
      return; // Client went away mid-handshake.
    }
    if (_closed) {
      await socket.close();
      return;
    }
    socket.pingInterval = const Duration(seconds: 5);
    final conn = _Connection(socket);
    _connections.add(conn);
    conn.helloTimeout = Timer(const Duration(seconds: 10), () {
      if (conn.player == null) unawaited(_drop(conn));
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
      Msg.setDisplay,
      Msg.setGameOptions,
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
      case Msg.setDisplay:
        _setDisplay(conn, msg['display']);
      case Msg.setGameOptions:
        _setGameOptions(conn, msg['options']);
    }
  }

  void _setGameOptions(_Connection conn, Object? changes) {
    if (_phase != RoomPhase.lobby) {
      _error(conn, ErrorCode.invalidAction, 'End the current game first.');
      return;
    }
    try {
      _gameOptions = _game.updateOptions(_gameOptions, changes);
    } on FormatException catch (e) {
      _error(conn, ErrorCode.badMessage, e.message);
      return;
    }
    _broadcastLobby();
  }

  void _setDisplay(_Connection conn, Object? raw) {
    final DisplaySettings next;
    try {
      next = DisplaySettings.fromJson(raw! as Json);
    } on Object {
      _error(conn, ErrorCode.badMessage, 'Malformed display settings.');
      return;
    }
    if (_phase != RoomPhase.lobby) {
      _error(conn, ErrorCode.invalidAction, 'End the current game first.');
      return;
    }
    // The host taking a seat again needs a free one.
    if (_hostIsScreen &&
        !next.hostIsScreen &&
        players.length >= _game.maxPlayers) {
      _error(
        conn,
        ErrorCode.tooManyPlayers,
        'The room is full, so you can\'t take a seat.',
      );
      return;
    }
    _display = next;
    _broadcastLobby();
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
        'Nicknames must be 1–$kMaxNicknameLength characters.',
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
    if (_everyone.any((p) => p.nickname.toLowerCase() == lower)) {
      _reject(conn, ErrorCode.nameTaken, '"$nickname" is already taken.');
      return;
    }

    conn.helloTimeout?.cancel();
    final player = PlayerInfo(
      id: 'p${_nextPlayerId++}',
      nickname: nickname,
      isWeb: msg['client'] == 'web',
    );
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
    _session = _game.createSession(
      current,
      _round,
      _random,
      Map.of(_gameOptions),
    );
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
    _gameOptions = next.defaultOptions;
    _broadcastLobby();
  }

  void _reject(_Connection conn, String code, String message) {
    conn.send(Msg.error, {'code': code, 'msg': message});
    unawaited(_drop(conn));
  }

  void _error(_Connection conn, String code, String message) =>
      conn.send(Msg.error, {'code': code, 'msg': message});

  void _onDisconnect(_Connection conn) {
    if (!_connections.contains(conn)) return;
    final player = conn.player;
    if (player == null) {
      unawaited(_drop(conn));
    } else if (player.id == _hostId) {
      unawaited(_drop(conn));
      unawaited(close(reason: CloseReason.hostLeft));
    } else {
      _removePlayer(conn, '${player.nickname} left.');
    }
  }

  /// Removes a joined player; a running game cannot continue without them.
  void _removePlayer(_Connection conn, String notice) {
    unawaited(_drop(conn));
    if (_closed) return;
    if (_phase != RoomPhase.lobby) {
      _returnToLobby(notice: '$notice The game was ended.');
    } else {
      _broadcastLobby();
      _broadcast(Msg.notice, {'msg': notice});
    }
  }

  /// Closes the WebSocket gracefully so queued messages (an error or the
  /// closed notice) are delivered before the connection goes away.
  Future<void> _drop(_Connection conn) async {
    _connections.remove(conn);
    conn.helloTimeout?.cancel();
    try {
      await conn.socket.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Peer vanished or never answered the close handshake.
    }
    await conn.subscription?.cancel();
  }

  String get _hostName =>
      _everyone.where((p) => p.id == _hostId).firstOrNull?.nickname ?? '';

  LobbyState get lobbyState => LobbyState(
    roomName: roomName,
    gameId: _game.id,
    players: players,
    minPlayers: _game.minPlayers,
    maxPlayers: _game.maxPlayers,
    hostId: _hostId,
    hostName: _hostName,
    phase: _phase,
    display: _display,
    gameOptions: Map.of(_gameOptions),
    displays: [
      for (final d in _displays) d.info,
      if (_hostIsScreen) DisplayInfo(kind: DisplayKind.host, name: _hostName),
    ],
  );

  /// What every shared screen shows: public state only.
  DisplayState get displayState {
    final session = _session;
    return DisplayState(
      lobby: lobbyState,
      gameName: _game.name,
      rules: _game.describeOptions(_gameOptions),
      gameId: session == null ? null : _game.id,
      table: session?.tableView(),
      result: session?.result,
    );
  }

  void _broadcastLobby() {
    _broadcast(Msg.lobby, lobbyState.toJson());
    _broadcastDisplay();
    notifyListeners();
  }

  void _broadcastGameState() {
    final session = _session;
    if (session == null) return;
    for (final conn in _connections) {
      final player = conn.player;
      // A host without a seat follows the game through the display feed.
      if (player == null || (player.id == _hostId && _hostIsScreen)) continue;
      conn.send(Msg.gameState, {
        'game': _game.id,
        'view': session.viewFor(player.id),
      });
    }
    _broadcastDisplay();
  }

  void _broadcastDisplay() {
    final message = encodeMessage(Msg.display, displayState.toJson());
    for (final display in List.of(_displays)) {
      display._send(message);
    }
    if (_hostIsScreen) {
      _connections
          .where((c) => c.player?.id == _hostId)
          .firstOrNull
          ?.send(Msg.display, displayState.toJson());
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
    final closedMessage = encodeMessage(Msg.closed, {'reason': reason});
    await Future.wait([
      for (final conn in List.of(_connections))
        () {
          conn.send(Msg.closed, {'reason': reason});
          return _drop(conn);
        }(),
      for (final display in List.of(_displays))
        () {
          display._send(closedMessage);
          return display._close();
        }(),
    ]);
    _displays.clear();
    await _http?.close(force: true);
    notifyListeners();
  }
}
