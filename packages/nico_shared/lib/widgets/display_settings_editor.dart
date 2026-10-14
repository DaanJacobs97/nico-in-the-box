import 'package:flutter/material.dart';

import '../net/protocol.dart';

/// Where the shared screen is, as one choice for the host.
enum ScreenChoice {
  /// The host's own device shows the table; the host takes no seat.
  thisDevice,

  /// A browser (e.g. a smart TV) opens the host's screen page.
  browser,

  /// A device running the Caster app, picked by the host.
  caster;

  static ScreenChoice of(DisplaySettings s) => !s.hostPlays
      ? thisDevice
      : s.target == DisplayTarget.caster
      ? caster
      : browser;

  DisplaySettings applyTo(DisplaySettings s) => switch (this) {
    thisDevice => s.copyWith(hostPlays: false),
    browser => s.copyWith(hostPlays: true, target: DisplayTarget.browser),
    caster => s.copyWith(hostPlays: true, target: DisplayTarget.caster),
  };
}

/// The host's Single game screen controls, used in host setup and the
/// lobby. Pass a null [onChanged] to show the settings read-only.
class DisplaySettingsEditor extends StatelessWidget {
  const DisplaySettingsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.casterAvailable = false,
  });

  final DisplaySettings value;
  final ValueChanged<DisplaySettings>? onChanged;

  /// The Caster app isn't connectable yet; its option is shown disabled.
  final bool casterAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choice = ScreenChoice.of(value);
    final change = onChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('single-screen-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Single game screen'),
          subtitle: const Text(
            'Show the table on one shared screen. Players see only their '
            'own hand and buttons.',
          ),
          value: value.enabled,
          onChanged: change == null
              ? null
              : (on) => change(value.copyWith(enabled: on)),
        ),
        if (value.enabled) ...[
          const SizedBox(height: 8),
          Text(
            'Where is the shared screen?',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<ScreenChoice>(
            segments: [
              const ButtonSegment(
                value: ScreenChoice.thisDevice,
                icon: Icon(Icons.tv),
                label: Text('This device'),
              ),
              const ButtonSegment(
                value: ScreenChoice.browser,
                icon: Icon(Icons.language),
                label: Text('A browser'),
              ),
              ButtonSegment(
                value: ScreenChoice.caster,
                icon: const Icon(Icons.cast),
                label: Text(casterAvailable ? 'Caster app' : 'Caster (soon)'),
                enabled: casterAvailable,
              ),
            ],
            selected: {choice},
            onSelectionChanged: change == null
                ? null
                : (set) => change(set.single.applyTo(value)),
          ),
          const SizedBox(height: 8),
          Text(switch (choice) {
            ScreenChoice.thisDevice =>
              "This device shows the table, so you don't take a seat. You "
                  'keep the host controls.',
            ScreenChoice.browser =>
              'Open the screen address on a TV or computer browser. You '
                  'play on this device as usual.',
            ScreenChoice.caster =>
              'Pick a device running the Caster app. You play on this '
                  'device as usual.',
          }, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
