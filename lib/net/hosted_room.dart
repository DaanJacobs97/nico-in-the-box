import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:nico_native/discovery.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/screen_awake.dart';

import 'caster_link.dart';
import 'display_frontend.dart';
import 'game_server.dart';
import 'web_files.dart';

/// Asset built by tool/build_web_client; absent in builds made without it.
const webClientAsset = 'assets/generated/web_client.zip';

/// Folder of the HTML/JS shared screen page served at `/screen/`.
const screenAssetDir = 'assets/display/';

/// Everything the host device runs for a room: the server, the LAN
/// announcer, and the host's own (auto-joined) client connection.
class HostedRoom {
  HostedRoom._(
    this.server,
    this._broadcaster,
    this.client,
    this.addresses,
    this.nickname,
  );

  final GameServer server;
  final RoomBroadcaster? _broadcaster;
  final GameClient client;

  /// This device's LAN addresses, for players who join manually.
  final List<String> addresses;

  /// The host's nickname, shown on Casters.
  final String nickname;

  CasterLink? _caster;
  bool _closed = false;

  /// The Caster showing this room, if any.
  CasterLink? get caster => (_caster?.isConnected ?? false) ? _caster : null;

  int get port => server.port;

  /// Whether a browser can show the shared screen at `/screen/`.
  bool get hasScreenPage => server.screenPage != null;

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
      screenPage: await _loadScreenPage(),
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
      ScreenAwake.hold();
      return HostedRoom._(
        server,
        broadcaster,
        client,
        await localIPv4Addresses(),
        nickname,
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
  /// Shows the room on the Caster at [host]:[port], replacing any Caster
  /// already connected. Throws [CasterException] if it can't be used.
  Future<void> connectCaster(String host, int port) async {
    final next = await CasterLink.connect(
      server: server,
      host: host,
      port: port,
      hostName: nickname,
    );
    final previous = _caster;
    _caster = next;
    await previous?.disconnect();
  }

  /// Stops showing the room on the Caster; it returns to waiting.
  Future<void> disconnectCaster() async {
    final link = _caster;
    _caster = null;
    await link?.disconnect();
  }

  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      ScreenAwake.release();
    }
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

  /// Loads the shared screen page's files from the app's assets.
  static Future<DisplayFrontend?> _loadScreenPage() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final files = <String, List<int>>{};
      for (final asset in manifest.listAssets()) {
        if (!asset.startsWith(screenAssetDir)) continue;
        final data = await rootBundle.load(asset);
        files[asset.substring(screenAssetDir.length)] = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      }
      if (!files.containsKey('index.html')) return null;
      return HtmlDisplayFrontend(MemoryWebFiles(files));
    } on Object {
      return null;
    }
  }
}
