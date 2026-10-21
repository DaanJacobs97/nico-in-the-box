'use strict';

// Sea Siege table: who is still placing, then every board (the host's first)
// on moving water with its shots and sunk ships. A gold banner says who is
// firing at whom; the target board glows and the other dims. New shots pop
// up as toasts over the board they hit, and their square flashes. Ships still
// afloat are never in the table. Boards sit side by side in landscape and
// stacked in portrait (style.css). Mirrors SeaSiegeTable in
// packages/nico_shared; the ship PNGs are drawn from the same painter by
// tool/sprites/.
(() => {
  const SIZE = 10;
  const COLUMNS = 'ABCDEFGHIJ';
  const SHOT_LIFE = 3000; // ms a toast stays up
  const FLASH_LIFE = 1000;
  const cellName = (cell) => `${COLUMNS[cell % SIZE]}${Math.floor(cell / SIZE) + 1}`;

  // The page is rebuilt on every update, so remember which shots were
  // already seen (by their number `n`) and when new ones arrived. Shots in
  // the log when the page first sees the game are not replayed.
  let seen = null;
  const fresh = new Map(); // n -> { shot, at }

  function trackShots(log) {
    const latest = log.length ? log[log.length - 1].n : 0;
    if (seen === null) seen = latest;
    if (latest < seen) seen = 0; // a new game started
    const now = performance.now();
    for (const shot of log) {
      if (shot.n > seen) fresh.set(shot.n, { shot, at: now });
    }
    seen = latest;
    for (const [n, f] of fresh) {
      if (now - f.at > SHOT_LIFE) fresh.delete(n);
    }
    return now;
  }

  // The fleet being fired at, or null when the game is over or more than
  // one fleet is left to pick from.
  function targetOf(table) {
    if (!table.turn || table.winner) return null;
    const targets = table.order.filter((id) => id !== table.turn && table.boards[id].afloat.length);
    return targets.length === 1 ? targets[0] : null;
  }

  NicoDisplay.register('seasiege', (table, lobby, { el, nameOf }) => {
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

    const now = trackShots(table.log);
    const target = targetOf(table);

    const describe = (shot) => {
      const outcome =
        shot.result === 'sunk' ? `Hit! ${shot.ship} sunk!` : shot.result === 'hit' ? `Hit! ${shot.ship}.` : 'Miss.';
      return `${nameOf(lobby, shot.shooter)} fired at ${cellName(shot.cell)}: ${outcome}`;
    };

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

      // New shots on this board: a flashing ring on the square, and a toast.
      // A negative animation delay keeps each one's timing across rebuilds.
      const mine = [...fresh.values()].filter((f) => f.shot.target === id);
      for (const { shot, at } of mine) {
        const age = now - at;
        if (age >= FLASH_LIFE) continue;
        const style = `left:${((shot.cell % SIZE) - 0.5) * 10}%;top:${(Math.floor(shot.cell / SIZE) - 0.5) * 10}%;animation-delay:-${age}ms`;
        water.append(el('span', { class: 'sea-flash', style }));
      }
      const toasts = el('div', { class: 'sea-toasts' });
      for (const { shot, at } of mine.slice(-2)) {
        const kind = shot.result === 'miss' ? 'miss' : 'hit';
        toasts.append(
          el('div', { class: `sea-toast ${kind}`, style: `animation-delay:-${now - at}ms` }, describe(shot))
        );
      }
      water.append(toasts);
      grid.append(water);

      const classes = ['sea-panel'];
      if (id === target) classes.push('target');
      else if (target) classes.push('dim');
      return el(
        'div',
        { class: classes.join(' ') },
        el('h3', {}, id === target ? el('span', { class: 'sea-crosshair' }) : '', `${nameOf(lobby, id)}'s fleet`),
        grid
      );
    }

    const status = table.winner
      ? `${nameOf(lobby, table.winner)} wins!`
      : target
        ? `${nameOf(lobby, table.turn)} is firing at ${nameOf(lobby, target)}'s fleet`
        : `${nameOf(lobby, table.turn)}'s turn to fire`;
    const hostFirst = [
      ...table.order.filter((id) => id === lobby.hostId),
      ...table.order.filter((id) => id !== lobby.hostId),
    ];

    return el(
      'div',
      { class: 'game' },
      el('div', { class: 'sea-banner' }, status),
      table.shootAgain ? el('div', { class: 'log' }, 'A hit earns another shot') : '',
      el('div', { class: 'sea-boards' }, ...hostFirst.map(board))
    );
  });
})();
