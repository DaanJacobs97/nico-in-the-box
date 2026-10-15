// A scripted player for LAN testing: joins a room over the real protocol and
// plays whatever game is running (Tic Tac Toe, Color Clash or Sea Siege)
// until the room closes. Handy as the "other player" when only one device
// is free.
//
//   flutter test tool/bot/lan_bot_test.dart --dart-define=HOST=192.168.0.156
//
// Options (--dart-define): HOST (required), PORT (47800), NAME (Bot),
// MOVE_DELAY_MS (0; slow it down to watch a shared screen).
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/color_clash/clash_card.dart';
import 'package:nico_shared/net/game_client.dart';
import 'package:nico_shared/net/protocol.dart';

const host = String.fromEnvironment('HOST');
const port = int.fromEnvironment('PORT', defaultValue: kGamePort);
const name = String.fromEnvironment('NAME', defaultValue: 'Bot');
const moveDelay = Duration(milliseconds: int.fromEnvironment('MOVE_DELAY_MS'));

void log(String line) => stdout.writeln(
  '[bot ${DateTime.now().toIso8601String().substring(11, 19)}] $line',
);

void main() {
  test('bot plays until the room closes', () async {
    expect(host, isNotEmpty, reason: 'pass --dart-define=HOST=<host ip>');

    // The room may not exist yet: keep trying for a few minutes.
    GameClient? client;
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (client == null) {
      try {
        client = await GameClient.connect(
          host: host,
          port: port,
          nickname: name,
        );
      } on JoinException catch (e) {
        if (DateTime.now().isAfter(deadline)) rethrow;
        if (e.code != JoinException.unreachable) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    final me = client;
    log('joined as ${me.playerId}');
    me.notices.listen((n) => log('notice: $n'));

    final results = <String>[];
    bool? lastShared;
    String? lastGame;
    Json? lastActedOn;
    var acting = false;
    var pending = false;

    // Acts on the newest view once per update. If an update arrives while
    // waiting out MOVE_DELAY_MS, the stale move is dropped and the newest
    // view is considered instead.
    Future<void> act() async {
      if (acting) {
        pending = true;
        return;
      }
      acting = true;
      try {
        while (true) {
          pending = false;
          final view = me.gameView;
          if (view == null || identical(view, lastActedOn)) break;
          final action = switch (me.gameId) {
            'tictactoe' => _ticTacToeMove(view, me.playerId),
            'colorclash' => _colorClashMove(view, me.playerId),
            'seasiege' => _seaSiegeMove(view, me.playerId),
            _ => null,
          };
          if (action == null) {
            lastActedOn = view;
            break;
          }
          await Future<void>.delayed(moveDelay);
          if (!identical(me.gameView, view)) continue;
          lastActedOn = view;
          me.sendAction(action);
          break;
        }
      } finally {
        acting = false;
      }
      if (pending) unawaited(act());
    }

    me.addListener(() {
      final shared = me.lobby?.sharedScreenActive;
      if (shared != null && shared != lastShared) {
        lastShared = shared;
        log('shared screen active: $shared');
      }
      final game = me.gameView == null ? null : me.gameId;
      if (game != lastGame) {
        lastGame = game;
        if (game != null) log('game started ($game)');
      }
      final result = me.gameResult;
      if (result != null &&
          (results.isEmpty || results.last != '${me.gameId}:$result')) {
        results.add('${me.gameId}:$result');
        log('game over (${me.gameId}): ${result['summary']}');
      }
      unawaited(act());
    });

    final done = Completer<void>();
    me.addListener(() {
      if (me.disconnectReason != null && !done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(minutes: 20));
    log(
      'left: ${me.disconnectReason!.name}, games finished: ${results.length}',
    );
  }, timeout: const Timeout(Duration(minutes: 25)));
}

Json? _ticTacToeMove(Json view, String me) {
  if (view['turn'] != me) return null;
  final board = view['board']! as List<Object?>;
  return {'type': 'place', 'cell': board.indexOf(null)};
}

Json? _colorClashMove(Json view, String me) {
  if (view['winner'] != null) return null;
  final vulnerable = view['vulnerable'];
  if (vulnerable != null && vulnerable != me) return {'type': 'catch'};
  if (view['turn'] != me) {
    return view['canCallLast'] == true ? {'type': 'callLast'} : null;
  }
  if (view['canCallLast'] == true) return {'type': 'callLast'};
  final playable = (view['playable']! as List<Object?>).cast<int>();
  if (playable.isNotEmpty) {
    return {
      'type': 'play',
      'cardId': playable.first,
      'color': playableColors.first.name,
    };
  }
  if (view['pendingDrawn'] != null) return {'type': 'pass'};
  return {'type': 'draw'};
}

final _random = Random();

/// Readies the fleet it was dealt, then fires at random untried squares.
Json? _seaSiegeMove(Json view, String me) {
  if (view['phase'] == 'placing') {
    return (view['ready']! as Json)[me] == true ? null : {'type': 'ready'};
  }
  if (view['turn'] != me) return null;
  final boards = view['boards']! as Json;
  final target = boards.keys.firstWhere((id) => id != me);
  final board = boards[target]! as Json;
  final tried = {
    ...board['hits']! as List<Object?>,
    ...board['misses']! as List<Object?>,
  };
  final open = [
    for (var cell = 0; cell < 100; cell++)
      if (!tried.contains(cell)) cell,
  ];
  return {
    'type': 'fire',
    'target': target,
    'cell': open[_random.nextInt(open.length)],
  };
}
