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

typedef _Link = ({
  WebSocketChannel channel,
  StreamSubscription<Object?> subscription,
});

/// A player's connection to a room. Exposes the latest lobby and game state
/// as a [ChangeNotifier] for the UI.
///
/// If the connection drops, the client reconnects on its own for as long as
/// the server keeps the seat ([reconnecting] is true meanwhile).
class GameClient extends ChangeNotifier {
  GameClient._(
    this._uri,
    this.playerId,
    this.isHost,
    this._timeout,
    this._retryInterval,
  );

  final Uri _uri;
  final String playerId;
  final bool isHost;
  final Duration _timeout;
  final Duration _retryInterval;

  late WebSocketChannel _channel;
  StreamSubscription<Object?>? _subscription;
  final _notices = StreamController<String>.broadcast();

  /// From the welcome; null for the host, who never reconnects.
  String? _resumeToken;
  Duration _grace = Duration.zero;

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

  /// The connection dropped and the client is trying to get its seat back.
  /// Actions sent meanwhile are dropped.
  bool reconnecting = false;

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
    Duration retryInterval = const Duration(seconds: 2),
  }) async {
    final uri = Uri(scheme: 'ws', host: host, port: port, path: kWebSocketPath);
    late final GameClient client;
    await _handshake(
      uri,
      {
        'nickname': nickname,
        'protocol': kProtocolVersion,
        'hostToken': ?hostToken,
        'client': kIsWeb ? 'web' : 'app',
      },
      timeout,
      onWelcome: (welcome, link) {
        client = GameClient._(
          uri,
          welcome['playerId']! as String,
          welcome['isHost'] == true,
          timeout,
          retryInterval,
        ).._attach(welcome, link);
      },
      onMessage: (msg) => client._handle(msg),
      onDone: () => client._onConnectionClosed(),
    );
    return client;
  }

  /// Opens a connection to [uri] and says [hello]. [onWelcome] runs as soon
  /// as the welcome arrives, so messages right behind it (the first lobby
  /// update) are not lost; they go to [onMessage]. Throws [JoinException].
  static Future<void> _handshake(
    Uri uri,
    Json hello,
    Duration timeout, {
    required void Function(Json welcome, _Link link) onWelcome,
    required void Function(Json msg) onMessage,
    required void Function() onDone,
  }) async {
    final channel = connectChannel(uri);
    try {
      await channel.ready.timeout(timeout);
    } on Object {
      unawaited(channel.sink.close());
      throw JoinException(
        JoinException.unreachable,
        'Could not reach a room at ${uri.host}:${uri.port}.',
      );
    }

    final welcomed = Completer<void>();
    var accepted = false;
    late final StreamSubscription<Object?> sub;
    sub = channel.stream.listen(
      (raw) {
        final Json msg;
        try {
          msg = decodeMessage(raw);
        } on FormatException {
          return;
        }
        if (accepted) {
          onMessage(msg);
          return;
        }
        switch (msg['type']) {
          case Msg.welcome:
            accepted = true;
            onWelcome(msg, (channel: channel, subscription: sub));
            welcomed.complete();
          case Msg.error:
            if (!welcomed.isCompleted) {
              welcomed.completeError(
                JoinException(
                  msg['code'] as String? ?? ErrorCode.badMessage,
                  msg['msg'] as String? ?? 'The room refused the connection.',
                ),
              );
            }
        }
      },
      onDone: () {
        if (accepted) {
          onDone();
        } else if (!welcomed.isCompleted) {
          welcomed.completeError(
            const JoinException(
              JoinException.unreachable,
              'The room closed the connection.',
            ),
          );
        }
      },
      onError: (Object _) {},
    );

    channel.sink.add(encodeMessage(Msg.hello, hello));

    try {
      await welcomed.future.timeout(timeout);
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

  void _attach(Json welcome, _Link link) {
    _channel = link.channel;
    _subscription = link.subscription;
    _resumeToken = welcome['resumeToken'] as String?;
    _grace = Duration(milliseconds: welcome['graceMs'] as int? ?? 0);
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

  /// The connection dropped without the server saying why: reconnect if the
  /// server keeps our seat, otherwise give up.
  void _onConnectionClosed() {
    if (disconnectReason != null || reconnecting) return;
    final token = _resumeToken;
    if (token == null || _grace <= Duration.zero) {
      _giveUp();
      return;
    }
    reconnecting = true;
    notifyListeners();
    unawaited(_subscription?.cancel());
    unawaited(_channel.sink.close());
    unawaited(_reconnect(token));
  }

  void _giveUp() {
    reconnecting = false;
    disconnectReason = DisconnectReason.connectionLost;
    notifyListeners();
  }

  /// Tries to take the seat back until the server's grace period is over.
  Future<void> _reconnect(String token) async {
    final elapsed = Stopwatch()..start();
    while (disconnectReason == null) {
      try {
        await _handshake(
          _uri,
          {'protocol': kProtocolVersion, 'resume': token},
          _timeout,
          onWelcome: (welcome, link) {
            if (disconnectReason != null) {
              // Left while reconnecting: free the seat right away.
              link.channel.sink.add(encodeMessage(Msg.leave));
              unawaited(link.subscription.cancel());
              unawaited(link.channel.sink.close());
              return;
            }
            _attach(welcome, link);
            reconnecting = false;
          },
          onMessage: _handle,
          onDone: _onConnectionClosed,
        );
        if (!reconnecting) notifyListeners();
        return;
      } on JoinException catch (e) {
        if (disconnectReason != null) return;
        if (e.code != JoinException.unreachable) {
          _giveUp(); // The seat is gone.
          return;
        }
      }
      if (elapsed.elapsed >= _grace) {
        _giveUp();
        return;
      }
      await Future<void>.delayed(_retryInterval);
    }
  }

  void _send(String type, [Json body = const {}]) {
    if (!isConnected || reconnecting) return;
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

  /// Leaves for good: the server frees the seat instead of keeping it.
  Future<void> leave() async {
    if (disconnectReason == null) _send(Msg.leave);
    disconnectReason ??= DisconnectReason.left;
    reconnecting = false;
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
