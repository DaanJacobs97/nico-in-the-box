import 'package:flutter/material.dart';

import '../games/registry.dart';
import '../net/game_client.dart';
import '../net/protocol.dart';
import '../widgets/display_settings_editor.dart';
import '../widgets/game_options_editor.dart';
import '../widgets/host_controls.dart';

/// Waiting room: who's here, which game, and (for the host) how to start.
class LobbyView extends StatelessWidget {
  const LobbyView({
    super.key,
    required this.client,
    this.hostFooter,
    this.hostScreenControls,
    this.casterAvailable = false,
  });

  final GameClient client;

  /// Extra content below the host's Start button, e.g. how to join.
  final Widget? hostFooter;

  /// Extra shared-screen controls for the host, shown under the settings
  /// (e.g. picking a Caster). Native-only, so the host app supplies them.
  final Widget? Function(LobbyState lobby)? hostScreenControls;

  /// Whether the host can pick the Caster app as the shared screen.
  final bool casterAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lobby = client.lobby!;
    final game = gameById(lobby.gameId);
    final isHost = client.isHost;

    final list = ListView(
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
        if (game != null && game.options.isNotEmpty)
          Card(
            child: GameOptionsEditor(
              game: game,
              values: lobby.gameOptions,
              onChanged: isHost ? client.setGameOptions : null,
            ),
          ),
        if (isHost)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DisplaySettingsEditor(
                    value: lobby.display,
                    onChanged: client.setDisplay,
                    casterAvailable: casterAvailable,
                  ),
                  if (lobby.display.enabled) ...[
                    const SizedBox(height: 8),
                    _ScreensConnected(displays: lobby.displays),
                    if (hostScreenControls?.call(lobby)
                        case final controls?) ...[
                      const SizedBox(height: 12),
                      controls,
                    ],
                  ],
                ],
              ),
            ),
          )
        else if (lobby.display.enabled)
          Card(
            child: ListTile(
              leading: const Icon(Icons.tv),
              title: const Text('Single game screen is on'),
              subtitle: Text(
                lobby.sharedScreenActive
                    ? 'Watch the shared screen; your device shows just your '
                          'hand and buttons.'
                    : 'No screen is connected yet, so you will see the whole '
                          'table here.',
              ),
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
                player.away
                    ? Icons.wifi_off
                    : player.id == lobby.hostId
                    ? Icons.emoji_events
                    : player.isWeb
                    ? Icons.language
                    : Icons.person,
                color: player.id == lobby.hostId ? Colors.amber : null,
              ),
              title: Text(
                player.id == client.playerId
                    ? '${player.nickname} (you)'
                    : player.nickname,
              ),
              subtitle: player.away
                  ? const Text('Reconnecting…')
                  : player.id == lobby.hostId
                  ? const Text('Host')
                  : player.isWeb
                  ? const Text('In a browser')
                  : null,
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
        if (isHost)
          ?hostFooter
        else
          Text(
            'Waiting for the host to start the game…',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
      ],
    );
    if (!isHost) return list;
    // The host's Start button stays visible however long the lobby gets.
    return Column(
      children: [
        Expanded(child: list),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  lobby.canStart
                      ? 'Start game'
                      : 'Need ${lobby.minPlayers - lobby.players.length} more '
                            'player(s)',
                ),
                onPressed: lobby.canStart ? client.startGame : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which shared screens are connected, for the host.
class _ScreensConnected extends StatelessWidget {
  const _ScreensConnected({required this.displays});

  final List<DisplayInfo> displays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (displays.isEmpty) {
      return Text(
        'No screen connected yet. Until one is, players see the whole table.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final d in displays)
          Chip(
            avatar: Icon(switch (d.kind) {
              DisplayKind.host => Icons.tv,
              DisplayKind.browser => Icons.language,
              DisplayKind.caster => Icons.cast,
            }, size: 18),
            label: Text(d.kind == DisplayKind.host ? 'This device' : d.name),
          ),
      ],
    );
  }
}
