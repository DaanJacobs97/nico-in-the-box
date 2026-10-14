import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/games/game_session.dart';
import 'package:nico_in_the_box/games/tictactoe/tictactoe_game.dart';
import 'package:nico_in_the_box/net/game_client.dart';
import 'package:nico_in_the_box/net/game_server.dart';
import 'package:nico_in_the_box/net/protocol.dart';

class _IdleSession implements GameSession {
  @override
  void applyAction(String playerId, Json action) {}
  @override
  Json viewFor(String playerId) => {};
  @override
  bool get isOver => false;
  @override
  Json? get result => null;
}

final _threeSeatGame = GameDefinition(
  id: 'idle',
  name: 'Idle',
  description: 'Test game with three seats.',
  minPlayers: 2,
  maxPlayers: 3,
  createSession: (_, _, _) => _IdleSession(),
);

/// Waits until [condition] holds after a change notification from [client].
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
  final clients = <GameClient>[];

  Future<GameClient> join(String nickname, {bool asHost = false}) async {
    final client = await GameClient.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      nickname: nickname,
      hostToken: asHost ? server.hostToken : null,
    );
    clients.add(client);
    return client;
  }

  setUp(() async {
    server = GameServer(
      roomName: 'Test room',
      game: ticTacToeDefinition,
      random: Random(42),
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    for (final c in clients) {
      await c.leave();
    }
    clients.clear();
    await server.close();
  });

  test('host auto-joins with host rights and a guest sees the lobby', () async {
    final host = await join('Nico', asHost: true);
    expect(host.isHost, isTrue);
    final guest = await join('Daan');
    expect(guest.isHost, isFalse);

    await until(guest, () => guest.lobby?.players.length == 2);
    final lobby = guest.lobby!;
    expect(lobby.hostId, host.playerId);
    expect(lobby.players.map((p) => p.nickname), ['Nico', 'Daan']);
    expect(lobby.maxPlayers, 2);
    expect(lobby.phase, RoomPhase.lobby);
  });

  test('two players play tic tac toe to a win, then restart swaps X', () async {
    final host = await join('Nico', asHost: true);
    final guest = await join('Daan');
    await until(host, () => host.lobby?.players.length == 2);

    host.startGame();
    // Each client receives its own copy of the board; wait for both.
    await until(guest, () => guest.gameView != null);
    await until(host, () => host.gameView != null);
    expect(guest.gameView!['turn'], host.playerId);

    Future<void> place(GameClient who, int cell, int expectedFilled) async {
      who.sendAction({'type': 'place', 'cell': cell});
      await until(
        who,
        () =>
            (who.gameView!['board']! as List<Object?>)
                .whereType<String>()
                .length ==
            expectedFilled,
      );
    }

    await place(host, 0, 1);
    await place(guest, 3, 2);
    await place(host, 1, 3);
    await place(guest, 4, 4);
    await place(host, 2, 5);

    await until(guest, () => guest.gameResult != null);
    expect(guest.gameResult!['winnerIds'], [host.playerId]);
    expect(guest.lobby!.phase, RoomPhase.finished);

    host.restartGame();
    await until(
      guest,
      () => guest.lobby!.phase == RoomPhase.playing && guest.gameResult == null,
    );
    expect(guest.gameView!['turn'], guest.playerId);
  });

  test('duplicate nickname is rejected, ignoring case', () async {
    await join('Nico', asHost: true);
    await expectLater(
      join('  nICO '),
      throwsA(
        isA<JoinException>().having((e) => e.code, 'code', ErrorCode.nameTaken),
      ),
    );
  });

  test('blank nickname is rejected', () async {
    await expectLater(
      join('   '),
      throwsA(
        isA<JoinException>().having(
          (e) => e.code,
          'code',
          ErrorCode.invalidName,
        ),
      ),
    );
  });

  test(
    'room is full once the game max is reached (host seat reserved)',
    () async {
      await join('Guest1');
      await expectLater(
        join('Guest2'),
        throwsA(
          isA<JoinException>().having(
            (e) => e.code,
            'code',
            ErrorCode.roomFull,
          ),
        ),
      );
      final host = await join('Nico', asHost: true);
      expect(host.isHost, isTrue);
    },
  );

  test('a non-host cannot restart, start or kick', () async {
    final host = await join('Nico', asHost: true);
    final guest = await join('Daan');
    await until(guest, () => guest.lobby?.players.length == 2);

    final notices = <String>[];
    final sub = guest.notices.listen(notices.add);
    guest.startGame();
    guest.restartGame();
    guest.kick(host.playerId);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();

    expect(notices, hasLength(3));
    expect(notices, everyElement(contains('Only the host')));
    expect(guest.lobby!.phase, RoomPhase.lobby);
    expect(server.players, hasLength(2));
  });

  test('host can kick a player mid-game, which returns to the lobby', () async {
    final host = await join('Nico', asHost: true);
    final guest = await join('Daan');
    await until(host, () => host.lobby?.players.length == 2);
    host.startGame();
    await until(host, () => host.lobby!.phase == RoomPhase.playing);

    host.kick(guest.playerId);
    await until(guest, () => guest.disconnectReason != null);
    expect(guest.disconnectReason, DisconnectReason.kicked);
    await until(
      host,
      () =>
          host.lobby!.players.length == 1 &&
          host.lobby!.phase == RoomPhase.lobby,
    );
    expect(host.gameView, isNull);
  });

  test('joining during a game is refused even with a free seat', () async {
    await server.close();
    server = GameServer(roomName: 'Big room', game: _threeSeatGame);
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);

    final host = await join('Nico', asHost: true);
    await join('Daan');
    await until(host, () => host.lobby?.players.length == 2);
    host.startGame();
    await until(host, () => host.lobby!.phase == RoomPhase.playing);

    await expectLater(
      join('Late'),
      throwsA(
        isA<JoinException>().having(
          (e) => e.code,
          'code',
          ErrorCode.gameInProgress,
        ),
      ),
    );
  });

  test('host can change game, which resizes the room', () async {
    final host = await join('Nico', asHost: true);
    await join('Daan');
    await until(host, () => host.lobby?.players.length == 2);

    host.changeGame('colorclash');
    await until(host, () => host.lobby!.maxPlayers == 4);
    final third = await join('Kim');
    await until(third, () => third.lobby?.players.length == 3);

    // Three players don't fit in Tic Tac Toe any more.
    final notice = host.notices.first;
    host.changeGame('tictactoe');
    expect(
      await notice.timeout(const Duration(seconds: 15)),
      contains('at most 2'),
    );
    expect(host.lobby!.gameId, 'colorclash');

    host.startGame();
    await until(third, () => third.gameId == 'colorclash');
    final hand = third.gameView!['hand']! as List<Object?>;
    expect(hand, hasLength(7));
  });

  test('a client with another protocol version is rejected', () async {
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}$kWebSocketPath',
    );
    socket.add(encodeMessage(Msg.hello, {'nickname': 'Old', 'protocol': -1}));
    final reply = decodeMessage(await socket.first);
    expect(reply['type'], Msg.error);
    expect(reply['code'], ErrorCode.protocolMismatch);
    await socket.close();
  });

  test('closing the room disconnects everyone with hostClosed', () async {
    final host = await join('Nico', asHost: true);
    final guest = await join('Daan');
    await until(guest, () => guest.lobby?.players.length == 2);

    host.closeRoom();
    await until(guest, () => guest.disconnectReason != null);
    expect(guest.disconnectReason, DisconnectReason.hostClosed);
    expect(server.isRunning, isFalse);
  });

  test('host leaving closes the room with hostLeft', () async {
    final host = await join('Nico', asHost: true);
    final guest = await join('Daan');
    await until(guest, () => guest.lobby?.players.length == 2);

    await host.leave();
    await until(guest, () => guest.disconnectReason != null);
    expect(guest.disconnectReason, DisconnectReason.hostLeft);
  });

  test('guest leaving notifies the host', () async {
    final host = await join('Nico', asHost: true);
    final guest = await join('Daan');
    await until(host, () => host.lobby?.players.length == 2);

    final notice = host.notices.first;
    await guest.leave();
    expect(await notice.timeout(const Duration(seconds: 15)), 'Daan left.');
    await until(host, () => host.lobby!.players.length == 1);
  });

  test('unreachable host gives a JoinException', () async {
    final port = server.port;
    await server.close();
    await expectLater(
      GameClient.connect(
        host: '127.0.0.1',
        port: port,
        nickname: 'Late',
        timeout: const Duration(seconds: 2),
      ),
      throwsA(
        isA<JoinException>().having(
          (e) => e.code,
          'code',
          JoinException.unreachable,
        ),
      ),
    );
  });
}
