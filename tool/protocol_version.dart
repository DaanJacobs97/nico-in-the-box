// Keeps kProtocolVersion one above main's on every pull request into main,
// so builds from different merges never claim the same protocol. Nobody
// edits the number by hand: the "Set protocol version" workflow runs `set`
// on each PR and commits the result, and the CI job "Protocol version" runs
// `check` as the safety net (e.g. for PRs from forks, which the workflow
// can't push to).
//
//   dart tool/protocol_version.dart check [--base origin/main]
//   dart tool/protocol_version.dart set   [--base origin/main]
//
// Only dart:io, so it runs with plain Dart (no Flutter, no pub get).
import 'dart:io';

const protocolFile = 'packages/nico_shared/lib/net/protocol.dart';

final _pattern = RegExp(r'const int kProtocolVersion = (\d+);');

/// The `kProtocolVersion` in [source] (the text of protocol.dart).
int readVersion(String source) {
  final match = _pattern.firstMatch(source);
  if (match == null) throw const FormatException('kProtocolVersion not found');
  return int.parse(match.group(1)!);
}

/// [source] with `kProtocolVersion` set to [version].
String writeVersion(String source, int version) =>
    source.replaceFirst(_pattern, 'const int kProtocolVersion = $version;');

/// What a branch at [branch] must change, or null when it is right. A PR
/// into main must be exactly one above main, whatever it changes.
String? problem({required int main, required int branch}) {
  if (branch == main + 1) return null;
  return 'main is at protocol $main, so this branch must be ${main + 1} '
      '(it is $branch). On pull requests from this repository the '
      '"Set protocol version" workflow sets it for you; otherwise run '
      '`dart tool/protocol_version.dart set` and commit the result.';
}

void main(List<String> args) {
  final command = args.isEmpty ? 'check' : args.first;
  final baseAt = args.indexOf('--base');
  final base = baseAt == -1 ? 'origin/main' : args[baseAt + 1];

  final shown = Process.runSync('git', ['show', '$base:$protocolFile']);
  if (shown.exitCode != 0) {
    stderr.writeln('Could not read $protocolFile on $base: ${shown.stderr}');
    exit(2);
  }
  final mainVersion = readVersion(shown.stdout as String);
  final file = File(protocolFile);
  final source = file.readAsStringSync();
  final branchVersion = readVersion(source);

  switch (command) {
    case 'check':
      final wrong = problem(main: mainVersion, branch: branchVersion);
      if (wrong != null) {
        stderr.writeln(wrong);
        exit(1);
      }
      stdout.writeln('Protocol $branchVersion: one above main ($mainVersion).');
    case 'set':
      final wanted = mainVersion + 1;
      if (branchVersion == wanted) {
        stdout.writeln('Protocol already $wanted.');
      } else {
        file.writeAsStringSync(writeVersion(source, wanted));
        stdout.writeln('Protocol set to $wanted (was $branchVersion).');
      }
    default:
      stderr.writeln(
        'Usage: dart tool/protocol_version.dart check|set '
        '[--base origin/main]',
      );
      exit(64);
  }
}
