// End-to-end LAN test with the real app on two devices.
//
// Run one side as host and the other as joiner at the same time, e.g.:
//   flutter test integration_test/lan_play_test.dart -d windows  --dart-define=ROLE=host
//   flutter test integration_test/lan_play_test.dart -d <android> --dart-define=ROLE=join
//
// The joiner finds the room through Scan (or set JOIN_IP=<host ip> to use
// manual entry). Both sides are driven through the UI: two rounds of Tic
// Tac Toe, then Color Clash to a winner, then the host closes the room.
//
// SCREEN=browser (with a client holding /display open) or SCREEN=host
// (host device is the screen; pair with GAMES=ttt) test Single game screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nico_in_the_box/main.dart';
import 'package:nico_shared/games/color_clash/color_clash_view.dart';
import 'package:nico_shared/games/game_views.dart';
import 'package:nico_shared/games/tictactoe/tictactoe_view.dart';
import 'package:nico_shared/net/protocol.dart';

const role = String.fromEnvironment('ROLE', defaultValue: 'host');
const joinIp = String.fromEnvironment('JOIN_IP');

/// `ttt` skips Color Clash (used when a person plays the other side).
const games = String.fromEnvironment('GAMES', defaultValue: 'all');

/// Host only: expect the other player to have joined from a browser.
const expectWebPlayer = bool.fromEnvironment('EXPECT_WEB_PLAYER');

/// Single game screen: `none`, `browser` (a screen connects to /display)
/// or `host` (the host's device is the screen and doesn't play).
const screen = String.fromEnvironment('SCREEN', defaultValue: 'none');

/// Players get the compact view whenever a shared screen is in use.
const expectCompact = screen != 'none';
const roomName = 'LAN Test';

/// Pumps frames in real time until [condition] holds.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .where((t) => t.isNotEmpty)
          .join(' | ');
      fail('Timed out waiting for ${reason ?? 'condition'}. On screen: $texts');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

bool present(Finder finder) => finder.evaluate().isNotEmpty;

Json? tttView() => present(find.byType(TicTacToeView))
    ? find
          .byType(TicTacToeView)
          .evaluate()
          .map((e) => (e.widget as TicTacToeView).ctx)
          .first
          .view
    : null;

bool _finished(Json v) => v['winner'] != null || v['draw'] == true;

int _marks(Json v) => (v['board']! as List<Object?>).whereType<String>().length;

/// Waits for a Tic Tac Toe game that is still running, then plays it via
/// taps until it is over. Returns the final view.
Future<Json> playTicTacToe(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () => tttView() != null && !_finished(tttView()!),
    timeout: const Duration(minutes: 2),
    reason: 'a running tic tac toe game',
  );
  final myId = _myTttId();
  expect(_tttCtx().compact, expectCompact, reason: 'compact view');
  var last = tttView()!;
  while (true) {
    // The host may leave the finished game before we see the final board,
    // so a vanished game view also counts as the end.
    await pumpUntil(
      tester,
      () {
        final v = tttView();
        return v == null || v['turn'] == myId || _finished(v);
      },
      timeout: const Duration(seconds: 60),
      reason: 'my turn or game end',
    );
    final view = tttView();
    if (view == null) return last;
    // A board with fewer marks means the host restarted before we saw the
    // end of this game; leave the new round to the next call.
    if (_marks(view) < _marks(last)) return last;
    last = view;
    if (_finished(view)) return view;
    final board = (view['board']! as List<Object?>);
    final cell = board.indexOf(null);
    final filled = board.whereType<String>().length;
    await tester.tap(find.byKey(ValueKey('ttt-cell-$cell')));
    await pumpUntil(
      tester,
      () =>
          (tttView()?['board'] as List<Object?>?)?.whereType<String>().length !=
          filled,
      reason: 'move to register',
    );
  }
}

ColorClashView? clashWidget() => present(find.byType(ColorClashView))
    ? find.byType(ColorClashView).evaluate().first.widget as ColorClashView
    : null;

