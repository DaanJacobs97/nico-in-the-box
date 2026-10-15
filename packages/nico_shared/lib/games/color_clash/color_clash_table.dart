import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';
import 'clash_card.dart';

/// Card colors on screen.
Color colorOf(CardColor color) => switch (color) {
  CardColor.red => const Color(0xFFE53935),
  CardColor.yellow => const Color(0xFFFDD835),
  CardColor.green => const Color(0xFF43A047),
  CardColor.blue => const Color(0xFF1E88E5),
  CardColor.wild => const Color(0xFF212121),
};

/// The public part of the table: everyone's card counts in turn order, the
/// draw and discard piles, the active color, direction, status and log.
/// Used inside a player's full view and, scaled up, on the shared screen.
class ClashTableArea extends StatelessWidget {
  const ClashTableArea({
    super.key,
    required this.table,
    required this.nameOf,
    required this.status,
    this.onDraw,
    this.scale = 1,
    this.logLines = 3,
  });

  /// A table view (or a player view, which contains one).
  final Json table;
  final String Function(String playerId) nameOf;
  final String status;

  /// Set when the viewer may draw now; null makes the pile read-only.
  final VoidCallback? onDraw;
  final double scale;
  final int logLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final players = (table['players']! as List<Object?>).cast<Json>();
    final turn = table['turn'] as String?;
    final top = ClashCard.fromJson(table['top']! as Json);
    final color = CardColor.values.byName(table['color']! as String);
    final log = (table['log']! as List<Object?>).cast<String>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(
            spacing: 8 * scale,
            runSpacing: 8 * scale,
            alignment: WrapAlignment.center,
            children: [
              for (final p in players)
                _PlayerChip(
                  key: ValueKey('player-chip-${p['id']}'),
                  name: nameOf(p['id']! as String),
                  cards: p['cards']! as int,
                  calledLast: p['calledLast'] == true,
                  isTurn: p['id'] == turn,
                  scale: scale,
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
                        key: const ValueKey('draw-pile'),
                        count: table['drawPile']! as int,
                        onTap: onDraw,
                        scale: scale,
                      ),
                      SizedBox(width: 24 * scale),
                      ClashCardFace(
                        card: top,
                        width: 96 * scale,
                        activeColor: color,
                      ),
                      SizedBox(width: 16 * scale),
                      Column(
                        children: [
                          Icon(
                            table['direction'] == 1
                                ? Icons.rotate_right
                                : Icons.rotate_left,
                            size: 32 * scale,
                          ),
                          SizedBox(height: 8 * scale),
                          CircleAvatar(
                            radius: 12 * scale,
                            backgroundColor: colorOf(color),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 16 * scale),
                  Text(
                    status,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize:
                          (theme.textTheme.titleLarge?.fontSize ?? 22) * scale,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final entry in log.reversed.take(logLines))
                    Text(
                      entry,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize:
                            (theme.textTheme.bodySmall?.fontSize ?? 12) * scale,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Color Clash on the shared screen: the table, large, without any hand.
class ColorClashTable extends StatelessWidget {
  const ColorClashTable({super.key, required this.ctx});

  final TableContext ctx;

  @override
  Widget build(BuildContext context) {
    final turn = ctx.table['turn'] as String?;
    return LayoutBuilder(
      builder: (context, constraints) => ClashTableArea(
        table: ctx.table,
        nameOf: ctx.nicknameOf,
        status: turn == null ? '' : "${ctx.nicknameOf(turn)}'s turn",
        // Grow with the screen; a TV gets roughly double size.
        scale: (constraints.biggest.shortestSide / 450).clamp(1.0, 2.5),
        logLines: 5,
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    super.key,
    required this.name,
    required this.cards,
    required this.calledLast,
    required this.isTurn,
    this.scale = 1,
  });

  final String name;
  final int cards;
  final bool calledLast;
  final bool isTurn;

  /// Grows the real font, icon and padding (not a paint-only transform),
  /// so neighbouring chips make room on big screens.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Chip(
      padding: EdgeInsets.all(4 * scale),
      avatar: Icon(isTurn ? Icons.play_arrow : Icons.person, size: 18 * scale),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        fontSize: (theme.textTheme.labelLarge?.fontSize ?? 14) * scale,
      ),
      label: Text('$name · $cards${calledLast ? ' · LAST!' : ''}'),
      backgroundColor: isTurn ? scheme.primaryContainer : null,
      side: isTurn ? BorderSide(color: scheme.primary, width: 2) : null,
    );
  }
}

class _DrawPile extends StatelessWidget {
  const _DrawPile({super.key, required this.count, this.onTap, this.scale = 1});

  final int count;
  final VoidCallback? onTap;
  final double scale;

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
            child: SizedBox(
              width: 72 * scale,
              height: 108 * scale,
              child: Center(
                child: Icon(Icons.style, color: Colors.white, size: 36 * scale),
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

class ClashCardFace extends StatelessWidget {
  const ClashCardFace({
    super.key,
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
