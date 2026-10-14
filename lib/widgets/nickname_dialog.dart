import 'package:flutter/material.dart';

import '../net/protocol.dart';

/// Asks for a nickname. Returns the trimmed nickname, or null if cancelled.
/// [errorText] is shown up front, e.g. when the previous choice was taken.
Future<String?> showNicknameDialog(
  BuildContext context, {
  String initial = '',
  String? errorText,
  String title = 'Choose a nickname',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _NicknameDialog(initial: initial, errorText: errorText, title: title),
  );
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({
    required this.initial,
    required this.errorText,
    required this.title,
  });

  final String initial;
  final String? errorText;
  final String title;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  late String? _error = widget.errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = normalizeNickname(_controller.text);
    if (name == null) {
      setState(() => _error = 'Use 1–$kMaxNicknameLength characters.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: kMaxNicknameLength,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: 'Nickname', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Join')),
      ],
    );
  }
}
