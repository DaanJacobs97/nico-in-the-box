import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/lobby_view.dart';
import 'package:nico_shared/screens/session_screen.dart';

/// A scripted room: welcomes the first hello, then drops it. Later hellos
/// (resumes) are welcomed after [resumeDelay], refused with [resumeError], or
/// get nothing at all once [stop] is called. Every welcome is followed by a
/// lobby where Bob is away.
class _FakeRoom {
  late HttpServer _http;
  int hellos = 0;
  final resumes = <Json>[];
  final received = <Json>[];

  /// What a resume gets back; null means a fresh welcome.
  String? resumeError;
  Duration resumeDelay = Duration.zero;

  Future<void> start({required int graceMs}) async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((raw) async {
        final msg = decodeMessage(raw);
        received.add(msg);
        if (msg['type'] != Msg.hello) return;
        hellos++;
        if (msg['resume'] != null) resumes.add(msg);
        if (msg['resume'] != null) await Future<void>.delayed(resumeDelay);
        if (msg['resume'] != null && resumeError != null) {
          socket.add(
            encodeMessage(Msg.error, {'code': resumeError, 'msg': 'No.'}),
          );
          await socket.close();
          return;
        }
        socket.add(
          encodeMessage(Msg.welcome, {
            'playerId': 'p2',
            'isHost': false,
            'resumeToken': 'secret',
            'graceMs': graceMs,
          }),
        );
        socket.add(encodeMessage(Msg.lobby, _lobby.toJson()));
        // The first connection drops right after the welcome.
        if (hellos == 1) {
          Timer(const Duration(milliseconds: 50), socket.close);
        }
      });
    });
  }

  int get port => _http.port;

  /// The room becomes unreachable.
  Future<void> stop() => _http.close(force: true);
}

const _lobby = LobbyState(
  roomName: 'Fake room',
  gameId: 'colorclash',
  players: [
    PlayerInfo(id: 'p1', nickname: 'Nico'),
    PlayerInfo(id: 'p2', nickname: 'Ann'),
    PlayerInfo(id: 'p3', nickname: 'Bob', away: true),
  ],
  minPlayers: 2,
  maxPlayers: 4,
  hostId: 'p1',
  phase: RoomPhase.lobby,
);

Future<GameClient> _join(_FakeRoom room) => GameClient.connect(
  host: InternetAddress.loopbackIPv4.address,
  port: room.port,
  nickname: 'Ann',
  retryInterval: const Duration(milliseconds: 50),
);

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
  test('a resume sends the token from the welcome', () async {
    final room = _FakeRoom();
    await room.start(graceMs: 5000);
    final client = await _join(room);
    await until(client, () => room.resumes.isNotEmpty && !client.reconnecting);
    expect(room.resumes.single['resume'], 'secret');
    expect(client.isConnected, isTrue);
    await client.leave();
    await room.stop();
  });

  test('a refused resume gives up with connectionLost', () async {
    final room = _FakeRoom()..resumeError = ErrorCode.resumeFailed;
    await room.start(graceMs: 5000);
    final client = await _join(room);
    await until(client, () => client.reconnecting);
    await until(client, () => client.disconnectReason != null);
    expect(client.disconnectReason, DisconnectReason.connectionLost);
    expect(client.reconnecting, isFalse);
    expect(room.resumes, hasLength(1));
    await room.stop();
  });

  test('an unreachable room gives up after the grace period', () async {
    final room = _FakeRoom();
    await room.start(graceMs: 300);
    final client = await _join(room);
    await room.stop();
    final watch = Stopwatch()..start();
    await until(client, () => client.disconnectReason != null);
    expect(client.disconnectReason, DisconnectReason.connectionLost);
    expect(
      watch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 200)),
    );
  });

  test('leaving while reconnecting stops trying', () async {
    final room = _FakeRoom();
    await room.start(graceMs: 5000);
    final client = await _join(room);
    await room.stop();
    await until(client, () => client.reconnecting);
    await client.leave();
    expect(client.reconnecting, isFalse);
    expect(client.disconnectReason, DisconnectReason.left);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(client.disconnectReason, DisconnectReason.left);
  });

  test('actions are dropped while reconnecting', () async {
    final room = _FakeRoom();
    await room.start(graceMs: 5000);
    final client = await _join(room);
    await room.stop();
    await until(client, () => client.reconnecting);
    client.sendAction({'type': 'move'});
    expect(room.received.where((m) => m['type'] == Msg.action), isEmpty);
    await client.leave();
  });

  group('SessionScreen', () {
    /// Opens the room screen on top of a home page, as the apps do.
    Future<GameClient> openSession(WidgetTester tester, _FakeRoom room) async {
      final client = (await tester.runAsync(() => _join(room)))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SessionScreen(client: client),
                  ),
                ),
                child: const Text('Home'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Home'));
      // Spinners never settle, so pump through the page transition.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return client;
    }

    const banner = 'Connection lost. Reconnecting…';
    bool roomBlocked(WidgetTester tester) => tester
        .widget<IgnorePointer>(
          find
              .ancestor(
                of: find.byType(LobbyView),
                matching: find.byType(IgnorePointer),
              )
              .first,
        )
        .ignoring;

    testWidgets('a lost connection shows the banner; Leave goes home', (
      tester,
    ) async {
      final room = _FakeRoom();
      await tester.runAsync(() => room.start(graceMs: 5000));
      final client = await openSession(tester, room);
      await tester.runAsync(() async {
        await room.stop();
        await until(client, () => client.reconnecting);
      });
      await tester.pump();
      expect(find.text(banner), findsOneWidget);
      expect(roomBlocked(tester), isTrue);

      await tester.tap(find.text('Leave'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(client.disconnectReason, DisconnectReason.left);
    });

    testWidgets('the banner goes away once the seat is back', (tester) async {
      final room = _FakeRoom()..resumeDelay = const Duration(milliseconds: 300);
      await tester.runAsync(() => room.start(graceMs: 5000));
      final client = await openSession(tester, room);
      await tester.runAsync(() => until(client, () => client.reconnecting));
      await tester.pump();
      expect(find.text(banner), findsOneWidget);

      await tester.runAsync(() => until(client, () => !client.reconnecting));
      await tester.pump();
      expect(find.text(banner), findsNothing);
      expect(roomBlocked(tester), isFalse);
      await tester.runAsync(() async {
        await client.leave();
        await room.stop();
      });
    });

    testWidgets('away players are marked in the lobby', (tester) async {
      final room = _FakeRoom()..resumeDelay = const Duration(milliseconds: 100);
      await tester.runAsync(() => room.start(graceMs: 5000));
      final client = await openSession(tester, room);
      await tester.runAsync(() => until(client, () => client.lobby != null));
      await tester.pump();
      // Bob is away; Nico and Ann (you) are not.
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      await tester.runAsync(() async {
        await client.leave();
        await room.stop();
      });
    });
  });
}
