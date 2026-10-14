import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('nicobox/multicast');

/// Holds Android's Wi-Fi multicast lock while scanning so broadcast
/// announcements aren't filtered out. A no-op on other platforms.
abstract final class MulticastLock {
  static Future<void> acquire() => _call('acquire');

  static Future<void> release() => _call('release');

  static Future<void> _call(String method) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (e) {
      debugPrint('Multicast lock $method failed: $e');
    }
  }
}
