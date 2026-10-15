'use strict';

// Sea Siege table: who is still placing, then every board with its shots and
// sunk ships, whose turn it is and the last shots. Ships still afloat are
// never in the table. Mirrors SeaSiegeTable in packages/nico_shared.
NicoDisplay.register('seasiege', (table, lobby, { el, nameOf }) => {
  const SIZE = 10;
  const COLUMNS = 'ABCDEFGHIJ';
  const cellName = (cell) => `${COLUMNS[cell % SIZE]}${Math.floor(cell / SIZE) + 1}`;

  if (table.phase === 'placing') {
    return el(
      'div',
      { class: 'center' },
      el('h1', {}, 'Captains, hide your fleets!'),
      ...table.order.map((id) =>
        el('div', { class: 'status' }, `${nameOf(lobby, id)}: ${table.ready[id] ? 'ready' : 'placing ships…'}`)
      )
    );
  }

  function board(id) {
    const b = table.boards[id];
    const hits = new Set(b.hits);
    const misses = new Set(b.misses);
    const sunk = new Set(b.sunk.flatMap((ship) => ship.cells));
    const grid = el('div', { class: 'sea-grid' }, el('span', { class: 'sea-label' }, ''));
    for (const c of COLUMNS) grid.append(el('span', { class: 'sea-label' }, c));
    for (let r = 0; r < SIZE; r++) {
      grid.append(el('span', { class: 'sea-label' }, String(r + 1)));
      for (let c = 0; c < SIZE; c++) {
        const cell = r * SIZE + c;
        const marker = hits.has(cell) ? 'hit' : misses.has(cell) ? 'miss' : '';
        grid.append(
          el(
            'span',
            { class: `sea-cell${sunk.has(cell) ? ' sunk' : ''}` },
            marker ? el('span', { class: `peg ${marker}` }) : ''
          )
        );
      }
    }
    return el(
      'div',
      { class: 'sea-panel' },
      el('h3', {}, `${nameOf(lobby, id)}'s fleet`),
      grid,
      el('div', { class: 'log' }, b.afloat.length ? `Afloat: ${b.afloat.join(', ')}` : 'Fleet sunk')
    );
  }

  const describe = (shot) => {
    const outcome =
      shot.result === 'sunk' ? `Hit! ${shot.ship} sunk!` : shot.result === 'hit' ? `Hit! ${shot.ship}.` : 'Miss.';
    return `${nameOf(lobby, shot.shooter)} fired at ${cellName(shot.cell)}: ${outcome}`;
  };

  const status = table.winner
    ? `${nameOf(lobby, table.winner)} wins!`
    : `${nameOf(lobby, table.turn)}'s turn to fire`;

  return el(
    'div',
    { class: 'game' },
    el('div', { class: 'status' }, status),
    table.shootAgain ? el('div', { class: 'log' }, 'A hit earns another shot') : '',
    el('div', { class: 'sea-boards' }, ...table.order.map(board)),
    ...table.log.slice(-2).reverse().map((shot) => el('div', { class: 'log' }, describe(shot)))
  );
});
