import 'package:flutter/material.dart';
import 'package:nico_shared/app/prefs.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/games/registry.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/session_screen.dart';
import 'package:nico_shared/widgets/display_settings_editor.dart';
import 'package:nico_shared/widgets/game_category_header.dart';

import '../net/hosted_room.dart';
import '../widgets/caster_picker.dart';
import '../widgets/join_info.dart';

class HostSetupScreen extends StatefulWidget {
  const HostSetupScreen({super.key});

  @override
  State<HostSetupScreen> createState() => _HostSetupScreenState();
}

class _HostSetupScreenState extends State<HostSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _roomName = TextEditingController();
  GameDefinition _game = availableGames.first;
  DisplaySettings _display = DisplaySettings.off;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    Prefs.nickname().then((name) {
      if (mounted && _nickname.text.isEmpty) _nickname.text = name;
    });
  }

  @override
  void dispose() {
    _nickname.dispose();
    _roomName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final nickname = normalizeNickname(_nickname.text)!;
    final roomName = _roomName.text.trim().isEmpty
        ? "$nickname's room"
        : _roomName.text.trim();

    setState(() => _creating = true);
    try {
      final room = await HostedRoom.create(
        roomName: roomName,
        game: _game,
        nickname: nickname,
        display: _display,
      );
      await Prefs.saveNickname(nickname);
      if (!mounted) {
        await room.close();
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SessionScreen(
            client: room.client,
            onClose: room.close,
            hostFooter: JoinInfo(room: room),
            casterAvailable: true,
            hostScreenControls: (lobby) =>
                ScreenChoice.of(lobby.display) == ScreenChoice.caster
                ? CasterPicker(room: room, lobby: lobby)
                : null,
          ),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create the room: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Host a game')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nickname,
              maxLength: kMaxNicknameLength,
              decoration: const InputDecoration(
                labelText: 'Your nickname',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) => normalizeNickname(value ?? '') == null
                  ? 'Use 1–$kMaxNicknameLength characters.'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _roomName,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: 'Room name (optional)',
                prefixIcon: Icon(Icons.meeting_room),
              ),
            ),
            const SizedBox(height: 16),
            Text('Pick a game', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            RadioGroup<GameDefinition>(
              groupValue: _game,
              onChanged: (game) => setState(() => _game = game ?? _game),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (category, games) in gamesByCategory()) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                      child: GameCategoryHeader(
                        key: ValueKey('category-${category.name}'),
                        category: category,
                      ),
                    ),
                    for (final game in games)
                      Card(
                        child: RadioListTile<GameDefinition>(
                          key: ValueKey('pick-game-${game.id}'),
                          value: game,
                          title: Text(game.name),
                          subtitle: Text(
                            '${game.playerRange} · ${game.description}',
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            DisplaySettingsEditor(
              value: _display,
              onChanged: (value) => setState(() => _display = value),
              casterAvailable: true,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: _creating
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Create room'),
              onPressed: _creating ? null : _create,
            ),
          ],
        ),
      ),
    );
  }
}
