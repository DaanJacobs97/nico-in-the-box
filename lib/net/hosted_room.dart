import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';

import 'discovery.dart';
import 'game_server.dart';
import 'web_files.dart';

/// Asset built by tool/build_web_client; absent in builds made without it.
const webClientAsset = 'assets/generated/web_client.zip';

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

  /// Whether players without the app can join from a browser at `/play/`.
  bool get hasWebClient => server.webClient != null;

  /// Starts the server, begins announcing it, and joins it as the host.
  static Future<HostedRoom> create({
    required String roomName,
    required GameDefinition game,
    required String nickname,
    DisplaySettings display = DisplaySettings.off,
  }) async {
    final server = GameServer(
      roomName: roomName,
      game: game,
      webClient: await _loadWebClient(),
      display: display,
    );
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

  /// Closes the room for everyone. The server goes first so guests are told
  /// the host closed it; dropping the host's own connection first would make
  /// the server report that the host left instead.
  Future<void> close() async {
    _broadcaster?.stop();
    await server.close(reason: CloseReason.hostClosed);
    await client.leave();
  }

  /// Unpacks the bundled browser client, or returns null when this build
  /// doesn't include it.
  static Future<WebFiles?> _loadWebClient() async {
    final ByteData data;
    try {
      data = await rootBundle.load(webClientAsset);
    } on Object {
      return null;
    }
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    // A few MB of zip: unpack off the UI thread.
    return Isolate.run(() => MemoryWebFiles.fromZip(bytes));
  }
}
