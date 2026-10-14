import 'package:flutter/material.dart';

import '../net/protocol.dart';
import 'color_clash/color_clash_view.dart';
import 'tictactoe/tictactoe_view.dart';

/// What a game's widget needs to render the current view and send moves.
class GameViewContext {
  const GameViewContext({
    required this.view,
    required this.myId,
    required this.lobby,
    required this.sendAction,
  });

  /// This player's view, produced by the game's `GameSession.viewFor`.
  final Json view;
  final String myId;
  final LobbyState lobby;
  final void Function(Json action) sendAction;

  String nicknameOf(String playerId) =>
      playerId == myId ? 'You' : lobby.nicknameOf(playerId);
}

typedef GameViewBuilder = Widget Function(GameViewContext context);

/// UI for each game id in the registry. Kept apart from the engines so they
/// stay pure Dart.
final Map<String, GameViewBuilder> gameViews = {
  'tictactoe': (ctx) => TicTacToeView(ctx: ctx),
  'colorclash': (ctx) => ColorClashView(ctx: ctx),
};
