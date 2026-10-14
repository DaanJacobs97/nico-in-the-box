import 'package:flutter/material.dart';
import 'package:nico_shared/net/protocol.dart';

/// Shown until a host picks this Caster: its name (editable) and address.
class IdleScreen extends StatelessWidget {
  const IdleScreen({
    super.key,
    required this.name,
    required this.addresses,
    required this.port,
    required this.onRename,
    this.error,
  });

  final String name;
  final List<String> addresses;
  final int? port;
  final ValueChanged<String> onRename;
  final String? error;

  Future<void> _editName(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: name),
    );
    final trimmed = result?.trim() ?? '';
    if (trimmed.isNotEmpty) onRename(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cast, size: 96, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Waiting for a host',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: theme.textTheme.headlineMedium),
                IconButton(
                  tooltip: 'Rename this screen',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editName(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              )
            else ...[
              Text(
                'In Nico in the Box, the host turns on Single game screen, '
                'chooses Caster app and picks this screen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (port != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Not in the list? Enter this address:',
                  style: theme.textTheme.bodyMedium,
                ),
                for (final address in addresses)
                  SelectableText(
                    port == kCasterPort ? address : '$address:$port',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Owns its text controller so it outlives the dialog's closing animation.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this screen'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        decoration: const InputDecoration(labelText: 'Screen name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
