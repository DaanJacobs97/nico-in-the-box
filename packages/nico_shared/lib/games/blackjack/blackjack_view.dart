import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';
import 'blackjack_game.dart';
import 'blackjack_table.dart';

export 'blackjack_table.dart' show BlackjackTable;

/// A player's Blackjack screen: the table (or, with a shared screen, just
/// the dealer and their own seat) and what they can do now.
class BlackjackView extends StatelessWidget {
  const BlackjackView({super.key, required this.ctx});

  final GameViewContext ctx;

  static const betAmounts = [10, 50, 100, 250, 500];

  @override
  Widget build(BuildContext context) {
    final view = ctx.view;
    final actions = (view['actions']! as List<Object?>).cast<String>();
    final seats = (view['seats']! as List<Object?>).cast<Json>();
    final mine = seats.where((s) => s['id'] == ctx.myId).firstOrNull;
    final theme = Theme.of(context);

    final status = Text(
      _status(view, actions, seats),
      key: const ValueKey('bj-status'),
      textAlign: TextAlign.center,
      style: theme.textTheme.titleLarge,
    );
    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          if (actions.contains('deal'))
            FilledButton.icon(
              key: const ValueKey('bj-deal'),
              icon: const Icon(Icons.style),
              label: const Text('Deal'),
              onPressed: () => ctx.sendAction({'type': 'deal'}),
            ),
          if (actions.contains('bet') && mine != null)
            for (final amount in _betChoices(mine['chips']! as int))
              FilledButton.tonal(
                key: ValueKey('bj-bet-$amount'),
                onPressed: () =>
                    ctx.sendAction({'type': 'bet', 'amount': amount}),
                child: Text('Bet $amount'),
              ),
          for (final (type, label, icon) in const [
            ('hit', 'Hit', Icons.add),
            ('stand', 'Stand', Icons.pan_tool),
            ('double', 'Double', Icons.exposure_plus_2),
            ('split', 'Split', Icons.call_split),
          ])
            if (actions.contains(type))
              FilledButton.icon(
                key: ValueKey('bj-action-$type'),
                icon: Icon(icon),
                label: Text(label),
                onPressed: () => ctx.sendAction({'type': type}),
              ),
        ],
      ),
    );

    if (!ctx.compact) {
      return Column(
        children: [
          Expanded(
            child: BlackjackTableArea(
              table: view,
              nameOf: ctx.nicknameOf,
              myId: ctx.myId,
            ),
          ),
          status,
          controls,
        ],
      );
    }
    // The table is on the shared screen: the dealer to play against, your
    // own seat large, and the buttons.
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxWidth / 360).clamp(1.0, 1.8);
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    BlackjackDealer(
                      dealer: view['dealer']! as Json,
                      scale: scale,
                    ),
                    const SizedBox(height: 16),
                    if (mine != null)
                      BlackjackSeat(
                        key: const ValueKey('bj-my-seat'),
                        seat: mine,
                        name: 'You',
                        chipsMode: view['mode'] == 'chips',
                        between: view['playing'] != true,
                        turnHand: (view['turn'] as Json?)?['player'] == ctx.myId
                            ? (view['turn']! as Json)['hand'] as int
                            : null,
                        scale: scale * 1.3,
                      ),
                  ],
                ),
              ),
            ),
            status,
            controls,
          ],
        );
      },
    );
  }

  /// The quick bets the player can afford, plus "all in" (rounded down to
  /// 10) when that's less than the biggest.
  static List<int> _betChoices(int chips) {
    final allIn = (chips.clamp(0, maxBet) ~/ minBet) * minBet;
    return [
      for (final a in betAmounts)
        if (a <= chips) a,
      if (allIn >= minBet && !betAmounts.contains(allIn)) allIn,
    ];
  }

  String _status(Json view, List<String> actions, List<Json> seats) {
    if (view['winners'] != null) return '';
    final turn = view['turn'] as Json?;
    if (turn != null) {
      final split = seats.any(
        (s) =>
            s['id'] == turn['player'] &&
            (s['hands']! as List<Object?>).length > 1,
      );
      final which = split ? ' (hand ${(turn['hand']! as int) + 1})' : '';
      return turn['player'] == ctx.myId
          ? 'Your turn$which'
          : "${ctx.nicknameOf(turn['player']! as String)}'s turn$which";
    }
    if (actions.contains('bet')) return 'Place your bet';
    if (actions.contains('deal')) return 'Tap Deal for the next hand';
    final waiting = [
      for (final s in seats)
        if (s['out'] != true && s['ready'] != true)
          ctx.nicknameOf(s['id']! as String),
    ];
    return waiting.isEmpty ? '' : 'Waiting for ${waiting.join(', ')}';
  }
}
