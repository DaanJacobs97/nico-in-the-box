// Scaffolds a new game: engine, player view, Flutter table, browser table,
// tests, registration, code map rows and a protocol version bump.
//
//   dart run tool/new_game.dart <id> "<Name>" [minPlayers] [maxPlayers]
//   dart run tool/new_game.dart dicewar "Dice War" 2 6
//
// The generated game has placeholder rules (take turns adding 1 or 2; first
// to 10 wins) that show every pattern from docs/ADDING_A_GAME.md, and all
// checks pass right away. Then replace the rules, views and tests with your
// game's. Undo with `git checkout -- . && git clean -fd` before committing.
import 'dart:io';

part 'new_game_templates.dart';

void main(List<String> args) {
  if (args.length < 2 || args.length > 4) _fail(_usage);
  final id = args[0];
  final name = args[1].trim();
  final min = args.length > 2 ? int.tryParse(args[2]) : 2;
  final max = args.length > 3 ? int.tryParse(args[3]) : (min ?? 2) + 2;

  if (!RegExp(r'^[a-z][a-z0-9]*$').hasMatch(id)) {
    _fail('The id must be lowercase letters and digits, such as "dicewar".');
  }
  if (name.isEmpty) _fail('Give the game a name, such as "Dice War".');
  if (min == null || max == null || min < 2 || max < min) {
    _fail('Player counts must be numbers with 2 <= min <= max.');
  }
  if (!File('pubspec.yaml').existsSync() ||
      !Directory(_gamesDir).existsSync()) {
    _fail('Run this from the repository root.');
  }
  if (Directory('$_gamesDir/$id').existsSync() ||
      File(_registry).readAsStringSync().contains("id: '$id'")) {
    _fail('A game with id "$id" already exists.');
  }

  final pascal = _pascalCase(name);
  if (pascal.isEmpty || !RegExp('^[A-Z]').hasMatch(pascal)) {
    _fail('The name must start with a letter.');
  }
  final camel = pascal[0].toLowerCase() + pascal.substring(1);
  String fill(String template) => template
      .replaceAll('__ID__', id)
      // A Dart string literal in the definition, plain text in comments.
      .replaceAll("'__NAME__'", _dartString(name))
      .replaceAll('__NAME__', name)
      .replaceAll('__PASCAL__', pascal)
      .replaceAll('__CAMEL__', camel)
      .replaceAll('__MIN__', '$min')
      .replaceAll('__MAX__', '$max');

  final gameFile = '$_gamesDir/$id/${id}_game.dart';
  final viewFile = '$_gamesDir/$id/${id}_view.dart';
  final jsFile = 'assets/display/games/$id.js';
  final engineTest = 'packages/nico_shared/test/games/${id}_test.dart';
  final viewTest = 'packages/nico_shared/test/widgets/${id}_view_test.dart';

  _write(gameFile, fill(_gameTemplate));
  _write(viewFile, fill(_viewTemplate));
  _write(jsFile, fill(_jsTemplate));
  _write(engineTest, fill(_engineTestTemplate));
  _write(viewTest, fill(_viewTestTemplate));

  _edit(_registry, (s) {
    s = _addImport(s, "import '$id/${id}_game.dart';");
    return _insertBefore(s, '];', '  ${camel}Definition,\n', after: 'const');
  });
  _edit(_gameViews, (s) {
    s = _addImport(s, "import '$id/${id}_view.dart';");
    s = _insertBefore(
      s,
      '};',
      "  '$id': (ctx) => ${pascal}View(ctx: ctx),\n",
      after: 'gameViews',
    );
    return _insertBefore(
      s,
      '};',
      "  '$id': (ctx) => ${pascal}Table(ctx: ctx),\n",
      after: 'gameTables',
    );
  });
  _edit('assets/display/index.html', (s) {
    final tags = RegExp(r'^.*<script src="games/.*$', multiLine: true);
    final last = tags.allMatches(s).last;
    return '${s.substring(0, last.end)}\n'
        '<script src="games/$id.js"></script>${s.substring(last.end)}';
  });
  var version = 0;
  _edit(_protocol, (s) {
    final pattern = RegExp(r'const int kProtocolVersion = (\d+);');
    final match = pattern.firstMatch(s)!;
    version = int.parse(match.group(1)!) + 1;
    return s.replaceFirst(pattern, 'const int kProtocolVersion = $version;');
  });

  final dartFiles = [gameFile, viewFile, engineTest, viewTest, _registry];
  final format = Process.runSync('dart', [
    'format',
    ...dartFiles,
    _gameViews,
  ], runInShell: true);
  if (format.exitCode != 0) stderr.write(format.stderr);

  _edit(_codeMap, (s) {
    String row(String path, String what) =>
        '| `$path` | ${_codeLines(path)} | $what |\n';
    s = _insertAfterLastLine(
      s,
      '| `$_gamesDir/',
      row(gameFile, '$name engine (generated placeholder rules)') +
          row(viewFile, '$name player view + `${pascal}Table`'),
    );
    s = _insertAfterLastLine(
      s,
      '| `assets/display/games/',
      row(jsFile, '$name table renderer'),
    );
    return s.replaceFirst(
      '. Also runs in Chrome in CI',
      ', $name (`games/${id}_test.dart`, `widgets/${id}_view_test.dart`)'
          '. Also runs in Chrome in CI',
    );
  });

  stdout.writeln('''
Created "$name" ($id, $min-$max players) with placeholder rules:
  $gameFile
  $viewFile
  $jsFile
  $engineTest
  $viewTest
Registered it in registry.dart, game_views.dart and index.html, added it to
docs/CODE_MAP.md and bumped kProtocolVersion to $version.

Next (docs/ADDING_A_GAME.md walks through each):
  1. Write the rules in ${id}_game.dart. Keep private data out of tableView().
  2. Draw the player view and table in ${id}_view.dart, and $id.js.
  3. Rewrite the generated tests for your rules; keep the privacy check.
  4. Fix the description in ${id}_game.dart and the rows in docs/CODE_MAP.md.
  5. Run the check: tool/check.ps1 (Windows) or tool/check.sh.''');
}

