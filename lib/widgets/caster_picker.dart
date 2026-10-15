import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nico_native/caster_scanner.dart';
import 'package:nico_shared/net/protocol.dart';

import '../net/caster_link.dart';
import '../net/hosted_room.dart';
import '../net/multicast_lock.dart';
import '../screens/join_screen.dart';

/// The host's "Choose screen" panel when the shared screen is a Caster:
/// Casters found on the network, a manual address, and the connected one.
class CasterPicker extends StatefulWidget {
  const CasterPicker({super.key, required this.room, required this.lobby});

  final HostedRoom room;
  final LobbyState lobby;

  @override
  State<CasterPicker> createState() => _CasterPickerState();
}

class _CasterPickerState extends State<CasterPicker> {
  final _scanner = CasterScanner();
  final _manual = TextEditingController();
  String? _connectingTo;
  String? _manualError;

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

  Future<void> _connect(String host, int port, String label) async {
    setState(() => _connectingTo = label);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.room.connectCaster(host, port);
    } on CasterException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _connectingTo = null);
    }
  }

  void _connectManual() {
    final parsed = parseManualAddress(_manual.text, defaultPort: kCasterPort);
    if (parsed == null) {
      setState(() => _manualError = 'Enter the address shown on the Caster.');
      return;
    }
    setState(() => _manualError = null);
    unawaited(_connect(parsed.$1, parsed.$2, parsed.$1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = widget.lobby.displays
        .where((d) => d.kind == DisplayKind.caster)
        .firstOrNull;

    if (connected != null) {
      return Card(
        color: theme.colorScheme.secondaryContainer,
        child: ListTile(
          leading: const Icon(Icons.cast_connected),
          title: Text('Showing on ${connected.name}'),
          subtitle: const Text('The table is on the Caster.'),
          trailing: TextButton(
            onPressed: widget.room.disconnectCaster,
            child: const Text('Disconnect'),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Choose screen', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        ListenableBuilder(
          listenable: _scanner,
          builder: (context, _) {
            if (_scanner.error != null) {
              return Text(_scanner.error!);
            }
            final casters = _scanner.casters;
            if (casters.isEmpty) {
              return const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('Looking for Casters…'),
                subtitle: Text(
                  'Start Nico Caster on the TV or computer, on the same '
                  'network.',
                ),
              );
            }
            return Column(
              children: [
                for (final caster in casters)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cast),
                    title: Text(caster.name),
                    subtitle: Text(
                      '${caster.address.address}'
                      '${caster.busy ? ' · In use' : ''}',
                    ),
                    trailing: _connectingTo == caster.id
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : FilledButton.tonal(
                            onPressed: caster.busy || _connectingTo != null
                                ? null
                                : () => _connect(
                                    caster.address.address,
                                    caster.port,
                                    caster.id,
                                  ),
                            child: const Text('Connect'),
                          ),
                  ),
              ],
            );
          },
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
                  isDense: true,
                  labelText: 'Or enter the Caster\'s address',
                  hintText: '192.168.1.30',
                  errorText: _manualError,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _connectManual(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _connectingTo == null ? _connectManual : null,
              child: const Text('Connect'),
            ),
          ],
        ),
      ],
    );
  }
}
