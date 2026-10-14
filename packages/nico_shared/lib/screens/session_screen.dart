import 'dart:async';

import 'package:flutter/material.dart';

import '../games/game_views.dart';
import '../games/registry.dart';
import '../net/game_client.dart';
import '../net/protocol.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/host_controls.dart';
import 'lobby_view.dart';

/// The room a player is in: the lobby, then the game. The host gets the
/// session controls on top of the same view everyone else sees.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.client,
    this.onClose,
    this.hostFooter,
  });

  final GameClient client;

  /// Set on the host's device: shuts the room down (server included) when
  /// the host leaves. Without it, leaving just disconnects this client.
  final Future<void> Function()? onClose;

  /// Extra lobby content for the host, e.g. how to join.
  final Widget? hostFooter;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final StreamSubscription<String> _notices;
  bool _exiting = false;

  GameClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _notices = _client.notices.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
    _client.addListener(_onClientChanged);
  }

  @override
  void dispose() {
    _client.removeListener(_onClientChanged);
    unawaited(_notices.cancel());
    super.dispose();
  }

  void _onClientChanged() {
    final reason = _client.disconnectReason;
    if (reason == null || reason == DisconnectReason.left) return;
    final message = switch (reason) {
      DisconnectReason.kicked => 'You were kicked from the room.',
      DisconnectReason.hostClosed => 'The host closed the room.',
      DisconnectReason.hostLeft => 'The host left, so the room was closed.',
      DisconnectReason.connectionLost => 'Lost connection to the room.',
      DisconnectReason.left => '',
    };
    unawaited(_exit(message: message));
  }

  /// Leaves the room (closing it if we host) and returns to the home screen.
  Future<void> _exit({String? message}) async {
    if (_exiting) return;
    _exiting = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (widget.onClose != null) {
      await widget.onClose!();
    } else {
      await _client.leave();
    }
    _client.dispose();
    navigator.popUntil((route) => route.isFirst);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _confirmLeave() async {
    final isHost = widget.onClose != null;
    final ok = await confirm(
      context,
      title: isHost ? 'Close room?' : 'Leave room?',
      message: isHost
          ? 'You are the host. Leaving closes the room for everyone.'
          : 'You will leave the room.',
      confirmLabel: isHost ? 'Close room' : 'Leave',
    );
    if (ok) await _exit();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: ListenableBuilder(
        listenable: _client,
        builder: (context, _) {
          final lobby = _client.lobby;
          return Scaffold(
            appBar: AppBar(
              title: Text(lobby?.roomName ?? 'Connecting…'),
              actions: [
                if (_client.isHost && lobby != null)
                  HostControlsMenu(client: _client, onCloseRoom: _exit),
              ],
            ),
            body: lobby == null
                ? const Center(child: CircularProgressIndicator())
                : lobby.phase == RoomPhase.lobby
                ? LobbyView(client: _client, hostFooter: widget.hostFooter)
                : _GameArea(client: _client),
          );
        },
      ),
    );
  }
}

class _GameArea extends StatelessWidget {
  const _GameArea({required this.client});

  final GameClient client;

  @override
  Widget build(BuildContext context) {
    final lobby = client.lobby!;
    final view = client.gameView;
    final builder = gameViews[client.gameId];
    if (view == null || builder == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final result = client.gameResult;

    return Column(
      children: [
        Expanded(
          child: builder(
            GameViewContext(
              view: view,
              myId: client.playerId,
              lobby: lobby,
              sendAction: client.sendAction,
            ),
          ),
        ),
        if (result != null) _ResultBar(client: client, result: result),
      ],
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({required this.client, required this.result});

  final GameClient client;
  final Json result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winners = (result['winnerIds'] as List<Object?>? ?? [])
        .cast<String>();
    final iWon = winners.contains(client.playerId);
    final game = gameById(client.lobby!.gameId);

    return Material(
      color: iWon
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                iWon ? '🎉 You win!' : result['summary'] as String? ?? '',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (client.isHost)
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.replay),
                      label: Text('Play ${game?.name ?? 'the game'} again'),
                      onPressed: client.restartGame,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.people),
                      label: const Text('Back to lobby'),
                      onPressed: client.endGame,
                    ),
                  ],
                )
              else
                const Text('Waiting for the host…'),
            ],
          ),
        ),
      ),
    );
  }
}
