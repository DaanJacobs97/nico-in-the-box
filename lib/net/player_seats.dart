part of 'game_server.dart';

/// One player WebSocket. Until its hello is accepted it has no [seat].
class _Connection {
  _Connection(this.socket);

  final WebSocket socket;
  _Seat? seat;
  // Cancelled in GameServer._drop.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? subscription;
  Timer? helloTimeout;

  PlayerInfo? get player => seat?.player;

  void send(String type, [Json body = const {}]) {
    if (socket.readyState != WebSocket.open) return;
    try {
      socket.add(encodeMessage(type, body));
    } on StateError {
      // Closing concurrently; the disconnect handler cleans up.
    }
  }
}

/// A player's place in the room. It outlives a dropped connection for
/// [GameServer.reconnectGrace], so the player can take it back with
/// [token].
class _Seat {
  _Seat(this.player, this.token, this.conn);

  final PlayerInfo player;

  /// Secret, sent only to this player in their welcome.
  final String token;

  /// Null while the player is away.
  _Connection? conn;

  /// Runs out the grace period while the player is away.
  Timer? expiry;

  bool get away => conn == null;

  /// What everyone else sees, including whether the player is away.
  PlayerInfo get info => PlayerInfo(
    id: player.id,
    nickname: player.nickname,
    isWeb: player.isWeb,
    away: away,
  );

  void send(String type, [Json body = const {}]) => conn?.send(type, body);
}

/// Joining, leaving, dropping out and coming back.
extension _PlayerSeats on GameServer {
  void _onHello(_Connection conn, Json msg) {
    if (msg['protocol'] != kProtocolVersion) {
      _reject(
        conn,
        ErrorCode.protocolMismatch,
        'This room runs a different app version.',
      );
      return;
    }
    final resume = msg['resume'];
    if (resume != null) {
      _resume(conn, resume);
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
    if (_seats.any((s) => s.player.nickname.toLowerCase() == lower)) {
      _reject(conn, ErrorCode.nameTaken, '"$nickname" is already taken.');
      return;
    }

    conn.helloTimeout?.cancel();
    final seat = _Seat(
      PlayerInfo(
        id: 'p${_nextPlayerId++}',
        nickname: nickname,
        isWeb: msg['client'] == 'web',
      ),
      GameServer._randomToken(_random),
      conn,
    );
    _seats.add(seat);
    conn.seat = seat;
    if (isHost) _hostId = seat.player.id;
    _welcome(seat);
    _broadcastLobby();
  }

  /// The host closes the room by leaving, so they get no resume token.
  void _welcome(_Seat seat) {
    final isHost = seat.player.id == _hostId;
    seat.send(Msg.welcome, {
      'playerId': seat.player.id,
      'isHost': isHost,
      if (!isHost) 'resumeToken': seat.token,
      if (!isHost) 'graceMs': reconnectGrace.inMilliseconds,
    });
  }

  /// Gives a kept seat to a new connection: same id, nickname and game.
  void _resume(_Connection conn, Object? token) {
    final seat = _seats
        .where((s) => s.player.id != _hostId && s.token == token)
        .firstOrNull;
    if (seat == null) {
      _reject(conn, ErrorCode.resumeFailed, 'Your seat in the room is gone.');
      return;
    }
    conn.helloTimeout?.cancel();
    final wasAway = seat.away;
    seat.expiry?.cancel();
    seat.expiry = null;
    // The client may notice a dead link before the server's ping does. The
    // old connection is then closed quietly instead of counting as a drop.
    final old = seat.conn;
    if (old != null) {
      old.seat = null;
      unawaited(_drop(old));
    }
    seat.conn = conn;
    conn.seat = seat;
    _welcome(seat);
    _broadcastLobby();
    final session = _session;
    if (session != null) {
      seat.send(Msg.gameState, {
        'game': _game.id,
        'view': session.viewFor(seat.player.id),
      });
      if (session.isOver) seat.send(Msg.gameOver, {'result': session.result});
    }
    if (wasAway) {
      for (final other in _seats) {
        if (other != seat) {
          other.send(Msg.notice, {'msg': '${seat.player.nickname} is back.'});
        }
      }
    }
  }

  /// A connection closed. Players keep their seat for [reconnectGrace]
  /// unless they said they were leaving; the host closes the room.
  void _onDisconnect(_Connection conn, {bool leaving = false}) {
    if (!_connections.contains(conn)) return;
    final seat = conn.seat;
    unawaited(_drop(conn));
    if (seat == null || _closed) return;
    if (seat.player.id == _hostId) {
      unawaited(close(reason: CloseReason.hostLeft));
    } else if (leaving || reconnectGrace == Duration.zero) {
      _removeSeat(seat, '${seat.player.nickname} left.');
    } else {
      seat.conn = null;
      seat.expiry = Timer(
        reconnectGrace,
        () => _removeSeat(seat, "${seat.player.nickname} didn't come back."),
      );
      _broadcastLobby();
      _broadcast(Msg.notice, {
        'msg':
            '${seat.player.nickname} lost connection. '
            'Waiting up to ${(reconnectGrace.inMilliseconds / 1000).ceil()} s…',
      });
    }
  }

  void _kick(_Connection hostConn, Object? playerId) {
    final target = _seats.where((s) => s.player.id == playerId).firstOrNull;
    if (target == null || target.conn == hostConn) {
      _error(hostConn, ErrorCode.invalidAction, "You can't kick that player.");
      return;
    }
    target.send(Msg.kicked);
    _removeSeat(target, '${target.player.nickname} was kicked.');
  }

  /// Frees a seat for good; a running game cannot continue without it.
  void _removeSeat(_Seat seat, String notice) {
    if (!_seats.remove(seat)) return;
    seat.expiry?.cancel();
    final conn = seat.conn;
    if (conn != null) unawaited(_drop(conn));
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
}
