import 'package:flutter/material.dart';

import '../net/game_client.dart';
import '../net/protocol.dart';
import 'confirm_dialog.dart';

enum _HostAction { restart, endGame, kick, closeRoom }

/// App-bar menu with the host's session controls. Only built for the host;
/// the server also rejects these commands from anyone else.
class HostControlsMenu extends StatelessWidget {
  const HostControlsMenu({
    super.key,
    required this.client,
    required this.onCloseRoom,
  });

  final GameClient client;

  /// Called after the host confirms closing the room.
  final VoidCallback onCloseRoom;

  @override
  Widget build(BuildContext context) {
    final lobby = client.lobby;
    final inGame = lobby != null && lobby.phase != RoomPhase.lobby;
    final hasOthers = lobby != null && lobby.players.length > 1;

    return PopupMenuButton<_HostAction>(
      tooltip: 'Host controls',
      icon: const Icon(Icons.admin_panel_settings),
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _HostAction.restart,
          enabled: inGame,
          child: const ListTile(
            leading: Icon(Icons.restart_alt),
            title: Text('Restart game'),
          ),
        ),
        PopupMenuItem(
          value: _HostAction.endGame,
          enabled: inGame,
          child: const ListTile(
            leading: Icon(Icons.stop_circle_outlined),
            title: Text('End game (back to lobby)'),
          ),
        ),
        PopupMenuItem(
          value: _HostAction.kick,
          enabled: hasOthers,
          child: const ListTile(
            leading: Icon(Icons.person_remove),
            title: Text('Kick player…'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _HostAction.closeRoom,
          child: ListTile(
            leading: Icon(Icons.close),
            title: Text('Close room'),
          ),
        ),
      ],
    );
  }

  Future<void> _onSelected(BuildContext context, _HostAction action) async {
    switch (action) {
      case _HostAction.restart:
        if (await confirm(
          context,
          title: 'Restart game?',
          message: 'The current game will be thrown away and a new one dealt.',
          confirmLabel: 'Restart',
        )) {
          client.restartGame();
        }
      case _HostAction.endGame:
        if (await confirm(
          context,
          title: 'End game?',
          message: 'Everyone goes back to the lobby.',
          confirmLabel: 'End game',
        )) {
          client.endGame();
        }
      case _HostAction.kick:
        if (!context.mounted) return;
        await showKickDialog(context, client);
      case _HostAction.closeRoom:
        if (await confirm(
          context,
          title: 'Close room?',
          message: 'All players will be disconnected.',
          confirmLabel: 'Close room',
        )) {
          onCloseRoom();
        }
    }
  }
}

/// Lets the host pick a player to kick, then confirms.
Future<void> showKickDialog(BuildContext context, GameClient client) async {
  final others =
      client.lobby?.players.where((p) => p.id != client.playerId).toList() ??
      [];
  final target = await showDialog<PlayerInfo>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Kick which player?'),
      children: [
        for (final player in others)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(player),
            child: Text(player.nickname),
          ),
      ],
    ),
  );
  if (target == null || !context.mounted) return;
  await confirmKick(context, client, target);
}

Future<void> confirmKick(
  BuildContext context,
  GameClient client,
  PlayerInfo target,
) async {
  final inGame = client.lobby?.phase != RoomPhase.lobby;
  if (await confirm(
    context,
    title: 'Kick ${target.nickname}?',
    message: inGame
        ? 'The current game will end and everyone returns to the lobby.'
        : 'They will be removed from the room.',
    confirmLabel: 'Kick',
  )) {
    client.kick(target.id);
  }
}
