import 'package:flutter/material.dart';

import '../games/game_session.dart';

/// A game's options in the lobby: switches for the host, the active rules as
/// text for everyone else. Shows nothing for games without options.
class GameOptionsEditor extends StatelessWidget {
  const GameOptionsEditor({
    super.key,
    required this.game,
    required this.values,
    this.onChanged,
  });

  final GameDefinition game;
  final GameOptions values;

  /// Called with the one changed option. Null makes the editor read-only.
  final void Function(GameOptions changes)? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in game.options)
          if (onChanged != null)
            SwitchListTile(
              key: ValueKey('game-option-${option.id}'),
              title: Text(option.label),
              subtitle: option.description.isEmpty
                  ? null
                  : Text(option.description),
              value: values[option.id] ?? option.defaultValue,
              onChanged: (on) => onChanged({option.id: on}),
            )
          else
            ListTile(
              key: ValueKey('game-option-${option.id}'),
              dense: true,
              leading: const Icon(Icons.rule),
              title: Text(option.label),
              subtitle: option.description.isEmpty
                  ? null
                  : Text(option.description),
              trailing: Text(
                (values[option.id] ?? option.defaultValue) ? 'On' : 'Off',
              ),
            ),
      ],
    );
  }
}
