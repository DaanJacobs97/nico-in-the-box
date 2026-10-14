import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nico_shared/net/protocol.dart';

/// The Caster's WebSocket server. A host connects to `/cast`, says
/// [Msg.castHello], and then pushes [Msg.display] updates for this screen to
/// show. One host at a time: others are told [ErrorCode.casterBusy].
class CastServer extends ChangeNotifier {
  CastServer({required this.name});

  /// This screen's name, sent to the host in the welcome.
  String Function() name;

  HttpServer? _http;
  WebSocket? _host;

  /// The connected host's nickname and room, while one is connected.
  String? hostName;
  String? roomName;

  /// Latest state to show; null until the first update arrives.
  DisplayState? display;

  bool get isBusy => _host != null;
  int get port => _http!.port;

  /// Binds to [port], trying the next few if it is taken (`port: 0` lets
  /// the OS choose, for tests).
  Future<void> start({
    int port = kCasterPort,
    InternetAddress? address,
    int attempts = 10,
  }) async {
    SocketException? lastError;
    for (var i = 0; i < (port == 0 ? 1 : attempts); i++) {
      try {
        _http = await HttpServer.bind(
          address ?? InternetAddress.anyIPv4,
          port == 0 ? 0 : port + i,
        );
        break;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    if (_http == null) throw lastError!;
    _http!.listen((request) => unawaited(_handle(request)));
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path != kCastPath ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } on Object {
      return;
    }
    socket.pingInterval = const Duration(seconds: 5);

    var greeted = false;
    final helloTimeout = Timer(const Duration(seconds: 5), () {
      if (!greeted) unawaited(socket.close());
    });
    socket.listen(
      (raw) {
        final Json msg;
        try {
          msg = decodeMessage(raw);
        } on FormatException {
          return;
        }
        if (!greeted) {
          greeted = true;
          helloTimeout.cancel();
          _onHello(socket, msg);
        } else if (socket == _host) {
          _onHostMessage(msg);
        }
      },
      onDone: () {
        helloTimeout.cancel();
        if (socket == _host) _release();
      },
      onError: (Object _) {},
      cancelOnError: true,
    );
  }

  void _onHello(WebSocket socket, Json msg) {
    String? refusal;
    var code = ErrorCode.badMessage;
    if (msg['type'] != Msg.castHello) {
      refusal = 'Expected castHello.';
    } else if (msg['protocol'] != kProtocolVersion) {
      code = ErrorCode.protocolMismatch;
      refusal = 'This Caster runs a different app version.';
    } else if (_host != null) {
      code = ErrorCode.casterBusy;
      refusal = '${name()} is already showing $roomName.';
    }
    if (refusal != null) {
      socket.add(encodeMessage(Msg.error, {'code': code, 'msg': refusal}));
      unawaited(socket.close());
      return;
    }
    _host = socket;
    hostName = msg['host'] as String? ?? '';
    roomName = msg['room'] as String? ?? '';
    socket.add(encodeMessage(Msg.castWelcome, {'name': name()}));
    notifyListeners();
  }

  void _onHostMessage(Json msg) {
    switch (msg['type']) {
      case Msg.display:
        try {
          display = DisplayState.fromJson(msg);
        } on Object {
          return;
        }
        notifyListeners();
      case Msg.closed:
        // The room is gone; wait for the next host.
        unawaited(_host?.close());
        _release();
    }
  }

  void _release() {
    _host = null;
    hostName = null;
    roomName = null;
    display = null;
    notifyListeners();
  }

  Future<void> close() async {
    await _host?.close();
    _host = null;
    await _http?.close(force: true);
  }
}
