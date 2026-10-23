import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_in_the_box/net/game_server.dart';
import 'package:nico_shared/games/game_session.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';

/// Every player sees only their own view, so a resume can prove it got the
/// right one back.
class _SecretSession implements GameSession {
  int moves = 0;

  @override
  void applyAction(String playerId, Json action) => moves++;
  @override
  Json viewFor(String playerId) => {'secret': 'for $playerId', 'moves': moves};
  @override
  Json tableView() => {'moves': moves};
  @override
  bool get isOver => false;
  @override
  Json? get result => null;
}

final _secretGame = GameDefinition(
  id: 'secret',
  name: 'Secret',
  description: 'Each player sees only their own view.',
  minPlayers: 2,
  maxPlayers: 3,
  category: GameCategory.board,
  createSession: (_, _, _, _) => _SecretSession(),
);

/// A bare WebSocket player, so a test decides exactly when it drops.
class _RawPlayer {
  _RawPlayer._(this.socket) {
    socket.listen(
      (raw) {
        messages.add(decodeMessage(raw));
        _changed.add(null);
      },
      onDone: () {
        closed = true;
        _changed.add(null);
      },
    );
  }

  static Future<_RawPlayer> open(int port) async => _RawPlayer._(
    await WebSocket.connect('ws://127.0.0.1:$port$kWebSocketPath'),
  );

  final WebSocket socket;
  final messages = <Json>[];
  bool closed = false;
  final _changed = StreamController<void>.broadcast();

  void send(String type, [Json body = const {}]) =>
      socket.add(encodeMessage(type, body));

  void hello(String nickname) =>
      send(Msg.hello, {'nickname': nickname, 'protocol': kProtocolVersion});

  void resume(String token) =>
      send(Msg.hello, {'resume': token, 'protocol': kProtocolVersion});

  Future<void> _until(bool Function() condition) async {
    if (condition()) return;
    await _changed.stream
        .firstWhere((_) => condition())
        .timeout(const Duration(seconds: 10));
  }

  /// The first message of [type] that matches [where].
  Future<Json> next(String type, [bool Function(Json)? where]) async {
    Json? find() => messages
        .where((m) => m['type'] == type && (where?.call(m) ?? true))
        .firstOrNull;
    await _until(() => find() != null);
    return find()!;
  }

  Future<void> untilClosed() => _until(() => closed);
}

/// Waits until [condition] holds after a change notification from [client].
Future<void> until(GameClient client, bool Function() condition) {
  if (condition()) return Future.value();
  final done = Completer<void>();
  void check() {
    if (!done.isCompleted && condition()) done.complete();
  }

  client.addListener(check);
  return done.future
      .timeout(const Duration(seconds: 10))
      .whenComplete(() => client.removeListener(check));
}

