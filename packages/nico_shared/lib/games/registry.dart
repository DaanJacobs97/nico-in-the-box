import 'color_clash/color_clash_game.dart';
import 'game_session.dart';
import 'seasiege/seasiege_game.dart';
import 'tacticalvoxelrpg/tacticalvoxelrpg_game.dart';
import 'tictactoe/tictactoe_game.dart';

/// Every game the host can pick, in display order.
const List<GameDefinition> availableGames = [
  ticTacToeDefinition,
  colorClashDefinition,
  seaSiegeDefinition,
  tacticalVoxelRPGDefinition,
];

GameDefinition? gameById(String id) {
  for (final game in availableGames) {
    if (game.id == id) return game;
  }
  return null;
}
