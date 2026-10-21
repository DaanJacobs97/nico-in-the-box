'use strict';

// Sea Siege table: who is still placing, then every board (the host's first)
// on moving water with its shots and sunk ships, whose turn it is and the
// last shots. Ships still afloat are never in the table. Boards sit side by
// side in landscape and stacked in portrait (style.css). Mirrors
// SeaSiegeTable in packages/nico_shared; the ship PNGs are drawn from the
// same painter by tool/sprites/.
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

  // A sunk ship across its squares. The PNG is drawn bow-right; a vertical
  // ship is turned a quarter clockwise around its top-left corner, so it
  // starts one column to the right.
  function wreck(ship) {
    const style = ship.vertical
      ? `left:${(ship.col + 1) * 10}%;top:${ship.row * 10}%;width:${ship.size * 10}%;transform:rotate(90deg)`
      : `left:${ship.col * 10}%;top:${ship.row * 10}%;width:${ship.size * 10}%`;
    return el('img', { class: 'sea-ship', src: `games/seasiege/${ship.id}_sunk.png`, alt: ship.name, style });
  }

  function board(id) {
    const b = table.boards[id];
    const hits = new Set(b.hits);
    const misses = new Set(b.misses);
    const grid = el('div', { class: 'sea-grid' }, el('span', { class: 'sea-label' }, ''));
    for (const c of COLUMNS) grid.append(el('span', { class: 'sea-label' }, c));
    for (let r = 0; r < SIZE; r++) {
      grid.append(el('span', { class: 'sea-label', style: `grid-column:1;grid-row:${r + 2}` }, String(r + 1)));
    }
    const water = el('div', { class: 'sea-water' });
    for (let cell = 0; cell < SIZE * SIZE; cell++) {
      const marker = hits.has(cell) ? 'hit' : misses.has(cell) ? 'miss' : '';
      water.append(el('span', { class: 'sea-cell' }, marker ? el('span', { class: `peg ${marker}` }) : ''));
    }
    water.append(...b.sunk.map(wreck));
    grid.append(water);
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
  const hostFirst = [
    ...table.order.filter((id) => id === lobby.hostId),
    ...table.order.filter((id) => id !== lobby.hostId),
  ];

  return el(
    'div',
    { class: 'game' },
    el('div', { class: 'status' }, status),
    table.shootAgain ? el('div', { class: 'log' }, 'A hit earns another shot') : '',
    el('div', { class: 'sea-boards' }, ...hostFirst.map(board)),
    ...table.log.slice(-2).reverse().map((shot) => el('div', { class: 'log' }, describe(shot)))
  );
});
