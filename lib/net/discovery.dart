import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'protocol.dart';

/// A room heard on the network.
class DiscoveredRoom {
  const DiscoveredRoom({
    required this.serverId,
    required this.address,
    required this.port,
    required this.roomName,
    required this.hostNickname,
    required this.gameId,
    required this.gameName,
    required this.players,
    required this.maxPlayers,
    required this.phase,
    required this.lastSeen,
  });

  /// Random per-room id, so one host heard on several addresses shows once.
  final String serverId;
  final InternetAddress address;
  final int port;
  final String roomName;
  final String hostNickname;
  final String gameId;
  final String gameName;
  final int players;
  final int maxPlayers;
  final RoomPhase phase;
  final DateTime lastSeen;

  bool get isJoinable => phase == RoomPhase.lobby && players < maxPlayers;

  DiscoveredRoom copyWith({InternetAddress? address}) => DiscoveredRoom(
    serverId: serverId,
    address: address ?? this.address,
    port: port,
    roomName: roomName,
    hostNickname: hostNickname,
    gameId: gameId,
    gameName: gameName,
    players: players,
    maxPlayers: maxPlayers,
    phase: phase,
    lastSeen: lastSeen,
  );
}

/// Builds the announcement a host broadcasts.
List<int> encodeAnnouncement({
  required String serverId,
  required int port,
  required LobbyState lobby,
  required String gameName,
}) {
  final hostNickname = lobby.hostId == null
      ? ''
      : lobby.nicknameOf(lobby.hostId!);
  return utf8.encode(
    jsonEncode({
      'app': kDiscoveryAppId,
      'v': kProtocolVersion,
      'id': serverId,
      'port': port,
      'room': lobby.roomName,
      'host': hostNickname,
      'game': lobby.gameId,
      'gameName': gameName,
      'players': lobby.players.length,
      'max': lobby.maxPlayers,
      'phase': lobby.phase.name,
    }),
  );
}

/// Parses an announcement, returning null for anything that isn't one of
/// ours or comes from a different protocol version.
DiscoveredRoom? parseAnnouncement(
  List<int> data,
  InternetAddress from, {
  DateTime? now,
}) {
  try {
    final json = jsonDecode(utf8.decode(data));
    if (json is! Map<String, Object?>) return null;
    if (json['app'] != kDiscoveryAppId || json['v'] != kProtocolVersion) {
      return null;
    }
    return DiscoveredRoom(
      serverId: json['id']! as String,
      address: from,
      port: json['port']! as int,
      roomName: json['room']! as String,
      hostNickname: json['host']! as String,
      gameId: json['game']! as String,
      gameName: json['gameName']! as String,
      players: json['players']! as int,
      maxPlayers: json['max']! as int,
      phase: RoomPhase.values.byName(json['phase']! as String),
      lastSeen: now ?? DateTime.now(),
    );
  } on Object {
    return null;
  }
}

/// Addresses a host should send announcements to: the limited broadcast
/// address, each IPv4 interface's /24 broadcast address (dart:io doesn't
/// expose netmasks, and /24 covers nearly every home network), and loopback
/// so a second instance on the same machine finds the room too.
Future<List<InternetAddress>> broadcastTargets() async {
  final targets = <String>{'255.255.255.255', '127.0.0.1'};
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        final parts = addr.address.split('.');
        if (parts.length == 4 && !addr.isLoopback) {
          targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    }
  } on SocketException {
    // No interface list: limited broadcast and loopback still work.
  }
  return [for (final t in targets) InternetAddress(t)];
}

/// The device's own LAN IPv4 addresses, shown to players for manual joining.
Future<List<String>> localIPv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return [
      for (final interface in interfaces)
        for (final addr in interface.addresses)
          if (!addr.isLoopback) addr.address,
    ];
  } on SocketException {
    return [];
  }
}

/// Periodically announces a hosted room on the LAN.
class RoomBroadcaster {
  RoomBroadcaster({
    required this.announcement,
    this.port = kDiscoveryPort,
    this.interval = const Duration(seconds: 1),
    this.targets,
  });

  /// Called every tick so the announcement reflects the current lobby.
  final List<int> Function() announcement;
  final int port;
  final Duration interval;

  /// Fixed targets (tests); otherwise [broadcastTargets] is refreshed
  /// periodically to follow network changes.
  final List<InternetAddress>? targets;

  RawDatagramSocket? _socket;
  Timer? _timer;
  List<InternetAddress> _targets = [];
  int _tick = 0;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
      ..broadcastEnabled = true;
    _targets = targets ?? await broadcastTargets();
    await _send();
    _timer = Timer.periodic(interval, (_) => unawaited(_send()));
  }

  Future<void> _send() async {
    final socket = _socket;
    if (socket == null) return;
    if (targets == null && ++_tick % 10 == 0) {
      _targets = await broadcastTargets();
    }
    final data = announcement();
    for (final target in _targets) {
      try {
        socket.send(data, target, port);
      } on SocketException {
        // Unreachable network for this target; try the others.
      }
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// Listens for room announcements and keeps a list of rooms heard recently.
class RoomScanner extends ChangeNotifier {
  RoomScanner({
    this.port = kDiscoveryPort,
    this.staleAfter = const Duration(milliseconds: 3500),
  });

  final int port;
  final Duration staleAfter;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _pruneTimer;
  final Map<String, DiscoveredRoom> _rooms = {};

  /// Set when the discovery port couldn't be opened (e.g. already in use).
  String? error;

  List<DiscoveredRoom> get rooms => _rooms.values.toList()
    ..sort(
      (a, b) => a.roomName.toLowerCase().compareTo(b.roomName.toLowerCase()),
    );

  bool get isScanning => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      error = null;
    } on SocketException catch (e) {
      error = 'Scanning unavailable: ${e.message}';
      notifyListeners();
      return;
    }
    _subscription = _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket?.receive();
      if (datagram == null) return;
      final room = parseAnnouncement(datagram.data, datagram.address);
      if (room != null) _upsert(room);
    });
    _pruneTimer = Timer.periodic(const Duration(seconds: 1), (_) => _prune());
    notifyListeners();
  }

  void _upsert(DiscoveredRoom room) {
    final existing = _rooms[room.serverId];
    // The same host may be heard via loopback and via its LAN address;
    // keep the LAN address since it also works from this machine.
    final keepExistingAddress =
        existing != null &&
        room.address.isLoopback &&
        !existing.address.isLoopback;
    _rooms[room.serverId] = keepExistingAddress
        ? room.copyWith(address: existing.address)
        : room;
    notifyListeners();
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(staleAfter);
    final before = _rooms.length;
    _rooms.removeWhere((_, room) => room.lastSeen.isBefore(cutoff));
    if (_rooms.length != before) notifyListeners();
  }

  void stop() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _socket?.close();
    _socket = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
