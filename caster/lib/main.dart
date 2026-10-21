import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nico_native/discovery.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/shared_screen_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'cast_server.dart';
import 'idle_screen.dart';

const _nameKey = 'casterName';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CasterApp());
}

/// A shared screen for Nico in the Box rooms. It announces itself on the
/// LAN, waits for a host to pick it, then shows that room's table.
class CasterApp extends StatefulWidget {
  const CasterApp({super.key});

  @override
  State<CasterApp> createState() => _CasterAppState();
}

class _CasterAppState extends State<CasterApp> {
  final _id = List.generate(
    8,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  late final CastServer _server = CastServer(name: () => _name);
  RoomBroadcaster? _announcer;
  late String _name = defaultCasterName(_id);
  List<String> _addresses = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    // A screen across the room never goes to sleep. It may turn: a tablet
    // propped up in portrait gets layouts made for tall screens.
    unawaited(WakelockPlus.enable().catchError((Object _) {}));

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_nameKey);
      if (saved != null && saved.trim().isNotEmpty) {
        _name = saved;
      } else {
        // Keep the generated default ("Caster 3fa1") from now on, so hosts
        // see the same screen name every time the app starts.
        await prefs.setString(_nameKey, _name);
      }
    } on Object {
      // Keep the default name for this session.
    }

    try {
      await _server.start();
    } on SocketException catch (e) {
      setState(() => _error = 'Could not start the Caster: ${e.message}');
      return;
    }
    _announcer = RoomBroadcaster(
      port: kCasterDiscoveryPort,
      announcement: () => utf8.encode(
        jsonEncode(
          CasterAnnouncement(
            id: _id,
            name: _name,
            port: _server.port,
            busy: _server.isBusy,
          ).toJson(),
        ),
      ),
    );
    try {
      await _announcer!.start();
    } on Object {
      // Hosts can still connect by typing this device's address.
    }
    final addresses = await localIPv4Addresses();
    if (mounted) setState(() => _addresses = addresses);
  }

  Future<void> _rename(String name) async {
    setState(() => _name = name);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, name);
    } on Object {
      // Not remembered, but used for this session.
    }
  }

  @override
  void dispose() {
    _announcer?.stop();
    unawaited(_server.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nico in the Box Caster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: ListenableBuilder(
        listenable: _server,
        builder: (context, _) => Scaffold(
          body: _server.isBusy
              ? SafeArea(child: SharedScreenView(state: _server.display))
              : IdleScreen(
                  name: _name,
                  addresses: _addresses,
                  port: _addresses.isEmpty ? null : _server.port,
                  error: _error,
                  onRename: _rename,
                ),
        ),
      ),
    );
  }
}

/// The device's network name, shortened to fit in a host's list. Android
/// reports "localhost", so then a short code from [id] tells screens apart.
String defaultCasterName(String id, {String? hostname}) {
  var host = hostname;
  if (host == null) {
    try {
      host = Platform.localHostname;
    } on Object {
      host = '';
    }
  }
  host = host.split('.').first.trim();
  if (host.isEmpty || host.toLowerCase() == 'localhost') {
    return 'Caster ${id.substring(0, 4)}';
  }
  return host.length > 24 ? host.substring(0, 24) : host;
}
