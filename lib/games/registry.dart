import 'color_clash/color_clash_game.dart';
import 'game_session.dart';
import 'tictactoe/tictactoe_game.dart';

/// Every game the host can pick, in display order.
const List<GameDefinition> availableGames = [
  ticTacToeDefinition,
  colorClashDefinition,
];

GameDefinition? gameById(String id) {
  for (final game in availableGames) {
    if (game.id == id) return game;
  }
  return null;
}
