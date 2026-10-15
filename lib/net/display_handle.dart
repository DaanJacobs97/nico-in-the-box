part of 'game_server.dart';

/// A connected shared screen. Call [detach] when it goes away.
class DisplayHandle {
  DisplayHandle._(
    this.info,
    this._sendFn,
    this._closeFn, {
    required this._onDetach,
  });

  final DisplayInfo info;
  final void Function(String message) _sendFn;
  final Future<void> Function()? _closeFn;
  final void Function() _onDetach;
  bool _detached = false;

  void _send(String message) {
    if (_detached) return;
    try {
      _sendFn(message);
    } on Object {
      // The screen is going away; its detach follows.
    }
  }

  Future<void> _close() async {
    _detached = true;
    try {
      await _closeFn?.call().timeout(const Duration(seconds: 2));
    } on Object {
      // Already gone.
    }
  }

  /// Stops sending to this screen and removes it from the lobby.
  void detach() {
    if (_detached) return;
    _detached = true;
    _onDetach();
  }
}
