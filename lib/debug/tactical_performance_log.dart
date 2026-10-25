import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Native-only, opt-in tactical performance log stored in the system temp dir.
class TacticalPerformanceLog {
  TacticalPerformanceLog._();

  static const enabled = bool.fromEnvironment('TACTICAL_PERF_LOG');
  static File? _file;
  static Future<void> _writeQueue = Future<void>.value();

  static void Function(Map<String, Object?> event)? get sink =>
      enabled ? record : null;

  static void record(Map<String, Object?> event) {
    if (!enabled) return;
    _writeQueue = _writeQueue
        .then((_) async {
          final file = await _getFile();
          final line = jsonEncode({
            'timestamp': DateTime.now().toIso8601String(),
            ...event,
          });
          await file.writeAsString(
            '$line\n',
            mode: FileMode.append,
            flush: true,
          );
        })
        .catchError((Object error) {
          debugPrint('Tactical performance log failed: $error');
        });
  }

  static Future<File> _getFile() async {
    final existing = _file;
    if (existing != null) return existing;
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File(
      '${Directory.systemTemp.path}/nico-tactical-performance-$timestamp.jsonl',
    );
    await file.create(recursive: true);
    _file = file;
    debugPrint('Tactical performance log: ${file.path}');
    return file;
  }
}
