import 'blackjack/blackjack_game.dart';
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
  blackjackDefinition,
];

GameDefinition? gameById(String id) {
  for (final game in availableGames) {
    if (game.id == id) return game;
  }
  return null;
}

/// [games] grouped by category in [GameCategory] order, keeping their order
/// within each. Categories no game uses are left out.
List<(GameCategory, List<GameDefinition>)> gamesByCategory([
  List<GameDefinition> games = availableGames,
]) => [
  for (final category in GameCategory.values)
    if (games.where((g) => g.category == category).toList()
        case final inCategory when inCategory.isNotEmpty)
      (category, inCategory),
];
