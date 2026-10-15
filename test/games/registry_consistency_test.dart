// Checks that every registered game has all the pieces the apps need.
// See docs/ADDING_A_GAME.md: if this fails after adding a game, a step from
// the checklist is missing.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/game_views.dart';
import 'package:nico_shared/games/registry.dart';
import 'package:nico_shared/net/protocol.dart';

List<PlayerInfo> _players(int count) => [
  for (var i = 1; i <= count; i++) PlayerInfo(id: 'p$i', nickname: 'Player $i'),
];

void main() {
  test('game ids are unique and URL/JS-safe', () {
    final ids = availableGames.map((g) => g.id).toList();
    expect(ids.toSet(), hasLength(ids.length), reason: 'duplicate game id');
    for (final id in ids) {
      expect(
        RegExp(r'^[a-z][a-z0-9]*$').hasMatch(id),
        isTrue,
        reason: '"$id": use lowercase letters and digits only',
      );
    }
  });

  for (final game in availableGames) {
    group(game.id, () {
      test('has a sensible player range and texts', () {
        expect(game.minPlayers, greaterThanOrEqualTo(1));
        expect(game.maxPlayers, greaterThanOrEqualTo(game.minPlayers));
        expect(game.name.trim(), isNotEmpty);
        expect(game.description.trim(), isNotEmpty);
      });

      test('has unique, valid option ids', () {
        final ids = game.options.map((o) => o.id).toList();
        expect(ids.toSet(), hasLength(ids.length), reason: 'duplicate id');
        for (final option in game.options) {
          expect(
            RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(option.id),
            isTrue,
            reason: '"${option.id}": start lowercase, letters and digits',
          );
          expect(option.label.trim(), isNotEmpty);
        }
      });

      test('has a player view and a shared-screen table', () {
        expect(gameViews, contains(game.id), reason: 'add it to gameViews');
        expect(gameTables, contains(game.id), reason: 'add it to gameTables');
      });

      test('has a browser shared-screen renderer, loaded by the page', () {
        final script = File('assets/display/games/${game.id}.js');
        expect(
          script.existsSync(),
          isTrue,
          reason: 'create assets/display/games/${game.id}.js',
        );
        expect(
          script.readAsStringSync(),
          contains("NicoDisplay.register('${game.id}'"),
          reason: 'the script must register the game id',
        );
        expect(
          File('assets/display/index.html').readAsStringSync(),
          contains('src="games/${game.id}.js"'),
          reason: 'add a <script> tag for it to assets/display/index.html',
        );
      });

      test('sessions work at both ends of the player range', () {
        for (final count in {game.minPlayers, game.maxPlayers}) {
          final players = _players(count);
          for (var round = 0; round < 3; round++) {
            final session = game.createSession(
              players,
              round,
              Random(round),
              game.defaultOptions,
            );
            expect(session.isOver, isFalse, reason: 'starts finished');
            expect(session.result, isNull);
            // Everything sent over the network must be plain JSON.
            expect(() => jsonEncode(session.tableView()), returnsNormally);
            for (final p in players) {
              expect(() => jsonEncode(session.viewFor(p.id)), returnsNormally);
            }
          }
        }
      });
    });
  }
}
