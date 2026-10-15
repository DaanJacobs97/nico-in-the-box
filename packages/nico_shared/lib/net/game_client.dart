import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'channel/connect.dart';
import 'protocol.dart';

/// Thrown by [GameClient.connect] when the room refuses or can't be reached.
class JoinException implements Exception {
  const JoinException(this.code, this.message);

  /// An [ErrorCode] value, or `'unreachable'` if no connection was made.
  final String code;
  final String message;

  static const unreachable = 'unreachable';

  @override
  String toString() => 'JoinException($code): $message';
}

/// Why the client is no longer connected.
enum DisconnectReason { left, kicked, hostClosed, hostLeft, connectionLost }

/// A player's connection to a room. Exposes the latest lobby and game state
/// as a [ChangeNotifier] for the UI.
class GameClient extends ChangeNotifier {
  GameClient._(this._channel, this.playerId, this.isHost);

  final WebSocketChannel _channel;
  final String playerId;
  final bool isHost;

  StreamSubscription<Object?>? _subscription;
  final _notices = StreamController<String>.broadcast();

  LobbyState? lobby;

  /// Game id and per-player view from the latest [Msg.gameState].
  String? gameId;
  Json? gameView;

  /// Outcome of the last finished game, cleared when a new one starts.
  Json? gameResult;

  /// The shared-screen state, received only while this device *is* the
  /// shared screen (the host chose not to take a seat).
  DisplayState? displayState;

  DisconnectReason? disconnectReason;

  bool get isConnected => disconnectReason == null;

  /// Server notices and action errors, for showing as snackbars.
  Stream<String> get notices => _notices.stream;

  /// Connects to a room and completes once the server has accepted the
  /// player, or throws [JoinException].
  static Future<GameClient> connect({
    required String host,
    required int port,
    required String nickname,
    String? hostToken,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final channel = connectChannel(
      Uri(scheme: 'ws', host: host, port: port, path: kWebSocketPath),
    );
    try {
      await channel.ready.timeout(timeout);
    } on Object {
      unawaited(channel.sink.close());
      throw JoinException(
        JoinException.unreachable,
        'Could not reach a room at $host:$port.',
      );
    }

    // Messages that arrive right after the welcome (the first lobby update)
    // must not be lost, so a single subscription serves both phases.
    final welcome = Completer<GameClient>();
    GameClient? client;
    late final StreamSubscription<Object?> sub;
    sub = channel.stream.listen(
      (raw) {
        final Json msg;
        try {
          msg = decodeMessage(raw);
        } on FormatException {
          return;
        }
        if (client != null) {
          client!._handle(msg);
          return;
        }
        switch (msg['type']) {
          case Msg.welcome:
            client = GameClient._(
              channel,
              msg['playerId']! as String,
              msg['isHost'] == true,
            ).._subscription = sub;
            welcome.complete(client);
          case Msg.error:
            welcome.completeError(
              JoinException(
                msg['code'] as String? ?? ErrorCode.badMessage,
                msg['msg'] as String? ?? 'The room refused the connection.',
              ),
            );
        }
      },
      onDone: () {
        if (client != null) {
          client!._onConnectionClosed();
        } else if (!welcome.isCompleted) {
          welcome.completeError(
            const JoinException(
              JoinException.unreachable,
              'The room closed the connection.',
            ),
          );
        }
      },
      onError: (Object _) {},
    );

    channel.sink.add(
      encodeMessage(Msg.hello, {
        'nickname': nickname,
        'protocol': kProtocolVersion,
        'hostToken': ?hostToken,
        'client': kIsWeb ? 'web' : 'app',
      }),
    );

    try {
      return await welcome.future.timeout(timeout);
    } on Object catch (e) {
      await sub.cancel();
      await channel.sink.close();
      if (e is JoinException) rethrow;
      throw const JoinException(
        JoinException.unreachable,
        'The room did not respond.',
      );
    }
  }

  void _handle(Json msg) {
    switch (msg['type']) {
      case Msg.lobby:
        final next = LobbyState.fromJson(msg);
        if (next.phase == RoomPhase.lobby) {
          gameView = null;
          gameId = null;
          gameResult = null;
        }
        lobby = next;
      case Msg.gameState:
        if (lobby?.phase == RoomPhase.playing) gameResult = null;
        gameId = msg['game']! as String;
        gameView = msg['view']! as Json;
      case Msg.gameOver:
        gameResult = msg['result'] as Json?;
      case Msg.display:
        displayState = DisplayState.fromJson(msg);
      case Msg.notice:
        _notices.add(msg['msg']! as String);
      case Msg.error:
        _notices.add(msg['msg'] as String? ?? 'Something went wrong.');
      case Msg.kicked:
        disconnectReason = DisconnectReason.kicked;
      case Msg.closed:
        disconnectReason ??= msg['reason'] == CloseReason.hostLeft
            ? DisconnectReason.hostLeft
            : DisconnectReason.hostClosed;
      default:
        return;
    }
    notifyListeners();
  }

  void _onConnectionClosed() {
    if (disconnectReason == null) {
      disconnectReason = DisconnectReason.connectionLost;
      notifyListeners();
    }
  }

  void _send(String type, [Json body = const {}]) {
    if (!isConnected) return;
    try {
      _channel.sink.add(encodeMessage(type, body));
    } on StateError {
      // The socket closed before onDone was delivered.
      _onConnectionClosed();
    }
  }

  void sendAction(Json action) => _send(Msg.action, {'action': action});

  // Host-only commands. The server rejects them from anyone else.
  void startGame() => _send(Msg.start);
  void restartGame() => _send(Msg.restart);
  void endGame() => _send(Msg.endGame);
  void kick(String playerId) => _send(Msg.kick, {'playerId': playerId});
  void changeGame(String gameId) => _send(Msg.changeGame, {'gameId': gameId});
  void closeRoom() => _send(Msg.closeRoom);
  void setDisplay(DisplaySettings display) =>
      _send(Msg.setDisplay, {'display': display.toJson()});

  /// Switches game options by id; options not named keep their value.
  void setGameOptions(Map<String, bool> changes) =>
      _send(Msg.setGameOptions, {'options': changes});

  Future<void> leave() async {
    disconnectReason ??= DisconnectReason.left;
    await _subscription?.cancel();
    await _channel.sink.close();
  }

  @override
  void dispose() {
    unawaited(leave());
    unawaited(_notices.close());
    super.dispose();
  }
}
