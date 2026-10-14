import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';
import 'clash_card.dart';

Color colorOf(CardColor color) => switch (color) {
  CardColor.red => const Color(0xFFE53935),
  CardColor.yellow => const Color(0xFFFDD835),
  CardColor.green => const Color(0xFF43A047),
  CardColor.blue => const Color(0xFF1E88E5),
  CardColor.wild => const Color(0xFF212121),
};

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
    final players = (view['players']! as List<Object?>).cast<Json>();
    final turn = view['turn'] as String?;
    final top = ClashCard.fromJson(view['top']! as Json);
    final color = CardColor.values.byName(view['color']! as String);
    final playable = (view['playable']! as List<Object?>).cast<int>().toSet();
    final pendingDrawn = view['pendingDrawn'] as int?;
    final vulnerable = view['vulnerable'] as String?;
    final log = (view['log']! as List<Object?>).cast<String>();
    final myTurn = turn == ctx.myId;
    final theme = Theme.of(context);

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

    return Column(
      children: [
        // Everyone at the table, in turn order.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final p in players)
                _PlayerChip(
                  name: ctx.nicknameOf(p['id']! as String),
                  cards: p['cards']! as int,
                  calledLast: p['calledLast'] == true,
                  isTurn: p['id'] == turn,
                ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _DrawPile(
                        count: view['drawPile']! as int,
                        onTap: myTurn && pendingDrawn == null
                            ? () => ctx.sendAction({'type': 'draw'})
                            : null,
                      ),
                      const SizedBox(width: 24),
                      _CardFace(card: top, width: 96, activeColor: color),
                      const SizedBox(width: 16),
                      Column(
                        children: [
                          Icon(
                            view['direction'] == 1
                                ? Icons.rotate_right
                                : Icons.rotate_left,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: colorOf(color),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    turn == null
                        ? ''
                        : myTurn
                        ? (pendingDrawn != null
                              ? 'Play the card you drew, or pass'
                              : 'Your turn!')
                        : "${ctx.nicknameOf(turn)}'s turn",
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final entry in log.reversed.take(3))
                    Text(entry, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
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
                  child: _CardFace(
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

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.name,
    required this.cards,
    required this.calledLast,
    required this.isTurn,
  });

  final String name;
  final int cards;
  final bool calledLast;
  final bool isTurn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(isTurn ? Icons.play_arrow : Icons.person, size: 18),
      label: Text('$name · $cards${calledLast ? ' · LAST!' : ''}'),
      backgroundColor: isTurn ? scheme.primaryContainer : null,
      side: isTurn ? BorderSide(color: scheme.primary, width: 2) : null,
    );
  }
}

class _DrawPile extends StatelessWidget {
  const _DrawPile({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: const Color(0xFF311B92),
          borderRadius: BorderRadius.circular(10),
          elevation: onTap != null ? 6 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: const SizedBox(
              width: 72,
              height: 108,
              child: Center(
                child: Icon(Icons.style, color: Colors.white, size: 36),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(onTap != null ? 'Draw ($count)' : '$count left'),
      ],
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.card,
    required this.width,
    this.activeColor,
    this.onTap,
  });

  final ClashCard card;
  final double width;

  /// For a wild on the discard pile, the color that was chosen.
  final CardColor? activeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = colorOf(card.color);
    final foreground = card.color == CardColor.yellow
        ? Colors.black87
        : Colors.white;
    final symbol = switch (card.kind) {
      CardKind.number => '${card.value}',
      CardKind.skip => '⊘',
      CardKind.reverse => '⇄',
      CardKind.drawTwo => '+2',
      CardKind.wild => 'W',
      CardKind.wildDrawFour => '+4',
    };
    final ring = card.isWild && activeColor != null
        ? colorOf(activeColor!)
        : Colors.white;

    return Material(
      color: background,
      elevation: onTap != null ? 6 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(width * 0.14),
        side: BorderSide(color: ring, width: width * 0.05),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: width * 1.5,
          child: Center(
            child: Text(
              symbol,
              style: TextStyle(
                color: foreground,
                fontSize: width * 0.42,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
