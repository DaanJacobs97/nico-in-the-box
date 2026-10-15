import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the display on while this device hosts a room. A hosting tablet is
/// often the shared screen nobody touches, and if it dims and sleeps, Android
/// may suspend the app and drop the room for everyone.
abstract final class ScreenAwake {
  static int _holders = 0;

  /// How many holders currently keep the screen on (for tests).
  static int get holders => _holders;

  /// Asks for the screen to stay on. Pair every call with [release].
  static void hold() {
    if (_holders++ == 0) _set(true);
  }

  static void release() {
    if (_holders == 0) return;
    if (--_holders == 0) _set(false);
  }

  static void _set(bool on) {
    // Best effort: unsupported platforms and tests (no plugin) just carry on.
    unawaited(
      Future(() => on ? WakelockPlus.enable() : WakelockPlus.disable())
          .catchError((Object _) {}),
    );
  }
}
