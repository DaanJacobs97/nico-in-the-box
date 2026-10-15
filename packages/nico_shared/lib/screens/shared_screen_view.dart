import 'package:flutter/material.dart';

import '../games/game_views.dart';
import '../games/registry.dart';
import '../net/protocol.dart';

/// What a shared screen shows, drawn from the display feed: the lobby while
/// players gather, then the game's table, then the result. Read-only.
///
/// Used by the host's device when it *is* the screen, and by the Caster app.
class SharedScreenView extends StatelessWidget {
  const SharedScreenView({super.key, required this.state, this.lobbyFooter});

  /// Null until the first display update arrives.
  final DisplayState? state;

  /// Extra lobby content, e.g. how to join.
  final Widget? lobbyFooter;

  @override
  Widget build(BuildContext context) {
    final state = this.state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final table = state.table;
    final builder = gameTables[state.gameId];
    if (state.lobby.phase == RoomPhase.lobby ||
        table == null ||
        builder == null) {
      return _ScreenLobby(
        lobby: state.lobby,
        rules: state.rules,
        footer: lobbyFooter,
      );
    }
    return Column(
      children: [
        Expanded(
          child: builder(TableContext(table: table, lobby: state.lobby)),
        ),
        if (state.result != null) _ScreenResult(result: state.result!),
      ],
    );
  }
}

class _ScreenLobby extends StatelessWidget {
  const _ScreenLobby({required this.lobby, this.rules = const [], this.footer});

  final LobbyState lobby;

  /// The active game options as text.
  final List<String> rules;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = gameById(lobby.gameId);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                lobby.roomName,
                textAlign: TextAlign.center,
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                game == null
                    ? lobby.gameId
                    : '${game.name} · ${game.playerRange}',
                style: theme.textTheme.headlineSmall,
              ),
              if (rules.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  rules.join('  ·  '),
                  key: const ValueKey('screen-rules'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ],
              const SizedBox(height: 32),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  for (final player in lobby.players)
                    Chip(
                      avatar: Icon(
                        player.id == lobby.hostId
                            ? Icons.emoji_events
                            : player.isWeb
                            ? Icons.language
                            : Icons.person,
                        color: player.id == lobby.hostId ? Colors.amber : null,
                      ),
                      label: Text(
                        player.nickname,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  for (var i = lobby.players.length; i < lobby.maxPlayers; i++)
                    Chip(
                      avatar: const Icon(Icons.hourglass_empty),
                      label: Text(
                        'Free seat',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'Join on your phone: open Nico in the Box, tap Join a game, '
                'and pick "${lobby.roomName}".',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (footer != null) ...[const SizedBox(height: 24), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenResult extends StatelessWidget {
  const _ScreenResult({required this.result});

  final Json result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🎉 ${result['summary'] as String? ?? ''}',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text('Waiting for the host…', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
