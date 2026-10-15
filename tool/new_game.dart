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
    ..writeAsStringSync(content);
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

const _gameTemplate = r'''
import 'dart:math';

import '../../net/protocol.dart';
import '../game_session.dart';

// Generated by tool/new_game.dart. The placeholder rules (take turns adding
// 1 or 2; first to the target wins) only show the patterns: replace them.
// See docs/ADDING_A_GAME.md, section 2.

const __CAMEL__Definition = GameDefinition(
  id: '__ID__',
  name: '__NAME__',
  description: 'TODO: one line the host sees when picking a game.',
  minPlayers: __MIN__,
  maxPlayers: __MAX__,
  createSession: _create,
);

GameSession _create(List<PlayerInfo> players, int round, Random random) =>
    __PASCAL__Session(players, round: round, random: random);

/// Actions: `{'type': 'add', 'amount': 1 | 2}`.
///
/// The starting seat moves on every round, so rematches are fair.
class __PASCAL__Session implements GameSession {
  __PASCAL__Session(this._players, {int round = 0, Random? random})
    : _turn = round % _players.length {
    // Use the given Random for anything random, so tests can replay games.
    final rng = random ?? Random();
    for (final p in _players) {
      _scores[p.id] = 0;
      // Stands in for private data such as a hand of cards.
      _secrets[p.id] = rng.nextInt(100);
    }
  }

  static const target = 10;

  final List<PlayerInfo> _players;
  final Map<String, int> _scores = {};
  final Map<String, int> _secrets = {};
  int _turn;
  String? _winnerId;

  String get _turnId => _players[_turn].id;

  @override
  bool get isOver => _winnerId != null;

  @override
  void applyAction(String playerId, Json action) {
    if (!_scores.containsKey(playerId)) {
      throw const GameActionException('You are not playing this game.');
    }
    if (isOver) throw const GameActionException('The game is over.');
    if (playerId != _turnId) {
      throw const GameActionException("It's not your turn.");
    }
    if (action['type'] != 'add') {
      throw const GameActionException('Unknown move.');
    }
    final amount = action['amount'];
    if (amount is! int || amount < 1 || amount > 2) {
      throw const GameActionException('Add 1 or 2.');
    }

    final score = _scores[playerId]! + amount;
    _scores[playerId] = score;
    if (score >= target) {
      _winnerId = playerId;
      return;
    }
    _turn = (_turn + 1) % _players.length;
  }

  /// Public state only: shared screens show it to everyone in the room.
  @override
  Json tableView() => {
    'order': [for (final p in _players) p.id],
    'scores': Map.of(_scores),
    'target': target,
    'turn': isOver ? null : _turnId,
    'winner': _winnerId,
  };

  /// The table plus this player's private data, so the two can't drift.
  @override
  Json viewFor(String playerId) => {
    ...tableView(),
    'secret': _secrets[playerId],
  };

  @override
  Json? get result {
    final winnerId = _winnerId;
    if (winnerId == null) return null;
    final name = _players.firstWhere((p) => p.id == winnerId).nickname;
    return {
      'winnerIds': [winnerId],
      'summary': '$name wins!',
    };
  }
}
''';

