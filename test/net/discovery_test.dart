import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/net/discovery.dart';
import 'package:nico_in_the_box/net/protocol.dart';

const _lobby = LobbyState(
  roomName: 'Friday night',
  gameId: 'tictactoe',
  players: [PlayerInfo(id: 'p1', nickname: 'Nico')],
  minPlayers: 2,
  maxPlayers: 2,
  hostId: 'p1',
  phase: RoomPhase.lobby,
);

List<int> _announce({String id = 'srv1', LobbyState lobby = _lobby}) =>
    encodeAnnouncement(
      serverId: id,
      port: 47800,
      lobby: lobby,
      gameName: 'Tic Tac Toe',
    );

void main() {
  test('announcement round trip', () {
    final from = InternetAddress('192.168.1.20');
    final room = parseAnnouncement(_announce(), from)!;
    expect(room.serverId, 'srv1');
    expect(room.address, from);
    expect(room.port, 47800);
    expect(room.roomName, 'Friday night');
    expect(room.hostNickname, 'Nico');
    expect(room.gameName, 'Tic Tac Toe');
    expect(room.players, 1);
    expect(room.maxPlayers, 2);
    expect(room.isJoinable, isTrue);
  });

  test('full or in-game rooms are not joinable', () {
    const full = LobbyState(
      roomName: 'r',
      gameId: 'tictactoe',
      players: [
        PlayerInfo(id: 'p1', nickname: 'A'),
        PlayerInfo(id: 'p2', nickname: 'B'),
      ],
      minPlayers: 2,
      maxPlayers: 2,
      hostId: 'p1',
      phase: RoomPhase.lobby,
    );
    final from = InternetAddress.loopbackIPv4;
    expect(
      parseAnnouncement(_announce(lobby: full), from)!.isJoinable,
      isFalse,
    );
  });

  test('ignores foreign packets and other protocol versions', () {
    final from = InternetAddress.loopbackIPv4;
    expect(parseAnnouncement(utf8.encode('hello'), from), isNull);
    expect(parseAnnouncement(utf8.encode('{"app":"other"}'), from), isNull);
    expect(
      parseAnnouncement(
        utf8.encode(jsonEncode({'app': kDiscoveryAppId, 'v': -1})),
        from,
      ),
      isNull,
    );
    expect(parseAnnouncement([0xff, 0xfe], from), isNull);
  });

  test('scanner hears a broadcaster over loopback', () async {
    // Use a non-default port so a running app doesn't interfere.
    const port = 47911;
    final scanner = RoomScanner(port: port);
    await scanner.start();
    expect(scanner.error, isNull);

    final broadcaster = RoomBroadcaster(
      announcement: _announce,
      port: port,
      interval: const Duration(milliseconds: 100),
      targets: [InternetAddress.loopbackIPv4],
    );
    await broadcaster.start();

    final found = Completer<void>();
    void check() {
      if (scanner.rooms.isNotEmpty && !found.isCompleted) found.complete();
    }

    scanner.addListener(check);
    check();
    await found.future.timeout(const Duration(seconds: 3));
    scanner.removeListener(check);

    expect(scanner.rooms.single.roomName, 'Friday night');
    expect(scanner.rooms.single.address.isLoopback, isTrue);

    broadcaster.stop();
    scanner.dispose();
  });
}
