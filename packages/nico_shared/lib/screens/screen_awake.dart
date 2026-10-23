import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the display on while this device is in a room: hosting (a hosting
/// tablet is often the shared screen nobody touches, and if it sleeps,
/// Android may suspend the app and drop the room for everyone) and playing
/// (waiting for others shouldn't lock your phone). Works in the apps and,
/// where the browser allows it, in the browser client.
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
    // Future.sync, not Future(): no timer, so widget tests have none pending.
    unawaited(
      Future.sync(() => on ? WakelockPlus.enable() : WakelockPlus.disable())
          .catchError((Object _) {}),
    );
  }
}
