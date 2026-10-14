import 'package:flutter/material.dart';
import 'package:nico_shared/app/prefs.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/session_screen.dart';
import 'package:nico_shared/widgets/nickname_dialog.dart';

void main() {
  runApp(const NicoWebClientApp());
}

class NicoWebClientApp extends StatelessWidget {
  const NicoWebClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: brightness,
      ),
    );
    return MaterialApp(
      title: 'Nico in the Box',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: WebJoinScreen(host: Uri.base.host, port: _portOf(Uri.base)),
    );
  }

  static int _portOf(Uri uri) => uri.hasPort ? uri.port : kGamePort;
}

/// Entry screen for browser players. The page was served by the host, so
/// the host's address is simply the page's own address.
class WebJoinScreen extends StatefulWidget {
  const WebJoinScreen({super.key, required this.host, required this.port});

  final String host;
  final int port;

  @override
  State<WebJoinScreen> createState() => _WebJoinScreenState();
}

class _WebJoinScreenState extends State<WebJoinScreen> {
  bool _joining = false;
  String? _error;

  /// Asks for a nickname and connects, asking again if the name is refused.
  Future<void> _join() async {
    if (_joining) return;
    var nickname = await Prefs.nickname();
    String? nameError;
    while (true) {
      if (!mounted) return;
      final chosen = await showNicknameDialog(
        context,
        initial: nickname,
        errorText: nameError,
      );
      if (chosen == null || !mounted) return;
      nickname = chosen;

      setState(() {
        _joining = true;
        _error = null;
      });
      try {
        final client = await GameClient.connect(
          host: widget.host,
          port: widget.port,
          nickname: nickname,
        );
        await Prefs.saveNickname(nickname);
        if (!mounted) {
          await client.leave();
          return;
        }
        setState(() => _joining = false);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionScreen(client: client),
          ),
        );
        return;
      } on JoinException catch (e) {
        if (!mounted) return;
        setState(() => _joining = false);
        if (e.code == ErrorCode.nameTaken || e.code == ErrorCode.invalidName) {
          nameError = e.message;
          continue;
        }
        setState(() => _error = e.message);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.inventory_2_rounded,
                    size: 96,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nico in the Box',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Playing in your browser',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    icon: _joining
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(_error == null ? 'Join the room' : 'Try again'),
                    onPressed: _joining ? null : _join,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
