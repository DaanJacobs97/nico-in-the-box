import 'dart:io';

import 'package:flutter/material.dart';

import '../games/registry.dart';
import '../net/game_client.dart';
import '../net/hosted_room.dart';
import '../net/protocol.dart';
import '../widgets/host_controls.dart';

/// Waiting room: who's here, which game, and (for the host) how to start.
class LobbyView extends StatelessWidget {
  const LobbyView({super.key, required this.client, this.hostedRoom});

  final GameClient client;
  final HostedRoom? hostedRoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lobby = client.lobby!;
    final game = gameById(lobby.gameId);
    final isHost = client.isHost;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.videogame_asset),
            title: Text(game?.name ?? lobby.gameId),
            subtitle: Text(game?.description ?? ''),
            trailing: isHost
                ? PopupMenuButton<String>(
                    tooltip: 'Change game',
                    icon: const Icon(Icons.swap_horiz),
                    onSelected: client.changeGame,
                    itemBuilder: (_) => [
                      for (final g in availableGames)
                        PopupMenuItem(
                          value: g.id,
                          enabled:
                              g.id != lobby.gameId &&
                              lobby.players.length <= g.maxPlayers,
                          child: Text('${g.name} (${g.playerRange})'),
                        ),
                    ],
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Players ${lobby.players.length}/${lobby.maxPlayers}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final player in lobby.players)
          Card(
            child: ListTile(
              leading: Icon(
                player.id == lobby.hostId ? Icons.emoji_events : Icons.person,
                color: player.id == lobby.hostId ? Colors.amber : null,
              ),
              title: Text(
                player.id == client.playerId
                    ? '${player.nickname} (you)'
                    : player.nickname,
              ),
              subtitle: player.id == lobby.hostId ? const Text('Host') : null,
              trailing: isHost && player.id != client.playerId
                  ? IconButton(
                      tooltip: 'Kick',
                      icon: const Icon(Icons.person_remove),
                      onPressed: () => confirmKick(context, client, player),
                    )
                  : null,
            ),
          ),
        for (var i = lobby.players.length; i < lobby.maxPlayers; i++)
          const Card(
            child: ListTile(
              leading: Icon(Icons.hourglass_empty),
              title: Text('Waiting for a player…'),
            ),
          ),
        const SizedBox(height: 24),
        if (isHost) ...[
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(
              lobby.canStart
                  ? 'Start game'
                  : 'Need ${lobby.minPlayers - lobby.players.length} more '
                        'player(s)',
            ),
            onPressed: lobby.canStart ? client.startGame : null,
          ),
          if (hostedRoom != null) ...[
            const SizedBox(height: 24),
            _JoinInfo(room: hostedRoom!),
          ],
        ] else
          Text(
            'Waiting for the host to start the game…',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
      ],
    );
  }
}

/// Shows the host's addresses so players can join manually.
class _JoinInfo extends StatelessWidget {
  const _JoinInfo({required this.room});

  final HostedRoom room;

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
