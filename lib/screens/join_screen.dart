import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nico_native/discovery.dart';
import 'package:nico_shared/app/prefs.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/session_screen.dart';
import 'package:nico_shared/widgets/nickname_dialog.dart';

import '../net/multicast_lock.dart';

/// Parses "host" or "host:port" typed by the user. Returns null if invalid.
(String, int)? parseManualAddress(String input, {int defaultPort = kGamePort}) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final colon = text.lastIndexOf(':');
  if (colon == -1) return (text, defaultPort);
  final host = text.substring(0, colon).trim();
  final port = int.tryParse(text.substring(colon + 1).trim());
  if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
  return (host, port);
}

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _scanner = RoomScanner();
  final _manual = TextEditingController();
  String? _manualError;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    unawaited(_startScanning());
  }

  Future<void> _startScanning() async {
    await MulticastLock.acquire();
    await _scanner.start();
  }

  @override
  void dispose() {
    _scanner.dispose();
    unawaited(MulticastLock.release());
    _manual.dispose();
    super.dispose();
  }

  void _joinManual() {
    final parsed = parseManualAddress(_manual.text);
    if (parsed == null) {
      setState(() => _manualError = 'Enter an IP address, e.g. 192.168.1.20');
      return;
    }
    setState(() => _manualError = null);
    unawaited(_join(parsed.$1, parsed.$2));
  }

  /// Asks for a nickname and connects, asking again if the name is refused.
  Future<void> _join(String host, int port) async {
    if (_joining) return;
    var nickname = await Prefs.nickname();
    String? nameError;
    while (true) {
      if (!mounted) return;
      final chosen = await showNicknameDialog(
        context,
        initial: nickname,
        errorText: nameError,
      );
      if (chosen == null || !mounted) return;
      nickname = chosen;

      setState(() => _joining = true);
      try {
        final client = await GameClient.connect(
          host: host,
          port: port,
          nickname: nickname,
        );
        await Prefs.saveNickname(nickname);
        if (!mounted) {
          await client.leave();
          return;
        }
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SessionScreen(client: client),
          ),
        );
        return;
      } on JoinException catch (e) {
        if (!mounted) return;
        setState(() => _joining = false);
        if (e.code == ErrorCode.nameTaken || e.code == ErrorCode.invalidName) {
          nameError = e.message;
          continue;
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Join a game')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Text('Rooms nearby', style: theme.textTheme.titleMedium),
                  const SizedBox(width: 12),
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: _scanner,
                builder: (context, _) {
                  if (_scanner.error != null) {
                    return _InfoCard(text: _scanner.error!);
                  }
                  final rooms = _scanner.rooms;
                  if (rooms.isEmpty) {
                    return const _InfoCard(
                      text:
                          'Looking for rooms on your network…\n'
                          'Make sure you are on the same Wi-Fi as the host.',
                    );
                  }
                  return Column(
                    children: [
                      for (final room in rooms)
                        _RoomTile(
                          room: room,
                          onTap: room.isJoinable
                              ? () => _join(room.address.address, room.port)
                              : null,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
              Text('Join by IP address', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                "Can't see the room? Enter the address shown in the host's "
                'lobby.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manual,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        hintText: '192.168.1.20 or 192.168.1.20:$kGamePort',
                        errorText: _manualError,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _joinManual(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _joining ? null : _joinManual,
                      child: const Text('Join'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_joining)
            const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.onTap});

  final DiscoveredRoom room;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String status;
    if (room.phase != RoomPhase.lobby) {
      status = 'In game';
    } else if (room.players >= room.maxPlayers) {
      status = 'Full';
    } else {
      status = '${room.players}/${room.maxPlayers}';
    }
    return Card(
      child: ListTile(
        enabled: onTap != null,
        leading: const Icon(Icons.videogame_asset),
        title: Text(room.roomName),
        subtitle: Text(
          '${room.gameName} · hosted by ${room.hostNickname}\n'
          '${room.address.address}:${room.port}',
        ),
        isThreeLine: true,
        trailing: Text(status),
        onTap: onTap,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
