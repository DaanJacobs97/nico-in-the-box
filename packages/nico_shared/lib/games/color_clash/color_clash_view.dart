import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';
import 'clash_card.dart';
import 'clash_hand.dart';
import 'color_clash_table.dart';

class ColorClashView extends StatelessWidget {
  const ColorClashView({super.key, required this.ctx});

  final GameViewContext ctx;

  @override
  Widget build(BuildContext context) {
    final view = ctx.view;
    final hand = [
      for (final c in view['hand']! as List<Object?>)
        ClashCard.fromJson(c! as Json),
    ];
    final turn = view['turn'] as String?;
    final playable = (view['playable']! as List<Object?>).cast<int>().toSet();
    final pendingDrawn = view['pendingDrawn'] as int?;
    final vulnerable = view['vulnerable'] as String?;
    final penalty = view['penalty'] as int? ?? 0;
    final myTurn = turn == ctx.myId;
    final canDraw = myTurn && pendingDrawn == null;
    final theme = Theme.of(context);
    final status = turn == null
        ? ''
        : myTurn
        ? (pendingDrawn != null
              ? 'Play the card you drew, or pass'
              : penalty > 0
              ? (playable.isEmpty ? 'Draw $penalty' : 'Stack, or draw $penalty')
              : 'Your turn!')
        : "${ctx.nicknameOf(turn)}'s turn";

    Future<bool> playCard(ClashCard card) async {
      if (!card.isWild) {
        ctx.sendAction({'type': 'play', 'cardId': card.id});
        return true;
      }
      final chosen = await _pickColor(context);
      if (chosen == null) return false;
      ctx.sendAction({'type': 'play', 'cardId': card.id, 'color': chosen.name});
      return true;
    }

    void draw() => ctx.sendAction({'type': 'draw'});

    final buttons = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          if (ctx.compact)
            FilledButton.icon(
              key: const ValueKey('draw-button'),
              icon: const Icon(Icons.style),
              label: Text(penalty > 0 && myTurn ? 'Draw $penalty' : 'Draw'),
              onPressed: canDraw ? draw : null,
            ),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.campaign),
            label: const Text('Last card!'),
            onPressed: view['canCallLast'] == true
                ? () => ctx.sendAction({'type': 'callLast'})
                : null,
          ),
          if (pendingDrawn != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.skip_next),
              label: const Text('Pass'),
              onPressed: () => ctx.sendAction({'type': 'pass'}),
            ),
          if (vulnerable != null && vulnerable != ctx.myId)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              icon: const Icon(Icons.pan_tool),
              label: Text('Catch ${ctx.nicknameOf(vulnerable)}!'),
              onPressed: () => ctx.sendAction({'type': 'catch'}),
            ),
        ],
      ),
    );
    final handView = ClashHand(
      cards: hand,
      playable: playable,
      dimUnplayable: myTurn,
      onPlay: playCard,
    );

    if (!ctx.compact) {
      return Column(
        children: [
          Expanded(
            child: ClashTableArea(
              table: view,
              nameOf: ctx.nicknameOf,
              status: status,
              onDraw: canDraw ? draw : null,
            ),
          ),
          buttons,
          const SizedBox(height: 8),
          SizedBox(height: 150, child: handView),
        ],
      );
    }

    // The table is on the shared screen: a status line with the card to
    // match, the buttons, and the hand as big as the screen allows.
    final top = ClashCard.fromJson(view['top']! as Json);
    final color = CardColor.values.byName(view['color']! as String);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              ClashCardFace(
                key: const ValueKey('compact-top-card'),
                card: top,
                width: 44,
                activeColor: color,
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  CircleAvatar(radius: 10, backgroundColor: colorOf(color)),
                  if (penalty > 0) ...[
                    const SizedBox(height: 6),
                    ClashPenaltyBadge(penalty: penalty),
                  ],
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  status,
                  key: const ValueKey('compact-status'),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ],
          ),
        ),
        buttons,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: handView,
          ),
        ),
      ],
    );
  }

  Future<CardColor?> _pickColor(BuildContext context) {
    return showDialog<CardColor>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose a color'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final color in playableColors)
              InkWell(
                key: ValueKey('pick-${color.name}'),
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).pop(color),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: colorOf(color),
                  child: Text(
                    color.name[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
