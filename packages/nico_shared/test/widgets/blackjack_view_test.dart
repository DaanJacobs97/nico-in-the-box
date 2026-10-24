import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/blackjack/blackjack_cards.dart';
import 'package:nico_shared/games/blackjack/blackjack_chips.dart';
import 'package:nico_shared/games/blackjack/blackjack_game.dart';
import 'package:nico_shared/games/blackjack/blackjack_table.dart';
import 'package:nico_shared/games/blackjack/blackjack_view.dart';
import 'package:nico_shared/games/game_views.dart';
import 'package:nico_shared/net/protocol.dart';
import 'package:nico_shared/screens/shared_screen_view.dart';

const ann = PlayerInfo(id: 'a', nickname: 'Ann');
const bob = PlayerInfo(id: 'b', nickname: 'Bob');

const lobby = LobbyState(
  roomName: 'Party',
  gameId: 'blackjack',
  players: [ann, bob],
  minPlayers: 2,
  maxPlayers: 8,
  hostId: 'a',
  hostName: 'Ann',
  phase: RoomPhase.playing,
);

PlayingCard c(int rank, [Suit suit = Suit.spades]) => PlayingCard(rank, suit);

/// Ann then Bob; cards dealt Ann, Bob, dealer, Ann, Bob, dealer, then hits.
BlackjackSession game(List<PlayingCard> cards, {bool chipsMode = false}) =>
    BlackjackSession.custom(
      const [ann, bob],
      deck: [...cards, for (var i = 0; i < 30; i++) c(2, Suit.clubs)],
      chipsMode: chipsMode,
    );

void dealAll(BlackjackSession s) {
  for (final id in ['a', 'b']) {
    s.applyAction(
      id,
      s.chipsMode ? {'type': 'bet', 'amount': 100} : {'type': 'deal'},
    );
  }
}

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

Widget view(
  BlackjackSession s, {
  required bool compact,
  String me = 'a',
  List<Json>? sent,
}) => BlackjackView(
  ctx: GameViewContext(
    view: s.viewFor(me),
    myId: me,
    lobby: lobby,
    sendAction: (action) => sent?.add(action),
    compact: compact,
  ),
);