/// Plays Color Clash through the UI until someone wins.
Future<void> playColorClash(WidgetTester tester) async {
  await pumpUntil(tester, () => clashWidget() != null, reason: 'color clash');
  expect(clashWidget()!.ctx.compact, expectCompact, reason: 'compact view');
  expect(present(find.byKey(const ValueKey('compact-status'))), expectCompact);
  var moves = 0;
  while (true) {
    await pumpUntil(
      tester,
      () {
        final w = clashWidget();
        if (w == null) return true;
        final v = w.ctx.view;
        return v['winner'] != null ||
            v['turn'] == w.ctx.myId ||
            (v['vulnerable'] != null && v['vulnerable'] != w.ctx.myId);
      },
      timeout: const Duration(seconds: 60),
      reason: 'clash turn',
    );
    final w = clashWidget();
    if (w == null) return;
    final view = w.ctx.view;
    if (view['winner'] != null) return;

    final before = view;
    final catchButton = find.textContaining('Catch ');
    if (present(catchButton)) {
      await tester.tap(catchButton);
    } else if (view['canCallLast'] == true) {
      await tester.tap(find.text('Last card!'));
    } else {
      final playable = (view['playable']! as List<Object?>).cast<int>();
      if (playable.isNotEmpty) {
        final cardFinder = find.byKey(ValueKey('hand-card-${playable.first}'));
        await tester.ensureVisible(cardFinder);
        await tester.pump();
        await tester.tap(cardFinder);
        await tester.pump(const Duration(milliseconds: 300));
        if (present(find.byKey(const ValueKey('pick-red')))) {
          await tester.tap(find.byKey(const ValueKey('pick-red')));
        }
      } else if (view['pendingDrawn'] != null) {
        await tester.tap(find.text('Pass'));
      } else {
        // Compact view has a Draw button instead of the draw pile.
        final drawButton = find.byKey(const ValueKey('draw-button'));
        await tester.tap(
          present(drawButton)
              ? drawButton
              : find.byKey(const ValueKey('draw-pile')),
        );
      }
    }
    moves++;
    await pumpUntil(
      tester,
      () => clashWidget()?.ctx.view != before,
      reason: 'clash move to register',
    );
    expect(moves, lessThan(2000), reason: 'game should finish');
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await pumpUntil(tester, () => present(finder), reason: '"$text"');
  await tester.tap(finder.last);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'host plays a full LAN session',
    (tester) async {
      await tester.pumpWidget(const NicoInTheBoxApp());
      await tapText(tester, 'Host a game');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextFormField).at(0), 'Host');
      await tester.enterText(find.byType(TextFormField).at(1), roomName);
      if (screen != 'none') {
        final toggle = find.byKey(const ValueKey('single-screen-switch'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pump(const Duration(milliseconds: 300));
        if (screen == 'host') await tapText(tester, 'This device');
      }
      await tapText(tester, 'Create room');

      await pumpUntil(
        tester,
        () => present(find.text('Players 2/2')),
        timeout: const Duration(minutes: 5),
        reason: 'a player to join',
      );
      if (expectWebPlayer) {
        expect(find.text('In a browser'), findsOneWidget);
      }
      if (screen == 'browser') {
        await pumpUntil(
          tester,
          () => present(find.text('Browser 1')),
          timeout: const Duration(minutes: 2),
          reason: 'a browser screen to connect',
        );
      }
      await tapText(tester, 'Start game');

      if (screen == 'host') {
        // This device shows the table; two guests play.
        for (var round = 1; round <= 2; round++) {
          await pumpUntil(
            tester,
            () =>
                present(find.byType(TicTacToeTable)) &&
                !present(find.text('Play again')),
            timeout: const Duration(minutes: 2),
            reason: 'round $round on the shared table',
          );
          expect(find.byType(TicTacToeView), findsNothing);
          await pumpUntil(
            tester,
            () => present(find.text('Play again')),
            timeout: const Duration(minutes: 3),
            reason: 'round $round to finish',
          );
          expect(find.textContaining('wins!'), findsWidgets);
          await tapText(tester, round == 1 ? 'Play again' : 'Back to lobby');
        }
        await pumpUntil(
          tester,
          () => present(find.text('Start game')),
          reason: 'back in the lobby',
        );
        await _closeRoomAsHost(tester);
        return;
      }

      final round1 = await playTicTacToe(tester);
      final myId = _myTttId();
      expect(_finished(round1), isTrue);
      await tapText(tester, 'Play Tic Tac Toe again');
      final round2 = await playTicTacToe(tester);
      expect(_finished(round2), isTrue);
      // Marks swap between rounds, so the opener alternates.
      expect(
        (round2['marks']! as Json)[myId],
        isNot((round1['marks']! as Json)[myId]),
      );
      if (games != 'ttt') {
        await tapText(tester, 'Back to lobby');

        await pumpUntil(
          tester,
          () => present(find.byIcon(Icons.swap_horiz)),
          reason: 'lobby',
        );
        await tester.tap(find.byIcon(Icons.swap_horiz));
        await tester.pump(const Duration(milliseconds: 500));
        await tapText(tester, 'Color Clash (2–4 players)');
        await pumpUntil(
          tester,
          () => present(find.text('Players 2/4')),
          reason: 'room resized to 4',
        );
        await tapText(tester, 'Start game');
        await playColorClash(tester);
        await pumpUntil(
          tester,
          () => present(find.text('Back to lobby')),
          reason: 'clash result',
        );
      }

      await _closeRoomAsHost(tester);
    },
    skip: role != 'host',
    timeout: const Timeout(Duration(minutes: 20)),
  );

  testWidgets(
    'joiner plays a full LAN session',
    (tester) async {
      await tester.pumpWidget(const NicoInTheBoxApp());
      await tapText(tester, 'Join a game');

      if (joinIp.isNotEmpty) {
        await tester.enterText(find.byType(TextField), joinIp);
        await tapText(tester, 'Join');
      } else {
        await pumpUntil(
          tester,
          () => present(find.text(roomName)),
          timeout: const Duration(minutes: 5),
          reason: 'room to appear in scan',
        );
        await tester.tap(find.text(roomName));
      }
      await pumpUntil(
        tester,
        () => present(find.byType(AlertDialog)),
        reason: 'nickname dialog',
      );
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Guest',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Join'),
        ),
      );
      await pumpUntil(
        tester,
        // The host may start the game before the lobby is ever drawn here.
        () =>
            present(find.text('Waiting for the host to start the game…')) ||
            tttView() != null ||
            clashWidget() != null,
        reason: 'lobby or game',
      );

      // Play whatever the host starts until the room is closed.
      var tttGames = 0;
      var clashGames = 0;
      while (true) {
        await pumpUntil(
          tester,
          () =>
              present(find.text('Host a game')) ||
              (tttView() != null && !_finished(tttView()!)) ||
              (clashWidget() != null &&
                  clashWidget()!.ctx.view['winner'] == null),
          timeout: const Duration(minutes: 3),
          reason: 'next game or room closed',
        );
        if (present(find.text('Host a game'))) break;
        if (tttView() != null) {
          await playTicTacToe(tester);
          tttGames++;
        } else {
          await playColorClash(tester);
          clashGames++;
          await pumpUntil(
            tester,
            () => clashWidget() == null,
            timeout: const Duration(minutes: 3),
            reason: 'host to close the room',
          );
        }
      }
      await pumpUntil(
        tester,
        () => present(find.text('The host closed the room.')),
        timeout: const Duration(seconds: 3),
        reason: 'the "host closed the room" message',
      );
      expect(tttGames, 2);
      expect(clashGames, games == 'ttt' ? 0 : 1);
    },
    skip: role != 'join',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<void> _closeRoomAsHost(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Host controls'));
  await tester.pump(const Duration(milliseconds: 500));
  await tapText(tester, 'Close room');
  await pumpUntil(
    tester,
    () => present(find.byType(AlertDialog)),
    reason: 'confirm dialog',
  );
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Close room'),
    ),
  );
  await pumpUntil(
    tester,
    () => present(find.text('Host a game')),
    reason: 'back home',
  );
}

TicTacToeView _tttW() =>
    find.byType(TicTacToeView).evaluate().first.widget as TicTacToeView;

GameViewContext _tttCtx() => _tttW().ctx;

String _myTttId() => find
    .byType(TicTacToeView)
    .evaluate()
    .map((e) => (e.widget as TicTacToeView).ctx.myId)
    .first;
