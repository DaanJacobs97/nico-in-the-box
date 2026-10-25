import 'package:flutter/material.dart';

import '../net/protocol.dart';
import 'color_clash/color_clash_table.dart';
import 'color_clash/color_clash_view.dart';
import 'seasiege/seasiege_table.dart';
import 'seasiege/seasiege_view.dart';
import 'tacticalvoxelrpg/tacticalvoxelrpg_view.dart';
import 'tictactoe/tictactoe_view.dart';

/// What a game's widget needs to render the current view and send moves.
class GameViewContext {
  const GameViewContext({
    required this.view,
    required this.myId,
    required this.lobby,
    required this.sendAction,
    this.compact = false,
    this.performanceLog,
  });

  /// This player's view, produced by the game's `GameSession.viewFor`.
  final Json view;
  final String myId;
  final LobbyState lobby;
  final void Function(Json action) sendAction;

  /// A shared screen is showing the table, so show only this player's
  /// hand and inputs (plus a one-line status).
  final bool compact;

  /// Optional native diagnostics sink; keeps this package usable on web.
  final void Function(Map<String, Object?> event)? performanceLog;

  String nicknameOf(String playerId) =>
      playerId == myId ? 'You' : lobby.nicknameOf(playerId);
}

typedef GameViewBuilder = Widget Function(GameViewContext context);

/// UI for each game id in the registry. Kept apart from the engines so they
/// stay pure Dart.
final Map<String, GameViewBuilder> gameViews = {
  'tictactoe': (ctx) => TicTacToeView(ctx: ctx),
  'colorclash': (ctx) => ColorClashView(ctx: ctx),
  'seasiege': (ctx) => SeaSiegeView(ctx: ctx),
  'tacticalvoxelrpg': (ctx) => TacticalVoxelRPGView(ctx: ctx),
};

/// What a shared screen needs to draw a game's table.
class TableContext {
  const TableContext({required this.table, required this.lobby});

  /// The game's `GameSession.tableView()`: public state only.
  final Json table;
  final LobbyState lobby;

  String nicknameOf(String playerId) => lobby.nicknameOf(playerId);
}

typedef GameTableBuilder = Widget Function(TableContext context);

/// Shared-screen table for each game id: big, read-only, no hands.
final Map<String, GameTableBuilder> gameTables = {
  'tictactoe': (ctx) => TicTacToeTable(ctx: ctx),
  'colorclash': (ctx) => ColorClashTable(ctx: ctx),
  'seasiege': (ctx) => SeaSiegeTable(ctx: ctx),
  'tacticalvoxelrpg': (ctx) => TacticalVoxelRPGTable(ctx: ctx),
};