const _viewTemplate = r'''
import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';

// Generated by tool/new_game.dart: placeholder UI for the placeholder rules.
// See docs/ADDING_A_GAME.md, sections 3 and 4.

/// What a player sees and taps. While a shared screen shows the table
/// (`ctx.compact`), only the status line and this player's inputs remain.
class __PASCAL__View extends StatelessWidget {
  const __PASCAL__View({super.key, required this.ctx});

  final GameViewContext ctx;

  @override
  Widget build(BuildContext context) {
    final view = ctx.view;
    final turn = view['turn'] as String?;
    final winner = view['winner'] as String?;
    final myTurn = turn == ctx.myId;
    final String status;
    if (winner != null) {
      status = winner == ctx.myId
          ? 'You win!'
          : '${ctx.nicknameOf(winner)} wins!';
    } else {
      status = myTurn ? 'Your turn' : 'Waiting for ${ctx.nicknameOf(turn!)}';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            status,
            key: const ValueKey('__ID__-status'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        if (ctx.compact)
          const Spacer()
        else
          Expanded(
            child: _Scores(table: view, nameOf: ctx.nicknameOf),
          ),
        Text('Your secret number: ${view['secret']}'),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            children: [
              for (final amount in [1, 2])
                FilledButton(
                  // Stable keys let tests and the LAN bot find inputs.
                  key: ValueKey('__ID__-add-$amount'),
                  onPressed: myTurn
                      ? () => ctx.sendAction({'type': 'add', 'amount': amount})
                      : null,
                  child: Text('+$amount'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// __NAME__ on the shared screen: big and read-only. Scales real sizes, not
/// `Transform.scale`, so nothing overlaps on a TV.
class __PASCAL__Table extends StatelessWidget {
  const __PASCAL__Table({super.key, required this.ctx});

  final TableContext ctx;

  @override
  Widget build(BuildContext context) {
    final table = ctx.table;
    final turn = table['turn'] as String?;
    final winner = table['winner'] as String?;
    final status = winner != null
        ? '${ctx.nicknameOf(winner)} wins!'
        : "${ctx.nicknameOf(turn!)}'s turn";
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.biggest.shortestSide / 450).clamp(1.0, 2.5);
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16 * scale),
              child: Text(status, style: TextStyle(fontSize: 28 * scale)),
            ),
            Expanded(
              child: _Scores(
                table: table,
                nameOf: ctx.nicknameOf,
                scale: scale,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Everyone's score in turn order: in the full player view and on the table.
class _Scores extends StatelessWidget {
  const _Scores({required this.table, required this.nameOf, this.scale = 1});

  final Json table;
  final String Function(String playerId) nameOf;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final order = (table['order']! as List<Object?>).cast<String>();
    final scores = (table['scores']! as Json).cast<String, int>();
    final target = table['target']! as int;
    final style = TextStyle(fontSize: 18 * scale);
    return ListView(
      padding: EdgeInsets.all(16 * scale),
      children: [
        for (final id in order)
          ListTile(
            selected: id == table['turn'],
            title: Text(nameOf(id), style: style),
            trailing: Text('${scores[id]} / $target', style: style),
          ),
      ],
    );
  }
}
''';

const _jsTemplate = r'''
'use strict';

// __NAME__ table, generated by tool/new_game.dart with placeholder rules.
// Mirrors __PASCAL__Table in packages/nico_shared. See docs/ADDING_A_GAME.md.
NicoDisplay.register('__ID__', (table, lobby, { el, nameOf }) => {
  const status = table.winner
    ? `${nameOf(lobby, table.winner)} wins!`
    : `${nameOf(lobby, table.turn)}'s turn`;

  const scores = table.order.map((id) =>
    el(
      'div',
      { class: 'status' },
      `${id === table.turn ? '▶ ' : ''}${nameOf(lobby, id)}: ` +
        `${table.scores[id]} / ${table.target}`
    )
  );

  return el('div', { class: 'game' }, el('h2', {}, status), ...scores);
});
''';