const _usage =
    'Usage: dart run tool/new_game.dart <id> "<Name>" [minPlayers] '
    '[maxPlayers]\nExample: dart run tool/new_game.dart dicewar "Dice War" 2 6';
const _gamesDir = 'packages/nico_shared/lib/games';
const _registry = '$_gamesDir/registry.dart';
const _gameViews = '$_gamesDir/game_views.dart';
const _protocol = 'packages/nico_shared/lib/net/protocol.dart';
const _codeMap = 'docs/CODE_MAP.md';

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}

String _dartString(String text) {
  final escaped = text.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$');
  return escaped.contains("'")
      ? '"${escaped.replaceAll('"', r'\"')}"'
      : "'$escaped'";
}

/// "Nico's Dice War" -> "NicosDiceWar".
String _pascalCase(String name) => name
    .replaceAll(RegExp("['’]"), '')
    .split(RegExp('[^A-Za-z0-9]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join();

int _codeLines(String path) =>
    File(path).readAsLinesSync().where((l) => l.trim().isNotEmpty).length;

void _write(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      path.endsWith('.dart') ? _sortImports(content) : content,
    );
}

/// Sorts each run of consecutive import lines. Where the game's imports land
/// depends on its id, and the analyzer wants every section sorted.
String _sortImports(String source) {
  final out = <String>[];
  final run = <String>[];
  void flush() => out.addAll(run..sort());
  for (final line in source.split('\n')) {
    if (line.startsWith('import ')) {
      run.add(line);
      continue;
    }
    flush();
    run.clear();
    out.add(line);
  }
  flush();
  return out.join('\n');
}

void _edit(String path, String Function(String) change) {
  final file = File(path);
  file.writeAsStringSync(change(file.readAsStringSync()));
}

/// Adds a relative import, keeping the relative imports sorted.
String _addImport(String source, String import) {
  final relative = RegExp(r"^import '(?!package:).*$", multiLine: true);
  final matches = relative.allMatches(source).toList();
  final lines = [...matches.map((m) => m.group(0)!), import]..sort();
  return source.substring(0, matches.first.start) +
      lines.join('\n') +
      source.substring(matches.last.end);
}

/// Inserts [text] before the first [marker] that follows [after].
String _insertBefore(
  String source,
  String marker,
  String text, {
  required String after,
}) {
  final at = source.indexOf(marker, source.indexOf(after));
  return source.substring(0, at) + text + source.substring(at);
}

/// Inserts [text] after the last line that starts with [prefix].
String _insertAfterLastLine(String source, String prefix, String text) {
  final lines = RegExp('^${RegExp.escape(prefix)}.*\n', multiLine: true);
  final at = lines.allMatches(source).last.end;
  return source.substring(0, at) + text + source.substring(at);
}
