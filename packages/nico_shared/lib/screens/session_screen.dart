import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../games/game_views.dart';
import '../games/registry.dart';
import '../net/game_client.dart';
import '../net/protocol.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/host_controls.dart';
import 'lobby_view.dart';
import 'shared_screen_view.dart';

/// The room a player is in: the lobby, then the game. The host gets the
/// session controls on top of the same view everyone else sees.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.client,
    this.onClose,
    this.hostFooter,
    this.hostScreenControls,
    this.casterAvailable = false,
  });

  final GameClient client;

  /// Set on the host's device: shuts the room down (server included) when
  /// the host leaves. Without it, leaving just disconnects this client.
  final Future<void> Function()? onClose;

  /// Extra lobby content for the host, e.g. how to join.
  final Widget? hostFooter;

  /// See [LobbyView.hostScreenControls].
  final Widget? Function(LobbyState lobby)? hostScreenControls;

  /// See [LobbyView.casterAvailable].
  final bool casterAvailable;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final StreamSubscription<String> _notices;
  bool _exiting = false;
  bool _immersiveTactical = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSystemUi());
  }

  @override
  void dispose() {
    _client.removeListener(_onClientChanged);
    unawaited(_notices.cancel());
    if (_immersiveTactical) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  void _onClientChanged() {
    _syncSystemUi();
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

  void _syncSystemUi() {
    final lobby = _client.lobby;
    final immersive =
        lobby?.gameId == 'tacticalvoxelrpg' &&
        lobby?.phase == RoomPhase.playing;
    if (_immersiveTactical == immersive) return;
    _immersiveTactical = immersive;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
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
          final tacticalBattle =
              lobby?.gameId == 'tacticalvoxelrpg' &&
              lobby?.phase == RoomPhase.playing;
          return Scaffold(
            extendBodyBehindAppBar: tacticalBattle,
            appBar: AppBar(
              backgroundColor: tacticalBattle ? Colors.transparent : null,
              elevation: tacticalBattle ? 0 : null,
              surfaceTintColor: tacticalBattle ? Colors.transparent : null,
              automaticallyImplyLeading: !tacticalBattle,
              title: tacticalBattle
                  ? const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ASHEN OATH',
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 18,
                            letterSpacing: 5,
                          ),
                        ),
                        Text(
                          'THE HOLLOW CAMPAIGN',
                          style: TextStyle(
                            fontSize: 8,
                            letterSpacing: 3,
                            color: Color(0xff929789),
                          ),
                        ),
                      ],
                    )
                  : Text(lobby?.roomName ?? 'Connecting…'),
              actions: [
                if (tacticalBattle) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Center(
                      child: Text(
                        'TACTICAL PROTOTYPE',
                        style: TextStyle(
                          fontSize: 8,
                          letterSpacing: 2,
                          color: Color(0xff959b8e),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Game rules',
                    onPressed: () => _showTacticalRules(context),
                    icon: const Icon(Icons.help_outline, size: 20),
                  ),
                ],
                if (_client.isHost && lobby != null)
                  HostControlsMenu(client: _client, onCloseRoom: _exit),
              ],
            ),
            body: _ReconnectingGuard(
              reconnecting: _client.reconnecting,
              onLeave: () => unawaited(_exit()),
              child: lobby == null
                  ? const Center(child: CircularProgressIndicator())
                  : lobby.phase == RoomPhase.lobby
                  ? LobbyView(
                      client: _client,
                      hostFooter: widget.hostFooter,
                      hostScreenControls: widget.hostScreenControls,
                      casterAvailable: widget.casterAvailable,
                    )
                  : _client.isHost && lobby.display.hostIsScreen
                  ? _HostScreenArea(client: _client)
                  : _GameArea(client: _client),
            ),
          );
        },
      ),
    );
  }

  void _showTacticalRules(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff19221c),
        title: const Text('Every oath has a cost.'),
        content: const Text(
          'Activate a unit to play its own five-card hand. Each unit gets '
          '2 action points per round. Drag a unit card into the battlefield '
          'to activate it, then drag an action card into the map to choose '
          'its target. Each unit acts once before the enemy phase. You can '
          'retain one card for each unit between rounds.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
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
              compact: lobby.sharedScreenActive,
            ),
          ),
        ),
        if (result != null) _ResultBar(client: client, result: result),
      ],
    );
  }
}

/// The host's device is the shared screen: it shows the table for everyone,
/// and only the host's finished-game buttons on top.
class _HostScreenArea extends StatelessWidget {
  const _HostScreenArea({required this.client});

  final GameClient client;

  @override
  Widget build(BuildContext context) {
    final state = client.displayState;
    final result = state?.result;
    return Column(
      children: [
        Expanded(child: SharedScreenView(state: state)),
        if (result != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.replay),
                  label: const Text('Play again'),
                  onPressed: client.restartGame,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.people),
                  label: const Text('Back to lobby'),
                  onPressed: client.endGame,
                ),
              ],
            ),
          ),
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

/// While the connection is being restored: a banner on top, and the room
/// greyed out and not tappable, so no move seems to go through.
class _ReconnectingGuard extends StatelessWidget {
  const _ReconnectingGuard({
    required this.reconnecting,
    required this.onLeave,
    required this.child,
  });

  final bool reconnecting;
  final VoidCallback onLeave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (reconnecting)
          MaterialBanner(
            leading: const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            content: const Text('Connection lost. Reconnecting…'),
            actions: [
              TextButton(onPressed: onLeave, child: const Text('Leave')),
            ],
          ),
        Expanded(
          child: IgnorePointer(
            ignoring: reconnecting,
            child: Opacity(opacity: reconnecting ? 0.4 : 1, child: child),
          ),
        ),
      ],
    );
  }
}
