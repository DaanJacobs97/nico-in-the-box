import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/net/game_server.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';

class _IdleSession implements GameSession {
  @override
  void applyAction(String playerId, Json action) {}
  @override
  Json viewFor(String playerId) => {};
  @override
  Json tableView() => {};
  @override
  bool get isOver => false;
  @override
  Json? get result => null;
}

/// The options every session of [_optionsGame] was created with.
final _created = <GameOptions>[];

final _optionsGame = GameDefinition(
  id: 'opts',
  name: 'Options',
  description: 'Test game with two options.',
  minPlayers: 2,
  maxPlayers: 2,
  category: GameCategory.board,
  options: const [
    GameOption(id: 'again', label: 'Hit = shoot again'),
    GameOption(id: 'fog', label: 'Fog', defaultValue: true),
  ],
  createSession: (_, _, _, options) {
    _created.add(options);
    return _IdleSession();
  },
);

Future<void> until(GameClient client, bool Function() condition) {
  if (condition()) return Future.value();
  final done = Completer<void>();
  void check() {
    if (!done.isCompleted && condition()) done.complete();
  }

  client.addListener(check);
  return done.future
      .timeout(const Duration(seconds: 15))
      .whenComplete(() => client.removeListener(check));
}

void main() {
  late GameServer server;
  late GameClient host;
  late GameClient guest;

  setUp(() async {
    _created.clear();
    server = GameServer(
      roomName: 'Test room',
      game: _optionsGame,
      random: Random(1),
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    host = await GameClient.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      nickname: 'Nico',
      hostToken: server.hostToken,
    );
    guest = await GameClient.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      nickname: 'Daan',
    );
    await until(guest, () => guest.lobby?.players.length == 2);
  });

  tearDown(() async {
    await host.leave();
    await guest.leave();
    await server.close();
  });

  Future<List<String>> noticesFrom(
    GameClient client,
    void Function() act,
  ) async {
    final notices = <String>[];
    final sub = client.notices.listen(notices.add);
    act();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();
    return notices;
  }

  test('the lobby starts with the game defaults', () {
    expect(guest.lobby!.gameOptions, {'again': false, 'fog': true});
    expect(server.displayState.rules, ['Hit = shoot again: off', 'Fog: on']);
    expect(server.displayState.gameName, 'Options');
  });

  test('the host changes an option and everyone sees it', () async {
    host.setGameOptions({'again': true});
    await until(guest, () => guest.lobby!.gameOptions['again'] == true);
    expect(guest.lobby!.gameOptions, {'again': true, 'fog': true});
    expect(server.displayState.rules.first, 'Hit = shoot again: on');
  });

  test('only the host can change options', () async {
    final notices = await noticesFrom(
      guest,
      () => guest.setGameOptions({'again': true}),
    );
    expect(notices.single, contains('Only the host'));
    expect(server.gameOptions['again'], isFalse);
  });

  // Non-bool values are covered by GameDefinition.updateOptions's tests.
  test('unknown options are rejected', () async {
    final notices = await noticesFrom(
      host,
      () => host.setGameOptions({'nope': true}),
    );
    expect(notices.single, contains('no option "nope"'));
    expect(server.gameOptions, {'again': false, 'fog': true});
  });

  test('sessions get the options, and a restart keeps them', () async {
    host.setGameOptions({'again': true, 'fog': false});
    await until(host, () => host.lobby!.gameOptions['again'] == true);
    host.startGame();
    await until(host, () => host.lobby!.phase == RoomPhase.playing);
    host.restartGame();
    await until(host, () => _created.length == 2);
    expect(_created, everyElement({'again': true, 'fog': false}));
  });

  test('options are locked while a game runs', () async {
    host.startGame();
    await until(host, () => host.lobby!.phase == RoomPhase.playing);
    final notices = await noticesFrom(
      host,
      () => host.setGameOptions({'again': true}),
    );
    expect(notices.single, contains('End the current game'));
  });

  test("changing the game resets to the new game's defaults", () async {
    host.setGameOptions({'again': true});
    await until(host, () => host.lobby!.gameOptions['again'] == true);
    host.changeGame('tictactoe');
    await until(guest, () => guest.lobby!.gameId == 'tictactoe');
    expect(guest.lobby!.gameOptions, isEmpty);
    expect(server.displayState.rules, isEmpty);
  });
}
