import 'package:flutter/material.dart';

import '../games/game_session.dart';

/// A game's options in the lobby: switches and choices for the host, the
/// active rules as text for everyone else. Shows nothing for games without
/// options.
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
          if (onChanged == null)
            ListTile(
              key: ValueKey('game-option-${option.id}'),
              dense: true,
              leading: const Icon(Icons.rule),
              title: Text(option.label),
              subtitle: option.description.isEmpty
                  ? null
                  : Text(option.description),
              trailing: Text(_shown(option.describe(values[option.id]))),
            )
          else if (option.isChoice)
            _ChoiceTile(
              key: ValueKey('game-option-${option.id}'),
              option: option,
              value: values[option.id] ?? option.defaultValue,
              onChanged: (id) => onChanged({option.id: id}),
            )
          else
            SwitchListTile(
              key: ValueKey('game-option-${option.id}'),
              title: Text(option.label),
              subtitle: option.description.isEmpty
                  ? null
                  : Text(option.description),
              value: (values[option.id] ?? option.defaultValue) == true,
              onChanged: (on) => onChanged({option.id: on}),
            ),
      ],
    );
  }

  /// "on" reads better as "On" on its own; choice labels stay as they are.
  static String _shown(String text) => switch (text) {
    'on' => 'On',
    'off' => 'Off',
    _ => text,
  };
}

/// The host picks one of a choice option's values.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.option,
    required this.value,
    required this.onChanged,
  });

  final GameOption option;
  final Object value;
  final void Function(String id) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(option.label, style: theme.textTheme.bodyLarge),
          if (option.description.isNotEmpty)
            Text(
              option.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final c in option.choices)
                  ButtonSegment(
                    value: c.id,
                    label: Text(
                      c.label,
                      key: ValueKey('game-option-${option.id}-${c.id}'),
                    ),
                  ),
              ],
              selected: {if (value is String) value as String},
              emptySelectionAllowed: true,
              onSelectionChanged: (picked) {
                if (picked.isNotEmpty) onChanged(picked.single);
              },
            ),
          ),
        ],
      ),
    );
  }
}
