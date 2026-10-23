import 'package:flutter/material.dart';

import '../games/game_session.dart';

IconData gameCategoryIcon(GameCategory category) => switch (category) {
  GameCategory.card => Icons.style,
  GameCategory.board => Icons.castle,
  GameCategory.grid => Icons.grid_on,
  GameCategory.gambling => Icons.casino,
  GameCategory.adventure => Icons.map,
};

/// A category's icon and name above its games in the host's game pickers.
class GameCategoryHeader extends StatelessWidget {
  const GameCategoryHeader({super.key, required this.category});

  final GameCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Row(
      children: [
        Icon(gameCategoryIcon(category), size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          category.label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
