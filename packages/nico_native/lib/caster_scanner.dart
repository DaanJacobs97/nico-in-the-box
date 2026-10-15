import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nico_shared/net/protocol.dart';

/// A Caster heard on the network.
class DiscoveredCaster {
  const DiscoveredCaster({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.busy,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final InternetAddress address;
  final int port;

  /// Already showing another host's room.
  final bool busy;
  final DateTime lastSeen;

  DiscoveredCaster withAddress(InternetAddress address) => DiscoveredCaster(
    id: id,
    name: name,
    address: address,
    port: port,
    busy: busy,
    lastSeen: lastSeen,
  );
}

/// Parses a Caster announcement packet; null for anything else.
DiscoveredCaster? parseCasterAnnouncement(
  List<int> data,
  InternetAddress from, {
  DateTime? now,
}) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(data));
  } on Object {
    return null;
  }
  final announcement = CasterAnnouncement.tryParse(json);
  if (announcement == null) return null;
  return DiscoveredCaster(
    id: announcement.id,
    name: announcement.name,
    address: from,
    port: announcement.port,
    busy: announcement.busy,
    lastSeen: now ?? DateTime.now(),
  );
}

/// Listens for Caster announcements and keeps the ones heard recently, so
/// the host can pick a screen.
class CasterScanner extends ChangeNotifier {
  CasterScanner({
    this.port = kCasterDiscoveryPort,
    this.staleAfter = const Duration(milliseconds: 3500),
  });

  final int port;
  final Duration staleAfter;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _pruneTimer;
  final Map<String, DiscoveredCaster> _casters = {};

  /// Set when the port couldn't be opened.
  String? error;

  List<DiscoveredCaster> get casters =>
      _casters.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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
      error = 'Looking for Casters failed: ${e.message}';
      notifyListeners();
      return;
    }
    _subscription = _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket?.receive();
      if (datagram == null) return;
      final caster = parseCasterAnnouncement(datagram.data, datagram.address);
      if (caster != null) _upsert(caster);
    });
    _pruneTimer = Timer.periodic(const Duration(seconds: 1), (_) => _prune());
    notifyListeners();
  }

  void _upsert(DiscoveredCaster caster) {
    final existing = _casters[caster.id];
    // Heard via loopback and the LAN: keep the LAN address, it works from
    // this machine too.
    final keepAddress =
        existing != null &&
        caster.address.isLoopback &&
        !existing.address.isLoopback;
    _casters[caster.id] = keepAddress
        ? caster.withAddress(existing.address)
        : caster;
    notifyListeners();
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(staleAfter);
    final before = _casters.length;
    _casters.removeWhere((_, c) => c.lastSeen.isBefore(cutoff));
    if (_casters.length != before) notifyListeners();
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
