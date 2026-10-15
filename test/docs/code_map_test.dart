// Keeps docs/CODE_MAP.md honest: every source file must be listed there with
// a roughly right line count, and every path it lists must exist. Also caps
// file size. If this fails, update the code map: it is how contributors and
// AI assistants find their way without reading the repo.
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

/// Source files above this many non-blank lines must be split.
const _maxCodeLines = 600;

int _codeLines(File file) =>
    file.readAsLinesSync().where((l) => l.trim().isNotEmpty).length;

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

  test('line counts in docs/CODE_MAP.md are roughly right', () {
    // Rows look like: | `path` | 123 | purpose |. Counts are non-blank lines
    // and may drift a little; they only tell readers how big a file is.
    final rows = RegExp(r'^\| `([^`]+)` \| (\d+) \|', multiLine: true);
    final wrong = <String>[];
    for (final m in rows.allMatches(map)) {
      final file = File(m.group(1)!);
      if (!file.existsSync()) continue; // Reported by the test above.
      final listed = int.parse(m.group(2)!);
      final actual = _codeLines(file);
      final slack = (actual * 0.2).clamp(25, double.infinity);
      if ((actual - listed).abs() > slack) {
        wrong.add('${m.group(1)}: listed $listed, actually $actual');
      }
    }
    expect(
      wrong,
      isEmpty,
      reason: 'Update these line counts in docs/CODE_MAP.md',
    );
  });

  test('no source file is over $_maxCodeLines lines', () {
    final big = [
      for (final root in _sourceRoots)
        for (final path in _filesUnder(root))
          if (path.endsWith('.dart') || path.endsWith('.js'))
            if (_codeLines(File(path)) > _maxCodeLines)
              '$path: ${_codeLines(File(path))}',
    ];
    expect(
      big,
      isEmpty,
      reason:
          'Split these into smaller files with one job each (and list them '
          'in docs/CODE_MAP.md). Small files are cheaper to read and review.',
    );
  });
}
