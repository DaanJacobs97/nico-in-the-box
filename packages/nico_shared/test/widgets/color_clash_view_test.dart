import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nico_shared/games/color_clash/clash_card.dart';
import 'package:nico_shared/games/color_clash/clash_hand.dart';
import 'package:nico_shared/games/color_clash/color_clash_game.dart';
import 'package:nico_shared/games/color_clash/color_clash_table.dart';
import 'package:nico_shared/games/color_clash/color_clash_view.dart';
import 'package:nico_shared/games/game_views.dart';
import 'package:nico_shared/net/protocol.dart';

const ann = PlayerInfo(id: 'a', nickname: 'Ann');
const bob = PlayerInfo(id: 'b', nickname: 'Bob');

var _nextId = 1000;
ClashCard card(CardColor color, CardKind kind, [int? value]) =>
    ClashCard(id: _nextId++, color: color, kind: kind, value: value);
ClashCard num(CardColor color, int value) =>
    card(color, CardKind.number, value);

LobbyState lobby() => LobbyState(
  roomName: 'Room',
  hostId: 'a',
  gameId: 'colorclash',
  minPlayers: 2,
  maxPlayers: 4,
  players: const [ann, bob],
  phase: RoomPhase.playing,
);

/// Ann to move on a red 5, holding [hand].
ColorClashSession session(List<ClashCard> hand, {bool stacking = false}) =>
    ColorClashSession.custom(
      const [ann, bob],
      hands: {
        'a': hand,
        'b': [num(CardColor.blue, 1), card(CardColor.blue, CardKind.drawTwo)],
      },
      drawPile: [for (var i = 0; i < 20; i++) num(CardColor.green, i % 10)],
      discard: [num(CardColor.red, 5)],
      stacking: stacking,
    );

Future<void> pumpView(
  WidgetTester tester,
  Json view, {
  required List<Json> sent,
  bool compact = true,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ColorClashView(
          ctx: GameViewContext(
            view: view,
            myId: 'a',
            lobby: lobby(),
            sendAction: sent.add,
            compact: compact,
          ),
        ),
      ),
    ),
  );
  expect(tester.takeException(), isNull);
}

Finder handCard(ClashCard c) => find.byKey(ValueKey('hand-card-${c.id}'));

