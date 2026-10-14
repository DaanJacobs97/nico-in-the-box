import 'package:flutter/material.dart';

import '../../net/protocol.dart';
import '../game_views.dart';

class TicTacToeView extends StatelessWidget {
  const TicTacToeView({super.key, required this.ctx});

  final GameViewContext ctx;

  @override
  Widget build(BuildContext context) {
    final view = ctx.view;
    final board = (view['board']! as List<Object?>).cast<String?>();
    final marks = (view['marks']! as Json).cast<String, String>();
    final turn = view['turn'] as String?;
    final winner = view['winner'] as String?;
    final winLine = (view['winLine'] as List<Object?>?)?.cast<int>() ?? [];
    final myMark = marks[ctx.myId];
    final myTurn = turn == ctx.myId;

    final String status;
    if (winner != null) {
      status = winner == ctx.myId
          ? 'You win!'
          : '${ctx.nicknameOf(winner)} wins!';
    } else if (view['draw'] == true) {
      status = "It's a draw!";
    } else if (myTurn) {
      status = 'Your turn ($myMark)';
    } else {
      status = 'Waiting for ${ctx.nicknameOf(turn!)} (${marks[turn]})';
    }

    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(status, style: theme.textTheme.headlineSmall),
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (var i = 0; i < 9; i++)
                      _Cell(
                        key: ValueKey('ttt-cell-$i'),
                        mark: board[i],
                        highlighted: winLine.contains(i),
                        onTap: myTurn && board[i] == null
                            ? () => ctx.sendAction({'type': 'place', 'cell': i})
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tic Tac Toe on the shared screen: who is X and O, whose turn it is, and
/// a large read-only board.
class TicTacToeTable extends StatelessWidget {
  const TicTacToeTable({super.key, required this.ctx});

  final TableContext ctx;

  @override
  Widget build(BuildContext context) {
    final table = ctx.table;
    final board = (table['board']! as List<Object?>).cast<String?>();
    final marks = (table['marks']! as Json).cast<String, String>();
    final turn = table['turn'] as String?;
    final winner = table['winner'] as String?;
    final winLine = (table['winLine'] as List<Object?>?)?.cast<int>() ?? [];
    String playerWith(String mark) =>
        ctx.nicknameOf(marks.entries.firstWhere((e) => e.value == mark).key);

    final String status;
    if (winner != null) {
      status = '${ctx.nicknameOf(winner)} wins!';
    } else if (table['draw'] == true) {
      status = "It's a draw!";
    } else {
      status = "${ctx.nicknameOf(turn!)}'s turn (${marks[turn]})";
    }

    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'X  ${playerWith('X')}   vs   ${playerWith('O')}  O',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(status, style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (var i = 0; i < 9; i++)
                      _Cell(mark: board[i], highlighted: winLine.contains(i)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.mark,
    required this.highlighted,
    this.onTap,
  });

  final String? mark;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = mark == 'X' ? scheme.primary : scheme.tertiary;
    return Material(
      color: highlighted
          ? scheme.secondaryContainer
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                mark ?? '',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
