import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/protocol_version.dart';

void main() {
  group('problem', () {
    test('one above main is right', () {
      expect(problem(main: 6, branch: 7), isNull);
    });

    test('anything else names the number to use', () {
      for (final branch in [6, 5, 8, 9]) {
        expect(problem(main: 6, branch: branch), contains('must be 7'));
      }
    });
  });

  test('reads and writes the constant, leaving the rest alone', () {
    const source =
        '// Protocol.\nconst int kProtocolVersion = 6;\nconst x = 1;\n';
    expect(readVersion(source), 6);
    final written = writeVersion(source, 7);
    expect(readVersion(written), 7);
    expect(written, source.replaceFirst('= 6;', '= 7;'));
  });

  test('the real protocol.dart has a readable version', () {
    expect(readVersion(File(protocolFile).readAsStringSync()), greaterThan(0));
  });

  // Two branches both bump 5 -> 6. Git merges identical edits silently, so
  // the second PR ends up claiming main's 6 after updating; the check must
  // catch that and `set` must fix it to 7.
  test('the silent-merge case, end to end with real git', () async {
    final dir = await Directory.systemTemp.createTemp('protocol_version');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('tool/protocol_version.dart').absolute.path;
    final file = File('${dir.path}/$protocolFile')..createSync(recursive: true);

    ProcessResult run(String exe, List<String> args) => Process.runSync(
      exe,
      args,
      workingDirectory: dir.path,
      runInShell: true, // `dart` is a .bat file on Windows
    );
    void git(List<String> args) {
      final r = run('git', [
        '-c',
        'user.name=t',
        '-c',
        'user.email=t@t',
        ...args,
      ]);
      expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
    }

    void commitVersion(int v, String message) {
      file.writeAsStringSync('const int kProtocolVersion = $v;\n');
      git(['commit', '-qam', message]);
    }

    git(['init', '-q', '-b', 'main']);
    file.writeAsStringSync('const int kProtocolVersion = 5;\n');
    git(['add', '.']);
    git(['commit', '-qm', 'start at 5']);
    git(['checkout', '-qb', 'friend']);
    commitVersion(6, 'friend bumps to 6');
    git(['checkout', '-q', 'main']);
    commitVersion(6, 'another PR merged at 6');

    // The friend updates his branch from main: no conflict, still 6.
    git(['checkout', '-q', 'friend']);
    git(['merge', '-q', '--no-edit', 'main']);
    expect(readVersion(file.readAsStringSync()), 6);

    final check = run('dart', [script, 'check', '--base', 'main']);
    expect(check.exitCode, 1);
    expect(check.stderr, contains('must be 7'));

    final set = run('dart', [script, 'set', '--base', 'main']);
    expect(set.exitCode, 0, reason: '${set.stderr}');
    expect(readVersion(file.readAsStringSync()), 7);
    expect(run('dart', [script, 'check', '--base', 'main']).exitCode, 0);
  });
}
