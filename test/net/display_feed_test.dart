import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/net/game_server.dart';
import 'package:nico_shared/games/color_clash/color_clash_game.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_game.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';

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

/// A browser shared screen connected to `/display`, recording what it gets.
class FakeScreen {
  FakeScreen._(this._socket) {
    _socket.listen((raw) {
      final msg = decodeMessage(raw);
      messages.add(msg);
      _changes.add(null);
    });
  }

  static Future<FakeScreen> connect(int port) async => FakeScreen._(
    await WebSocket.connect('ws://127.0.0.1:$port$kDisplayPath'),
  );

  final WebSocket _socket;
  final messages = <Json>[];
  final _changes = StreamController<void>.broadcast();

  DisplayState? get latest {
    final displays = messages.where((m) => m['type'] == Msg.display);
    return displays.isEmpty ? null : DisplayState.fromJson(displays.last);
  }

  Future<void> until(bool Function() condition) async {
    if (condition()) return;
    await _changes.stream
        .firstWhere((_) => condition())
        .timeout(const Duration(seconds: 15));
  }

  Future<void> close() => _socket.close();
}

void main() {
  late GameServer server;
  final clients = <GameClient>[];
  final screens = <FakeScreen>[];

  Future<void> startServer({
    DisplaySettings display = DisplaySettings.off,
    bool clash = false,
  }) async {
    server = GameServer(
      roomName: 'Screen room',
      game: clash ? colorClashDefinition : ticTacToeDefinition,
      display: display,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  }

  Future<GameClient> join(String nickname, {bool asHost = false}) async {
    final client = await GameClient.connect(
      host: '127.0.0.1',
      port: server.port,
      nickname: nickname,
      hostToken: asHost ? server.hostToken : null,
    );
    clients.add(client);
    return client;
  }

  Future<FakeScreen> screen() async {
    final s = await FakeScreen.connect(server.port);
    screens.add(s);
    return s;
  }

  tearDown(() async {
    for (final s in screens) {
      await s.close();
    }
    screens.clear();
    for (final c in clients) {
      await c.leave();
    }
    clients.clear();
    await server.close();
  });

  test('a browser screen gets the lobby and shows up in it', () async {
    await startServer();
    final host = await join('Nico', asHost: true);
    final tv = await screen();

    await tv.until(() => tv.latest != null);
    expect(tv.latest!.lobby.roomName, 'Screen room');
    expect(tv.latest!.gameId, isNull);

    await until(host, () => host.lobby?.displays.length == 1);
    expect(host.lobby!.displays.single.kind, DisplayKind.browser);
    // Single game screen is still off, so players keep their full view.
    expect(host.lobby!.sharedScreenActive, isFalse);

    host.setDisplay(const DisplaySettings(enabled: true));
    await until(host, () => host.lobby?.sharedScreenActive ?? false);
  });

  test('the table on screen never includes a hand', () async {
    await startServer(clash: true);
    final host = await join('Nico', asHost: true);
    final guest = await join('Daan');
    final tv = await screen();
    await until(host, () => host.lobby?.players.length == 2);

    host.startGame();
    await tv.until(() => tv.latest?.table != null);
    final table = tv.latest!.table!;
    expect(tv.latest!.gameId, 'colorclash');
    expect(table.containsKey('hand'), isFalse);
    expect(table.containsKey('playable'), isFalse);
    final players = (table['players']! as List<Object?>).cast<Json>();
    expect(players.map((p) => p['cards']), [7, 7]);

    // Players still get their private view with their own hand.
    await until(guest, () => guest.gameView != null);
    expect(guest.gameView!['hand'], hasLength(7));
  });

  test('screens follow moves and see the result', () async {
    await startServer();
    final host = await join('Nico', asHost: true);
    final guest = await join('Daan');
    final tv = await screen();
    await until(host, () => host.lobby?.players.length == 2);
    host.startGame();
    await until(guest, () => guest.gameView != null);
    await until(host, () => host.gameView != null);

    for (final (who, cell) in [
      (host, 0),
      (guest, 3),
      (host, 1),
      (guest, 4),
      (host, 2),
    ]) {
      who.sendAction({'type': 'place', 'cell': cell});
      // The screen shows each move as it happens.
      await tv.until(() {
        final board = tv.latest?.table?['board'] as List<Object?>?;
        return board != null && board[cell] != null;
      });
    }
    await tv.until(() => tv.latest?.result != null);
    expect(tv.latest!.result!['winnerIds'], [host.playerId]);
    expect(tv.latest!.lobby.phase, RoomPhase.finished);
  });

  test('when the screen disconnects, players fall back to full view', () async {
    await startServer(display: const DisplaySettings(enabled: true));
    final host = await join('Nico', asHost: true);
    final tv = await screen();
    await until(host, () => host.lobby?.sharedScreenActive ?? false);

    await tv.close();
    await until(host, () => host.lobby?.sharedScreenActive == false);
    expect(host.lobby!.displays, isEmpty);
  });

  test(
    'only the host can change display settings, only in the lobby',
    () async {
      await startServer();
      final host = await join('Nico', asHost: true);
      final guest = await join('Daan');
      await until(guest, () => guest.lobby?.players.length == 2);

      final notice = guest.notices.first;
      guest.setDisplay(const DisplaySettings(enabled: true));
      expect(
        await notice.timeout(const Duration(seconds: 15)),
        contains('Only the host'),
      );

      host.startGame();
      await until(host, () => host.lobby?.phase == RoomPhase.playing);
      final inGame = host.notices.first;
      host.setDisplay(const DisplaySettings(enabled: true));
      expect(
        await inGame.timeout(const Duration(seconds: 15)),
        contains('End the current game'),
      );
      expect(host.lobby!.display.enabled, isFalse);
    },
  );

  group('host device as the screen', () {
    const hostIsScreen = DisplaySettings(enabled: true, hostPlays: false);

    test('host takes no seat, keeps control and sees the table', () async {
      await startServer(display: hostIsScreen);
      final host = await join('Nico', asHost: true);
      final a = await join('Ann');
      final b = await join('Bob');
      await until(host, () => host.lobby?.players.length == 2);

      final lobby = host.lobby!;
      expect(lobby.players.map((p) => p.nickname), ['Ann', 'Bob']);
      expect(lobby.hostId, host.playerId);
      expect(lobby.nicknameOf(host.playerId), 'Nico');
      expect(lobby.displays.single.kind, DisplayKind.host);
      expect(lobby.sharedScreenActive, isTrue);

      // Tic Tac Toe holds two: the room is full without the host.
      await expectLater(
        join('Cat'),
        throwsA(
          isA<JoinException>().having(
            (e) => e.code,
            'code',
            ErrorCode.roomFull,
          ),
        ),
      );

      host.startGame();
      await until(a, () => a.gameView != null);
      await until(host, () => host.displayState?.table != null);
      expect(host.gameView, isNull);
      final marks = host.displayState!.table!['marks']! as Json;
      expect(marks.keys, unorderedEquals([a.playerId, b.playerId]));
      expect(b.isConnected, isTrue);
    });

    test('nobody can take the host\'s nickname', () async {
      await startServer(display: hostIsScreen);
      await join('Nico', asHost: true);
      await expectLater(
        join('nico'),
        throwsA(
          isA<JoinException>().having(
            (e) => e.code,
            'code',
            ErrorCode.nameTaken,
          ),
        ),
      );
    });

    test('host can only take a seat back when one is free', () async {
      await startServer(display: hostIsScreen);
      final host = await join('Nico', asHost: true);
      await join('Ann');
      await join('Bob');
      await until(host, () => host.lobby?.players.length == 2);

      final notice = host.notices.first;
      host.setDisplay(const DisplaySettings(enabled: true));
      expect(
        await notice.timeout(const Duration(seconds: 15)),
        contains('full'),
      );
      expect(host.lobby!.display.hostPlays, isFalse);
    });
  });

  test(
    '"this device is the screen" only applies while the screen is on',
    () async {
      await startServer(
        display: const DisplaySettings(enabled: false, hostPlays: false),
      );
      final host = await join('Nico', asHost: true);
      await until(host, () => host.lobby?.players.length == 1);
      expect(host.lobby!.players.single.nickname, 'Nico');

      host.setDisplay(const DisplaySettings(enabled: true, hostPlays: false));
      await until(host, () => host.lobby?.players.isEmpty ?? false);
      expect(host.lobby!.displays.single.kind, DisplayKind.host);
    },
  );

  test('closing the room tells screens', () async {
    await startServer();
    final host = await join('Nico', asHost: true);
    final tv = await screen();
    await tv.until(() => tv.latest != null);

    host.closeRoom();
    await tv.until(() => tv.messages.any((m) => m['type'] == Msg.closed));
  });
}
