import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/net/caster_link.dart';
import 'package:nico_in_the_box/net/game_server.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_game.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';

/// A stand-in Caster: speaks the /cast handshake and records what it gets.
class FakeCaster {
  FakeCaster._(this._http, {required this.busy});

  static Future<FakeCaster> start({bool busy = false}) async {
    final caster = FakeCaster._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      busy: busy,
    );
    caster._http.listen(caster._handle);
    return caster;
  }

  final HttpServer _http;
  final bool busy;
  final received = <Json>[];
  WebSocket? socket;
  final _changes = StreamController<void>.broadcast();

  int get port => _http.port;

  Future<void> _handle(HttpRequest request) async {
    final ws = await WebSocketTransformer.upgrade(request);
    ws.listen((raw) {
      final msg = decodeMessage(raw);
      if (msg['type'] == Msg.castHello) {
        if (busy) {
          ws.add(
            encodeMessage(Msg.error, {
              'code': ErrorCode.casterBusy,
              'msg': 'TV is already showing another room.',
            }),
          );
          unawaited(ws.close());
          return;
        }
        socket = ws;
        ws.add(encodeMessage(Msg.castWelcome, {'name': 'Living room TV'}));
      }
      received.add(msg);
      _changes.add(null);
    });
  }

  Future<void> until(bool Function() condition) async {
    if (condition()) return;
    await _changes.stream
        .firstWhere((_) => condition())
        .timeout(const Duration(seconds: 15));
  }

  bool got(String type) => received.any((m) => m['type'] == type);

  Future<void> close() async {
    await socket?.close();
    await _http.close(force: true);
  }
}

Future<void> until(GameClient client, bool Function() condition) {
  if (condition()) return Future.value();
  final done = Completer<void>();
  void check() {
    if (!done.isCompleted && condition()) done.complete();
  }

  client.addListener(check);
  return done.future
      .timeout(const Duration(seconds: 15))
      .whenComplete(() => client.removeListener(check));
}

void main() {
  late GameServer server;
  late GameClient host;
  final casters = <FakeCaster>[];

  Future<FakeCaster> caster({bool busy = false}) async {
    final c = await FakeCaster.start(busy: busy);
    casters.add(c);
    return c;
  }

  Future<CasterLink> link(FakeCaster c) => CasterLink.connect(
    server: server,
    host: '127.0.0.1',
    port: c.port,
    hostName: 'Nico',
  );

  setUp(() async {
    server = GameServer(
      roomName: 'Friday night',
      game: ticTacToeDefinition,
      display: const DisplaySettings(
        enabled: true,
        target: DisplayTarget.caster,
      ),
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    host = await GameClient.connect(
      host: '127.0.0.1',
      port: server.port,
      nickname: 'Nico',
      hostToken: server.hostToken,
    );
  });

  tearDown(() async {
    await host.leave();
    await server.close();
    for (final c in casters) {
      await c.close();
    }
    casters.clear();
  });

  test('a connected Caster becomes a shared screen and gets updates', () async {
    final tv = await caster();
    final linked = await link(tv);
    expect(linked.name, 'Living room TV');

    // The hello told the Caster which room and host it shows.
    final hello = tv.received.firstWhere((m) => m['type'] == Msg.castHello);
    expect(hello['room'], 'Friday night');
    expect(hello['host'], 'Nico');
    expect(hello['protocol'], kProtocolVersion);

    await tv.until(() => tv.got(Msg.display));
    await until(host, () => host.lobby?.sharedScreenActive ?? false);
    final screen = host.lobby!.displays.single;
    expect(screen.kind, DisplayKind.caster);
    expect(screen.name, 'Living room TV');
  });

  test('a busy Caster is refused with its reason', () async {
    final tv = await caster(busy: true);
    await expectLater(
      link(tv),
      throwsA(
        isA<CasterException>()
            .having((e) => e.code, 'code', ErrorCode.casterBusy)
            .having((e) => e.message, 'message', contains('another room')),
      ),
    );
    expect(server.lobbyState.displays, isEmpty);
  });

  test('an address with no Caster is reported as unreachable', () async {
    final tv = await caster();
    final port = tv.port;
    await tv.close();
    casters.remove(tv);
    await expectLater(
      CasterLink.connect(
        server: server,
        host: '127.0.0.1',
        port: port,
        hostName: 'Nico',
        timeout: const Duration(seconds: 2),
      ),
      throwsA(
        isA<CasterException>().having(
          (e) => e.code,
          'code',
          CasterException.unreachable,
        ),
      ),
    );
  });

  test('if the Caster drops, players are told and fall back', () async {
    final tv = await caster();
    await link(tv);
    await until(host, () => host.lobby?.sharedScreenActive ?? false);

    final notice = host.notices.first;
    await tv.socket!.close();
    expect(
      await notice.timeout(const Duration(seconds: 15)),
      contains('"Living room TV" disconnected'),
    );
    await until(host, () => host.lobby?.sharedScreenActive == false);
  });

  test('the host disconnecting sends the Caster back to waiting', () async {
    final tv = await caster();
    final linked = await link(tv);
    await until(host, () => host.lobby?.sharedScreenActive ?? false);

    var noticed = false;
    final sub = host.notices.listen((_) => noticed = true);
    await linked.disconnect();
    await tv.until(() => tv.got(Msg.closed));
    await until(host, () => host.lobby?.sharedScreenActive == false);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();
    expect(noticed, isFalse, reason: 'the host chose this; no alarm');
    expect(linked.isConnected, isFalse);
  });

  test('closing the room releases the Caster', () async {
    final tv = await caster();
    await link(tv);
    await tv.until(() => tv.got(Msg.display));
    await server.close();
    await tv.until(() => tv.got(Msg.closed));
  });
}