const _engineTestTemplate = r'''
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/__ID__/__ID___game.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/net/protocol.dart';

// Generated by tool/new_game.dart. These test the placeholder rules: keep the
// groups and rewrite them for your game (docs/ADDING_A_GAME.md, section 7).

List<PlayerInfo> _players(int count) => [
  for (var i = 1; i <= count; i++) PlayerInfo(id: 'p$i', nickname: 'Player $i'),
];

Json _add(int amount) => {'type': 'add', 'amount': amount};

String _turn(__PASCAL__Session s) => s.tableView()['turn']! as String;

void main() {
  group('setup', () {
    test('everyone starts at zero and the start moves each round', () {
      final s = __PASCAL__Session(_players(2));
      expect(s.tableView()['scores'], {'p1': 0, 'p2': 0});
      expect(_turn(s), 'p1');
      expect(_turn(__PASCAL__Session(_players(2), round: 1)), 'p2');
    });
  });

  group('rules', () {
    test('a move adds to the score and passes the turn', () {
      final s = __PASCAL__Session(_players(2))..applyAction('p1', _add(2));
      expect((s.tableView()['scores']! as Json)['p1'], 2);
      expect(_turn(s), 'p2');
    });
  });

  group('rejections', () {
    for (final (who, action, why) in [
      ('p2', _add(1), 'out of turn'),
      ('p1', _add(3), 'too much'),
      ('p1', <String, Object?>{'type': 'jump'}, 'unknown move'),
      ('nobody', _add(1), 'not a player'),
    ]) {
      test(why, () {
        final s = __PASCAL__Session(_players(2));
        expect(
          () => s.applyAction(who, action),
          throwsA(isA<GameActionException>()),
        );
        expect(_turn(s), 'p1', reason: 'a rejected move changes nothing');
      });
    }
  });

  group('end', () {
    test('first to the target wins, and then nothing more is allowed', () {
      final s = __PASCAL__Session(_players(2));
      while (!s.isOver) {
        s.applyAction(_turn(s), _add(2));
      }
      expect(s.result!['winnerIds'], ['p1']);
      expect(
        () => s.applyAction('p2', _add(1)),
        throwsA(isA<GameActionException>()),
      );
    });
  });

  group('random games', () {
    for (var seed = 0; seed < 20; seed++) {
      test('seed $seed ends without leaking private data', () {
        final random = Random(seed);
        final players = _players(__MIN__ + seed % (__MAX__ - __MIN__ + 1));
        final s = __PASCAL__Session(players, round: seed, random: random);
        for (var moves = 0; !s.isOver; moves++) {
          expect(moves, lessThan(1000), reason: 'the game never ends');
          _expectPrivate(s, players);
          s.applyAction(_turn(s), _add(1 + random.nextInt(2)));
        }
        expect(s.result, isNotNull);
      });
    }
  });
}

/// Privacy: the table holds no private data, and every view agrees with the
/// table on the public part. Extend this when you add private fields.
void _expectPrivate(__PASCAL__Session s, List<PlayerInfo> players) {
  final table = s.tableView();
  expect(table, isNot(contains('secret')));
  for (final p in players) {
    final view = s.viewFor(p.id);
    for (final key in table.keys) {
      expect(view[key], table[key], reason: 'view and table differ on $key');
    }
  }
}
''';

const _viewTestTemplate = r'''
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/__ID__/__ID___game.dart';
import 'package:nico_shared/games/__ID__/__ID___view.dart';
import 'package:nico_shared/games/game_views.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/shared_screen_view.dart';

// Generated by tool/new_game.dart. Keep these cases when you replace the
// placeholder UI (docs/ADDING_A_GAME.md, section 7).

const ann = PlayerInfo(id: 'a', nickname: 'Ann');
const bob = PlayerInfo(id: 'b', nickname: 'Bob');

const lobby = LobbyState(
  roomName: 'Party',
  gameId: '__ID__',
  players: [ann, bob],
  minPlayers: __MIN__,
  maxPlayers: __MAX__,
  hostId: 'a',
  hostName: 'Ann',
  phase: RoomPhase.playing,
);

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  final session = __PASCAL__Session(const [ann, bob]);

  Widget view({required bool compact, List<Json>? sent}) => __PASCAL__View(
    ctx: GameViewContext(
      view: session.viewFor('a'),
      myId: 'a',
      lobby: lobby,
      sendAction: (action) => sent?.add(action),
      compact: compact,
    ),
  );

  testWidgets('full view shows the table and the inputs', (tester) async {
    await pumpAt(tester, const Size(400, 800), view(compact: false));
    expect(tester.takeException(), isNull);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byKey(const ValueKey('__ID__-add-1')), findsOneWidget);
  });

  testWidgets('compact view hides the table but keeps inputs', (tester) async {
    final sent = <Json>[];
    await pumpAt(tester, const Size(400, 800), view(compact: true, sent: sent));
    expect(tester.takeException(), isNull);
    expect(find.text('Bob'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('__ID__-add-2')));
    expect(sent, [
      {'type': 'add', 'amount': 2},
    ]);
  });

  testWidgets('shared screen shows the table at TV size', (tester) async {
    await pumpAt(
      tester,
      const Size(1920, 1080),
      SharedScreenView(
        state: DisplayState(
          lobby: lobby,
          gameId: '__ID__',
          table: session.tableView(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text("Ann's turn"), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });
}
''';
