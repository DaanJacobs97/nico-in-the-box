import 'dart:async';
import 'dart:io';

import 'package:nico_shared/net/protocol.dart';

import 'game_server.dart';

/// Why a Caster could not be used.
class CasterException implements Exception {
  const CasterException(this.code, this.message);

  /// An [ErrorCode] (e.g. [ErrorCode.casterBusy]) or `'unreachable'`.
  final String code;
  final String message;

  static const unreachable = 'unreachable';

  @override
  String toString() => 'CasterException($code): $message';
}

/// The host's connection to a Caster app. Once connected, the Caster is one
/// of the room's shared screens and receives every display update.
class CasterLink {
  CasterLink._(this._socket, this.name, this._server);

  final WebSocket _socket;
  final GameServer _server;

  /// The Caster's name, as it introduced itself.
  final String name;

  DisplayHandle? _display;
  bool _closing = false;

  bool get isConnected => _display != null;

  /// Connects to the Caster at [host]:[port] and attaches it to [server].
  static Future<CasterLink> connect({
    required GameServer server,
    required String host,
    required int port,
    required String hostName,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final WebSocket socket;
    try {
      socket = await WebSocket.connect('ws://$host:$port$kCastPath')
          .timeout(timeout);
    } on Object {
      throw CasterException(
        CasterException.unreachable,
        'Could not reach a Caster at $host:$port.',
      );
    }
    socket.pingInterval = const Duration(seconds: 5);

    final reply = Completer<Json>();
    late final CasterLink link;
    var linked = false;
    socket.listen(
      (raw) {
        final Json msg;
        try {
          msg = decodeMessage(raw);
        } on FormatException {
          return;
        }
        if (!reply.isCompleted) reply.complete(msg);
      },
      onDone: () {
        if (!reply.isCompleted) {
          reply.completeError(
            const CasterException(
              CasterException.unreachable,
              'The Caster closed the connection.',
            ),
          );
        } else if (linked) {
          link._onClosed();
        }
      },
      onError: (Object _) {},
    );
    socket.add(
      encodeMessage(Msg.castHello, {
        'protocol': kProtocolVersion,
        'room': server.roomName,
        'host': hostName,
      }),
    );

    final Json welcome;
    try {
      welcome = await reply.future.timeout(timeout);
    } on Object catch (e) {
      await socket.close();
      if (e is CasterException) rethrow;
      throw const CasterException(
        CasterException.unreachable,
        'The Caster did not answer.',
      );
    }
    if (welcome['type'] != Msg.castWelcome) {
      await socket.close();
      throw CasterException(
        welcome['code'] as String? ?? ErrorCode.badMessage,
        welcome['msg'] as String? ?? 'The Caster refused the connection.',
      );
    }

    link = CasterLink._(socket, welcome['name'] as String? ?? 'Caster', server);
    linked = true;
    link._display = server.attachDisplay(
      kind: DisplayKind.caster,
      name: link.name,
      send: (message) {
        if (socket.readyState == WebSocket.open) socket.add(message);
      },
      close: socket.close,
    );
    return link;
  }

  /// The Caster went away on its own (closed, crashed, Wi-Fi dropped).
  void _onClosed() {
    final display = _display;
    if (display == null) return;
    _display = null;
    display.detach();
    if (!_closing && _server.isRunning) {
      _server.broadcastNotice(
        'The shared screen "$name" disconnected. Your device shows the '
        'whole table again until it is back.',
      );
    }
  }

  /// The host stops using this Caster; it returns to its waiting screen.
  Future<void> disconnect() async {
    _closing = true;
    _display?.detach();
    _display = null;
    if (_socket.readyState == WebSocket.open) {
      _socket.add(
        encodeMessage(Msg.closed, {'reason': CloseReason.hostClosed}),
      );
    }
    try {
      await _socket.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Already gone.
    }
  }
}
