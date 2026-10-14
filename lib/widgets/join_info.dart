import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../net/hosted_room.dart';

/// Shows the host's addresses so players can join manually.
class JoinInfo extends StatelessWidget {
  const JoinInfo({super.key, required this.room});

  final HostedRoom room;

  String _playUrl(String address) => 'http://$address:${room.port}/play';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addresses = room.addresses;
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How to join', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text(
              'Players on the same network should see this room under '
              '"Join a game". If not, they can enter one of these addresses:',
            ),
            const SizedBox(height: 8),
            if (addresses.isEmpty)
              const Text('No network address found — are you connected?')
            else
              for (final address in addresses)
                SelectableText(
                  room.port == kGamePort ? address : '$address:${room.port}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
            if (room.hasWebClient && addresses.isNotEmpty) ...[
              const Divider(height: 32),
              Text(
                'No app? Join in a browser',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'Scan the code with a phone camera, or open the address in '
                'any browser on the same network:',
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  // QR codes need a light background and a quiet zone to scan.
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: _playUrl(addresses.first),
                    size: 180,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final address in addresses)
                SelectableText(
                  _playUrl(address),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
            ],
            if (Platform.isWindows) ...[
              const SizedBox(height: 12),
              Text(
                'Nobody can connect? Windows Firewall may be blocking the '
                'game. Allow "Nico in the Box" on Private networks (Windows '
                'Security → Firewall & network protection → Allow an app '
                'through firewall), and make sure your Wi-Fi is set to a '
                'Private network.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
