'use strict';

// Tic Tac Toe table: who is X and O, whose turn it is, and the board.
// Mirrors TicTacToeTable in packages/nico_shared.
NicoDisplay.register('tictactoe', (table, lobby, { el, nameOf }) => {
  const marks = table.marks;
  const playerWith = (mark) =>
    nameOf(lobby, Object.keys(marks).find((id) => marks[id] === mark));

  let status;
  if (table.winner) status = `${nameOf(lobby, table.winner)} wins!`;
  else if (table.draw) status = "It's a draw!";
  else status = `${nameOf(lobby, table.turn)}'s turn (${marks[table.turn]})`;

  const winLine = table.winLine || [];
  const board = el('div', { class: 'ttt-board' });
  table.board.forEach((mark, i) => {
    board.append(
      el(
        'div',
        { class: `ttt-cell${winLine.includes(i) ? ' win' : ''}` },
        mark ? el('span', { class: `mark-${mark}` }, mark) : ''
      )
    );
  });

  return el(
    'div',
    { class: 'game' },
    el(
      'h2',
      {},
      el('span', { class: 'mark-X' }, 'X'),
      `  ${playerWith('X')}   vs   ${playerWith('O')}  `,
      el('span', { class: 'mark-O' }, 'O')
    ),
    el('div', { class: 'status' }, status),
    board
  );
});
