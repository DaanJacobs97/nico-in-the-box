import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';
import 'clash_card.dart';
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
    final myTurn = turn == ctx.myId;
    final canDraw = myTurn && pendingDrawn == null;
    final theme = Theme.of(context);
    final status = turn == null
        ? ''
        : myTurn
        ? (pendingDrawn != null
              ? 'Play the card you drew, or pass'
              : 'Your turn!')
        : "${ctx.nicknameOf(turn)}'s turn";

    Future<void> playCard(ClashCard card) async {
      if (!card.isWild) {
        ctx.sendAction({'type': 'play', 'cardId': card.id});
        return;
      }
      final chosen = await _pickColor(context);
      if (chosen != null) {
        ctx.sendAction({
          'type': 'play',
          'cardId': card.id,
          'color': chosen.name,
        });
      }
    }

    void draw() => ctx.sendAction({'type': 'draw'});

    return Column(
      children: [
        if (ctx.compact) ...[
          // The table is on the shared screen; keep just a status line.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              status,
              key: const ValueKey('compact-status'),
              style: theme.textTheme.headlineSmall,
            ),
          ),
          const Spacer(),
        ] else
          Expanded(
            child: ClashTableArea(
              table: view,
              nameOf: ctx.nicknameOf,
              status: status,
              onDraw: canDraw ? draw : null,
            ),
          ),
        Padding(
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
                  label: const Text('Draw'),
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
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: ListView.separated(
            key: const ValueKey('hand-list'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            itemCount: hand.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final card = hand[i];
              final canPlay = playable.contains(card.id);
              return AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                offset: canPlay ? const Offset(0, -0.08) : Offset.zero,
                child: Opacity(
                  opacity: myTurn && !canPlay ? 0.55 : 1,
                  child: ClashCardFace(
                    key: ValueKey('hand-card-${card.id}'),
                    card: card,
                    width: 76,
                    onTap: canPlay ? () => playCard(card) : null,
                  ),
                ),
              );
            },
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
