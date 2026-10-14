import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_caster/cast_server.dart';
import 'package:nico_shared/net/protocol.dart';

/// A host connected to the Caster, recording its replies.
class FakeHost {
  FakeHost._(this.socket) {
    socket.listen(
      (raw) => replies.add(decodeMessage(raw)),
      onDone: () => done.complete(),
    );
  }

  static Future<FakeHost> connect(int port) async =>
      FakeHost._(await WebSocket.connect('ws://127.0.0.1:$port$kCastPath'));

  final WebSocket socket;
  final replies = <Json>[];
  final done = Completer<void>();

  void hello({int protocol = kProtocolVersion}) => socket.add(
    encodeMessage(Msg.castHello, {
      'protocol': protocol,
      'room': 'Friday night',
      'host': 'Nico',
    }),
  );

  Future<Json> firstReply() async {
    for (var i = 0; i < 150 && replies.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return replies.first;
  }
}

Future<void> until(CastServer server, bool Function() condition) {
  if (condition()) return Future.value();
  final done = Completer<void>();
  void check() {
    if (!done.isCompleted && condition()) done.complete();
  }

  server.addListener(check);
  return done.future
      .timeout(const Duration(seconds: 10))
      .whenComplete(() => server.removeListener(check));
}

const _lobby = LobbyState(
  roomName: 'Friday night',
  gameId: 'tictactoe',
  players: [PlayerInfo(id: 'p1', nickname: 'Nico')],
  minPlayers: 2,
  maxPlayers: 2,
  hostId: 'p1',
  phase: RoomPhase.lobby,
);

void main() {
  late CastServer server;
  final hosts = <FakeHost>[];

  Future<FakeHost> host() async {
    final h = await FakeHost.connect(server.port);
    hosts.add(h);
    return h;
  }

  setUp(() async {
    server = CastServer(name: () => 'Living room TV');
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    for (final h in hosts) {
      await h.socket.close();
    }
    hosts.clear();
    await server.close();
  });

  test('a host is welcomed and its updates are shown', () async {
    final h = await host();
    h.hello();
    final welcome = await h.firstReply();
    expect(welcome['type'], Msg.castWelcome);
    expect(welcome['name'], 'Living room TV');
    await until(server, () => server.isBusy);
    expect(server.roomName, 'Friday night');
    expect(server.hostName, 'Nico');

    h.socket.add(
      encodeMessage(Msg.display, const DisplayState(lobby: _lobby).toJson()),
    );
    await until(server, () => server.display != null);
    expect(server.display!.lobby.roomName, 'Friday night');
  });

  test('a second host is told the Caster is busy', () async {
    final first = await host();
    first.hello();
    await until(server, () => server.isBusy);

    final second = await host();
    second.hello();
    final reply = await second.firstReply();
    expect(reply['type'], Msg.error);
    expect(reply['code'], ErrorCode.casterBusy);
    expect(reply['msg'], contains('Friday night'));
    await second.done.future.timeout(const Duration(seconds: 5));
    // The first host keeps the screen.
    expect(server.hostName, 'Nico');
  });

  test('another app version is refused', () async {
    final h = await host();
    h.hello(protocol: -1);
    final reply = await h.firstReply();
    expect(reply['code'], ErrorCode.protocolMismatch);
    expect(server.isBusy, isFalse);
  });

  test('when the host leaves or the room closes, it is free again', () async {
    final first = await host();
    first.hello();
    await until(server, () => server.isBusy);
    await first.socket.close();
    await until(server, () => !server.isBusy);
    expect(server.display, isNull);

    final second = await host();
    second.hello();
    expect((await second.firstReply())['type'], Msg.castWelcome);
    await until(server, () => server.isBusy);
    second.socket.add(encodeMessage(Msg.closed, {'reason': 'hostClosed'}));
    await until(server, () => !server.isBusy);
  });

  test('a connection that never says hello is dropped', () async {
    final h = await host();
    await h.done.future.timeout(const Duration(seconds: 10));
    expect(server.isBusy, isFalse);
  });
}