void main() {
  late GameServer server;
  late GameClient host;
  late List<String> hostNotices;
  final raws = <_RawPlayer>[];

  Future<void> startRoom({Duration grace = const Duration(seconds: 10)}) async {
    server = GameServer(
      roomName: 'Test room',
      game: _secretGame,
      random: Random(1),
      reconnectGrace: grace,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    host = await GameClient.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      nickname: 'Nico',
      hostToken: server.hostToken,
    );
    hostNotices = [];
    host.notices.listen(hostNotices.add);
  }

  Future<_RawPlayer> raw() async {
    final player = await _RawPlayer.open(server.port);
    raws.add(player);
    return player;
  }

  /// Joins Ann and returns her connection and welcome.
  Future<(_RawPlayer, Json)> joinAnn() async {
    final ann = await raw();
    ann.hello('Ann');
    final welcome = await ann.next(Msg.welcome);
    await until(host, () => host.lobby?.players.length == 2);
    return (ann, welcome);
  }

  /// Waits until the host has been shown a notice matching [matcher].
  Future<void> heard(Object matcher) async {
    final m = wrapMatcher(matcher);
    for (var i = 0; i < 500; i++) {
      if (hostNotices.any((n) => m.matches(n, {}))) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('No notice matching $matcher; got $hostNotices');
  }

  bool annAway() =>
      host.lobby!.players.any((p) => p.nickname == 'Ann' && p.away);

  tearDown(() async {
    for (final r in raws) {
      await r.socket.close();
    }
    raws.clear();
    await host.leave();
    await server.close();
  });

  test('players get a resume token; the host does not', () async {
    await startRoom();
    expect(host.isHost, isTrue);
    final (_, welcome) = await joinAnn();
    expect(welcome['resumeToken'], isA<String>());
    expect(welcome['graceMs'], 10000);
  });

  test(
    'a dropped player keeps their seat and gets their own view back',
    () async {
      await startRoom();
      final (ann, welcome) = await joinAnn();
      host.startGame();
      await ann.next(Msg.gameState);

      await ann.socket.close(); // No leave message: a drop.
      await until(host, annAway);
      expect(host.lobby!.phase, RoomPhase.playing);
      await heard(contains('Ann lost connection'));

      final back = await raw();
      back.resume(welcome['resumeToken']! as String);
      final again = await back.next(Msg.welcome);
      expect(again['playerId'], welcome['playerId']);
      expect(again['isHost'], isFalse);
      final state = await back.next(Msg.gameState);
      expect(state['view'], {
        'secret': 'for ${welcome['playerId']}',
        'moves': 0,
      });
      await until(host, () => !annAway());
      await heard('Ann is back.');

      // The game goes on.
      back.send(Msg.action, {
        'action': {'type': 'move'},
      });
      await until(host, () => host.gameView?['moves'] == 1);
    },
  );

  test('after the grace period the seat is freed and the game ends', () async {
    await startRoom(grace: const Duration(milliseconds: 300));
    final (ann, welcome) = await joinAnn();
    host.startGame();
    await ann.next(Msg.gameState);

    await ann.socket.close();
    await until(host, () => host.lobby!.players.length == 1);
    expect(host.lobby!.phase, RoomPhase.lobby);
    await heard("Ann didn't come back. The game was ended.");

    final tooLate = await raw();
    tooLate.resume(welcome['resumeToken']! as String);
    final error = await tooLate.next(Msg.error);
    expect(error['code'], ErrorCode.resumeFailed);
    await tooLate.untilClosed();
  });

  test('a wrong token is rejected', () async {
    await startRoom();
    await joinAnn();
    final stranger = await raw();
    stranger.resume('not-a-token');
    final error = await stranger.next(Msg.error);
    expect(error['code'], ErrorCode.resumeFailed);
    await stranger.untilClosed();
    expect(host.lobby!.players, hasLength(2));
  });

  test('a kicked player cannot come back', () async {
    await startRoom();
    final (ann, welcome) = await joinAnn();
    host.kick(welcome['playerId']! as String);
    await ann.next(Msg.kicked);
    await until(host, () => host.lobby!.players.length == 1);

    final back = await raw();
    back.resume(welcome['resumeToken']! as String);
    expect((await back.next(Msg.error))['code'], ErrorCode.resumeFailed);
  });

  test('leaving on purpose frees the seat at once', () async {
    await startRoom();
    final (ann, welcome) = await joinAnn();
    ann.send(Msg.leave);
    await until(host, () => host.lobby!.players.length == 1);
    await heard('Ann left.');

    final back = await raw();
    back.resume(welcome['resumeToken']! as String);
    expect((await back.next(Msg.error))['code'], ErrorCode.resumeFailed);
  });

  test('a resume replaces a connection that still looks open', () async {
    await startRoom();
    final (ann, welcome) = await joinAnn();
    final back = await raw();
    back.resume(welcome['resumeToken']! as String);
    expect((await back.next(Msg.welcome))['playerId'], welcome['playerId']);
    await ann.untilClosed();

    // Closing the old connection does not count as a drop.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(host.lobby!.players, hasLength(2));
    expect(annAway(), isFalse);
    expect(hostNotices, isEmpty);
  });

  test(
    'the nickname stays taken and a full room still takes the player back',
    () async {
      await startRoom();
      final (ann, welcome) = await joinAnn();
      await ann.socket.close();
      await until(host, annAway);

      final copycat = await raw();
      copycat.hello('ann');
      expect((await copycat.next(Msg.error))['code'], ErrorCode.nameTaken);

      // Bob takes the last free seat; Ann's is still hers.
      final bob = await raw();
      bob.hello('Bob');
      await bob.next(Msg.welcome);
      expect(server.acceptingPlayers, isFalse);
      final back = await raw();
      back.resume(welcome['resumeToken']! as String);
      expect((await back.next(Msg.welcome))['playerId'], welcome['playerId']);
      await until(host, () => !annAway());
    },
  );

  test('a GameClient reconnects on its own after a drop', () async {
    await startRoom();
    final guest = await GameClient.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      nickname: 'Ann',
      retryInterval: const Duration(milliseconds: 50),
    );
    addTearDown(guest.leave);
    host.startGame();
    await until(guest, () => guest.gameView != null);

    var sawReconnecting = false;
    guest.addListener(() => sawReconnecting |= guest.reconnecting);
    await server.dropConnectionOf(guest.playerId);
    await until(guest, () => sawReconnecting && !guest.reconnecting);

    expect(guest.isConnected, isTrue);
    expect(guest.gameView, {'secret': 'for ${guest.playerId}', 'moves': 0});
    guest.sendAction({'type': 'move'});
    await until(guest, () => guest.gameView!['moves'] == 1);
  });
}