void main() {
  testWidgets('between hands: Deal (wins mode)', (tester) async {
    final sent = <Json>[];
    await pumpAt(
      tester,
      const Size(400, 800),
      view(game([]), compact: false, sent: sent),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Tap Deal for the next hand'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.byKey(const ValueKey('bj-bet-10')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('bj-deal')));
    expect(sent, [
      {'type': 'deal'},
    ]);
  });

  testWidgets('between hands: the bets you can afford (chips mode)', (
    tester,
  ) async {
    final sent = <Json>[];
    await pumpAt(
      tester,
      const Size(400, 800),
      view(game([], chipsMode: true), compact: false, sent: sent),
    );
    expect(find.text('Place your bet'), findsOneWidget);
    for (final amount in BlackjackView.betAmounts) {
      expect(find.byKey(ValueKey('bj-bet-$amount')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('bj-bet-100')));
    expect(sent, [
      {'type': 'bet', 'amount': 100},
    ]);
  });

  testWidgets('waiting for the others after betting', (tester) async {
    final s = game([])..applyAction('a', {'type': 'deal'});
    await pumpAt(tester, const Size(400, 800), view(s, compact: false));
    expect(find.text('Waiting for Bob'), findsOneWidget);
    expect(find.byKey(const ValueKey('bj-deal')), findsNothing);
  });

  testWidgets('on your turn: hit, stand, double, split', (tester) async {
    final s = game([
      c(8),
      c(9),
      c(10),
      c(8, Suit.hearts),
      c(9),
      c(7),
    ], chipsMode: true);
    dealAll(s);
    final sent = <Json>[];
    await pumpAt(
      tester,
      const Size(400, 900),
      view(s, compact: false, sent: sent),
    );
    expect(find.text('Your turn'), findsOneWidget);
    for (final type in ['hit', 'stand', 'double', 'split']) {
      expect(
        find.byKey(ValueKey('bj-action-$type')),
        findsOneWidget,
        reason: type,
      );
    }
    await tester.tap(find.byKey(const ValueKey('bj-action-hit')));
    expect(sent, [
      {'type': 'hit'},
    ]);
    // The dealer's hole card is face down; Bob's view has no buttons.
    expect(find.byKey(const ValueKey('bj-card-back')), findsOneWidget);
    await pumpAt(
      tester,
      const Size(400, 900),
      view(s, compact: false, me: 'b'),
    );
    expect(find.text("Ann's turn"), findsOneWidget);
    expect(find.byKey(const ValueKey('bj-action-hit')), findsNothing);
  });

  testWidgets('after a split the status says which hand', (tester) async {
    final s =
        game([c(8), c(9), c(10), c(8, Suit.hearts), c(9), c(7), c(3), c(10)])
          ..applyAction('a', {'type': 'deal'})
          ..applyAction('b', {'type': 'deal'})
          ..applyAction('a', {'type': 'split'});
    await pumpAt(tester, const Size(400, 900), view(s, compact: false));
    expect(find.text('Your turn (hand 1)'), findsOneWidget);
  });

  testWidgets('compact: the dealer and your own seat only', (tester) async {
    final s = game([c(10), c(9), c(5), c(7), c(8), c(6)]);
    dealAll(s);
    await pumpAt(tester, const Size(400, 800), view(s, compact: true));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('bj-dealer')), findsOneWidget);
    expect(find.byKey(const ValueKey('bj-my-seat')), findsOneWidget);
    // Your seat sits in the middle of the space below the dealer.
    final top = tester.getBottomLeft(find.byKey(const ValueKey('bj-dealer')));
    final bottom = tester.getTopLeft(find.byKey(const ValueKey('bj-status')));
    expect(
      tester.getCenter(find.byKey(const ValueKey('bj-my-seat'))).dy,
      moreOrLessEquals((top.dy + bottom.dy) / 2, epsilon: 13),
    );
    expect(find.text('Bob'), findsNothing);
    expect(find.byKey(const ValueKey('bj-action-stand')), findsOneWidget);
  });

  testWidgets('results show on each hand once settled', (tester) async {
    final s = game([c(10), c(10), c(1), c(8), c(9), c(6)]);
    dealAll(s);
    s
      ..applyAction('a', {'type': 'stand'})
      ..applyAction('b', {'type': 'stand'});
    await pumpAt(tester, const Size(400, 900), view(s, compact: false));
    expect(find.text('Win'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('bj-card-back')), findsNothing);
  });

  testWidgets('shared screen shows the table at TV size', (tester) async {
    final s = game([c(10), c(9), c(5), c(7), c(8), c(6)]);
    dealAll(s);
    await pumpAt(
      tester,
      const Size(1920, 1080),
      SharedScreenView(
        state: DisplayState(
          lobby: lobby,
          gameId: 'blackjack',
          table: s.tableView(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byKey(const ValueKey('bj-card-back')), findsOneWidget);
    expect(find.textContaining('First to 5 wins'), findsOneWidget);
    // The seats sit in the middle of the space below the dealer.
    final dealerBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('bj-dealer')))
        .dy;
    final areaBottom = tester.getBottomLeft(find.byType(BlackjackTableArea)).dy;
    final seats = tester.getRect(find.byKey(const ValueKey('bj-seats')));
    final above = seats.top - dealerBottom;
    final below = areaBottom - seats.bottom;
    expect(above, greaterThan(100), reason: 'not stuck under the dealer');
    expect(above - below, moreOrLessEquals(0, epsilon: 60));
  });

  testWidgets('a full table of eight fits a phone and a TV', (tester) async {
    final players = [
      for (var i = 1; i <= 8; i++) PlayerInfo(id: 'p$i', nickname: 'Player $i'),
    ];
    final s = BlackjackSession.custom(
      players,
      deck: [for (var i = 0; i < 60; i++) c(1 + i % 13, Suit.values[i % 4])],
      chipsMode: true,
    );
    for (final p in players) {
      s.applyAction(p.id, {'type': 'bet', 'amount': 50});
    }
    final eight = LobbyState(
      roomName: 'Party',
      gameId: 'blackjack',
      players: players,
      minPlayers: 2,
      maxPlayers: 8,
      hostId: 'p1',
      phase: RoomPhase.playing,
    );
    for (final size in [const Size(390, 844), const Size(1920, 1080)]) {
      await pumpAt(
        tester,
        size,
        SharedScreenView(
          state: DisplayState(
            lobby: eight,
            gameId: 'blackjack',
            table: s.tableView(),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  test('bets break into the fewest chips, biggest first', () {
    expect(chipBreakdown(370), {100: 3, 50: 1, 10: 2});
    expect(chipBreakdown(1150), {500: 2, 100: 1, 50: 1});
    expect(chipBreakdown(15), {10: 1, 5: 1});
    expect(chipBreakdown(0), isEmpty);
  });

  testWidgets('bets show as chips with "Bet: x chips"', (tester) async {
    // Ann doubles (5 + 6 + 10); Bob has bet but not played yet.
    final s = game([
      c(5),
      c(9),
      c(10),
      c(6),
      c(8),
      c(7),
      c(10),
    ], chipsMode: true);
    dealAll(s);
    s.applyAction('a', {'type': 'double'});
    await pumpAt(tester, const Size(500, 900), view(s, compact: false));
    expect(tester.takeException(), isNull);
    expect(find.text('Bet: 200 chips (doubled)'), findsOneWidget);
    expect(find.text('Bet: 100 chips'), findsOneWidget);
    expect(find.byKey(const ValueKey('bj-chips-200')), findsOneWidget);
    expect(find.byType(CasinoChip), findsWidgets);
  });

  testWidgets('a bet placed for the next hand shows before the deal', (
    tester,
  ) async {
    final s = game([], chipsMode: true)
      ..applyAction('a', {'type': 'bet', 'amount': 250});
    await pumpAt(tester, const Size(500, 900), view(s, compact: false));
    expect(find.text('Bet: 250 chips'), findsOneWidget);
    expect(find.text('750 chips · ready'), findsOneWidget);
  });

  testWidgets('the table sits on felt, in light mode too', (tester) async {
    final s = game([c(10), c(9), c(5), c(7), c(8), c(6)]);
    dealAll(s);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final compact in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: Scaffold(body: view(s, compact: compact)),
        ),
      );
      expect(find.byKey(const ValueKey('bj-felt')), findsOneWidget);
      expect(
        find.text('BLACKJACK PAYS 3 TO 2 · DEALER STANDS ON 17'),
        findsOneWidget,
      );
      // Text on the felt is light, whatever the app theme.
      final style = DefaultTextStyle.of(
        tester.element(find.byKey(const ValueKey('bj-dealer'))),
      ).style;
      expect(style.color!.computeLuminance(), greaterThan(0.5));
    }
  });
}
