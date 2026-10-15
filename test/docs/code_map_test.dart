// Keeps docs/CODE_MAP.md honest: every source file must be listed there, and
// every path it lists must exist. If this fails, update the code map: it's
// how contributors and AI assistants find their way without reading the repo.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sourceRoots = [
  'lib',
  'packages/nico_shared/lib',
  'packages/nico_native/lib',
  'caster/lib',
  'web_client/lib',
  'assets/display',
  'tool',
];

const _testRoots = [
  'test',
  'packages/nico_shared/test',
  'packages/nico_native/test',
  'caster/test',
  'web_client/test',
  'integration_test',
];

const _extensions = ['.dart', '.js', '.html', '.css', '.ps1', '.sh', '.kt'];

/// Hand-written files outside the roots above that the map must mention.
const _extraSources = [
  'android/app/src/main/kotlin/com/daanjacobs97/nico_in_the_box/MainActivity.kt',
];

Iterable<String> _filesUnder(String root) sync* {
  final dir = Directory(root);
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (_extensions.any(path.endsWith)) yield path;
  }
}

void main() {
  final map = File('docs/CODE_MAP.md').readAsStringSync();

  test('every source file is listed in docs/CODE_MAP.md', () {
    final missing = [
      for (final root in _sourceRoots) ..._filesUnder(root),
      ..._extraSources,
    ].where((path) => !map.contains('`$path`')).toList();
    expect(
      missing,
      isEmpty,
      reason: 'Add these to docs/CODE_MAP.md with a one-line description',
    );
  });

  test('every test file is mentioned in docs/CODE_MAP.md', () {
    final missing = [for (final root in _testRoots) ..._filesUnder(root)]
        .where((path) => !map.contains(path.split('/').last))
        .toList();
    expect(
      missing,
      isEmpty,
      reason: 'Mention these in the "Tests" section of docs/CODE_MAP.md',
    );
  });

  test('every path listed in docs/CODE_MAP.md exists', () {
    const prefixes = [
      'lib/',
      'packages/',
      'caster/',
      'web_client/',
      'assets/',
      'tool/',
      'test/',
      'integration_test/',
      'android/',
    ];
    final listed = RegExp(r'`([\w./-]+\.(?:dart|js|html|css|ps1|sh|kt))`')
        .allMatches(map)
        .map((m) => m.group(1)!)
        .where((p) => prefixes.any(p.startsWith))
        .toSet();
    final stale = listed.where((p) => !File(p).existsSync()).toList();
    expect(
      stale,
      isEmpty,
      reason: 'These no longer exist; update docs/CODE_MAP.md',
    );
  });
}