Future<void> swipeUp(WidgetTester tester, ClashCard c, double distance) async {
  final gesture = await tester.startGesture(tester.getCenter(handCard(c)));
  for (var i = 1; i <= 10; i++) {
    await gesture.moveBy(Offset(0, -distance / 10));
    await tester.pump(const Duration(milliseconds: 40));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('wild card art', () {
    Color squareColor(WidgetTester tester, String color, Finder within) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: within, matching: find.byKey(ValueKey(color))),
      );
      return (box.decoration as BoxDecoration).color!;
    }

    testWidgets('wilds are a grid of the four colors; +4 says so', (
      tester,
    ) async {
      final wild = card(CardColor.wild, CardKind.wild);
      final plus4 = card(CardColor.wild, CardKind.wildDrawFour);
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              ClashCardFace(key: const Key('w'), card: wild, width: 90),
              ClashCardFace(key: const Key('w4'), card: plus4, width: 90),
            ],
          ),
        ),
      );
      for (final key in ['w', 'w4']) {
        final face = find.byKey(Key(key));
        for (final color in playableColors) {
          expect(
            squareColor(tester, 'wild-${color.name}', face),
            colorOf(color),
          );
        }
      }
      expect(
        find.descendant(
          of: find.byKey(const Key('w')),
          matching: find.text('W'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('w4')),
          matching: find.text('+4'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('on the pile, only the chosen color stays bright', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ClashCardFace(
              card: card(CardColor.wild, CardKind.wild),
              width: 90,
              activeColor: CardColor.green,
            ),
          ),
        ),
      );
      final all = find.byType(ClashCardFace);
      expect(squareColor(tester, 'wild-green', all), colorOf(CardColor.green));
      for (final other in ['red', 'yellow', 'blue']) {
        expect(
          squareColor(tester, 'wild-$other', all),
          isNot(colorOf(CardColor.values.byName(other))),
        );
      }
    });
  });

  group('compact player screen', () {
    testWidgets('shows the card to match and a big hand', (tester) async {
      final hand = [for (var v = 0; v < 7; v++) num(CardColor.red, v)];
      await pumpView(tester, session(hand).viewFor('a'), sent: []);
      expect(find.byKey(const ValueKey('compact-top-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('draw-pile')), findsNothing);
      final size = tester.getSize(handCard(hand.first));
      expect(size.width, greaterThan(76), reason: 'bigger than the old row');
    });

    for (final count in [7, 15]) {
      testWidgets('$count cards fit the width without scrolling', (
        tester,
      ) async {
        final hand = [
          for (var i = 0; i < count; i++) num(CardColor.blue, i % 10),
        ];
        await pumpView(tester, session(hand).viewFor('a'), sent: []);
        expect(find.byType(SingleChildScrollView), findsNothing);
        for (final c in hand) {
          final rect = tester.getRect(handCard(c));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(390));
        }
      });
    }

    testWidgets('a huge hand scrolls instead of shrinking forever', (
      tester,
    ) async {
      final hand = [for (var i = 0; i < 30; i++) num(CardColor.blue, i % 10)];
      await pumpView(tester, session(hand).viewFor('a'), sent: []);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(
        tester.getSize(handCard(hand.first)).width,
        ClashHand.minCardWidth,
      );
    });

    testWidgets('landscape works too', (tester) async {
      final hand = [for (var v = 0; v < 9; v++) num(CardColor.red, v)];
      await pumpView(
        tester,
        session(hand).viewFor('a'),
        sent: [],
        size: const Size(844, 390),
      );
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('a pending penalty shows, and Draw takes it', (tester) async {
      final plus2 = card(CardColor.red, CardKind.drawTwo);
      final g = session([plus2, num(CardColor.red, 1)], stacking: true)
        ..applyAction('a', {'type': 'play', 'cardId': plus2.id});
      final sent = <Json>[];
      // Bob's screen, facing the +2.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColorClashView(
              ctx: GameViewContext(
                view: g.viewFor('b'),
                myId: 'b',
                lobby: lobby(),
                sendAction: sent.add,
                compact: true,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('penalty-badge')), findsOneWidget);
      expect(find.text('Stack, or draw 2'), findsOneWidget);
      await tester.tap(find.text('Draw 2'));
      expect(sent, [
        {'type': 'draw'},
      ]);
    });
  });

  group('swipe to play', () {
    testWidgets('dragging a card up far enough plays it', (tester) async {
      final red7 = num(CardColor.red, 7);
      final sent = <Json>[];
      await pumpView(
        tester,
        session([red7, num(CardColor.blue, 2)]).viewFor('a'),
        sent: sent,
      );
      await swipeUp(tester, red7, 300);
      expect(sent, [
        {'type': 'play', 'cardId': red7.id},
      ]);
    });

    testWidgets('a short drag springs back without playing', (tester) async {
      final red7 = num(CardColor.red, 7);
      final sent = <Json>[];
      await pumpView(
        tester,
        session([red7, num(CardColor.blue, 2)]).viewFor('a'),
        sent: sent,
      );
      final before = tester.getRect(handCard(red7));
      await swipeUp(tester, red7, 30);
      expect(sent, isEmpty);
      expect(tester.getRect(handCard(red7)), before);
    });

    testWidgets('an unplayable card cannot be swiped', (tester) async {
      final blue2 = num(CardColor.blue, 2);
      final sent = <Json>[];
      await pumpView(
        tester,
        session([num(CardColor.red, 7), blue2]).viewFor('a'),
        sent: sent,
      );
      await swipeUp(tester, blue2, 300);
      expect(sent, isEmpty);
    });

    testWidgets('a swiped wild asks for a color; backing out returns it', (
      tester,
    ) async {
      final wild = card(CardColor.wild, CardKind.wild);
      final sent = <Json>[];
      await pumpView(
        tester,
        session([wild, num(CardColor.blue, 2)]).viewFor('a'),
        sent: sent,
      );
      final before = tester.getRect(handCard(wild));

      await swipeUp(tester, wild, 300);
      expect(find.text('Choose a color'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5)); // the dialog's barrier
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(tester.getRect(handCard(wild)), before);

      await swipeUp(tester, wild, 300);
      await tester.tap(find.byKey(const ValueKey('pick-green')));
      await tester.pumpAndSettle();
      expect(sent, [
        {'type': 'play', 'cardId': wild.id, 'color': 'green'},
      ]);
    });

    testWidgets('tapping still plays, in the full view too', (tester) async {
      final red7 = num(CardColor.red, 7);
      final sent = <Json>[];
      await pumpView(
        tester,
        session([red7, num(CardColor.blue, 2)]).viewFor('a'),
        sent: sent,
        compact: false,
        size: const Size(1280, 800),
      );
      await tester.tap(handCard(red7));
      expect(sent, [
        {'type': 'play', 'cardId': red7.id},
      ]);
    });
  });

  testWidgets('the shared screen shows a pending penalty', (tester) async {
    final plus2 = card(CardColor.red, CardKind.drawTwo);
    final g = session([plus2, num(CardColor.red, 1)], stacking: true)
      ..applyAction('a', {'type': 'play', 'cardId': plus2.id});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorClashTable(
            ctx: TableContext(table: g.tableView(), lobby: lobby()),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('penalty-badge')), findsOneWidget);
    expect(find.text('Bob: stack or draw 2'), findsOneWidget);
  });
}
