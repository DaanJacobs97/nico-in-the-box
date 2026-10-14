import 'dart:async';
import 'dart:math';

import '../games/game_session.dart';
import 'discovery.dart';
import 'game_client.dart';
import 'game_server.dart';

/// Everything the host device runs for a room: the server, the LAN
/// announcer, and the host's own (auto-joined) client connection.
class HostedRoom {
  HostedRoom._(this.server, this._broadcaster, this.client, this.addresses);

  final GameServer server;
  final RoomBroadcaster? _broadcaster;
  final GameClient client;

  /// This device's LAN addresses, for players who join manually.
  final List<String> addresses;

  int get port => server.port;

  /// Starts the server, begins announcing it, and joins it as the host.
  static Future<HostedRoom> create({
    required String roomName,
    required GameDefinition game,
    required String nickname,
  }) async {
    final server = GameServer(roomName: roomName, game: game);
    await server.start();

    final serverId = List.generate(
      8,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    RoomBroadcaster? broadcaster = RoomBroadcaster(
      announcement: () => encodeAnnouncement(
        serverId: serverId,
        port: server.port,
        lobby: server.lobbyState,
        gameName: server.game.name,
      ),
    );
    try {
      await broadcaster.start();
    } on Object {
      // Players can still join by typing the host's IP address.
      broadcaster = null;
    }

    try {
      final client = await GameClient.connect(
        host: '127.0.0.1',
        port: server.port,
        nickname: nickname,
        hostToken: server.hostToken,
      );
      return HostedRoom._(
        server,
        broadcaster,
        client,
        await localIPv4Addresses(),
      );
    } on Object {
      broadcaster?.stop();
      await server.close();
      rethrow;
    }
  }

  Future<void> close() async {
    _broadcaster?.stop();
    await client.leave();
    await server.close();
  }
}
