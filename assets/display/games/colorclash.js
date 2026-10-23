'use strict';

// Color Clash table: everyone's card count in turn order, the draw pile, the
// top card, the active color, direction and the move log. Never a hand: the
// table view doesn't contain one. Mirrors ColorClashTable in nico_shared.
NicoDisplay.register('colorclash', (table, lobby, { el, nameOf }) => {
  const SYMBOLS = {
    skip: '⊘',
    reverse: '⇄',
    drawTwo: '+2',
  };

  const players = el('div', { class: 'chips' });
  for (const p of table.players) {
    players.append(
      el(
        'span',
        { class: `chip${p.id === table.turn ? ' turn' : ''}` },
        // U+FE0E asks for the plain glyph; Android otherwise draws an emoji.
        p.id === table.turn ? '▶︎ ' : '',
        nameOf(lobby, p.id),
        ` · ${p.cards}`,
        p.calledLast ? el('span', { class: 'badge' }, 'LAST!') : ''
      )
    );
  }

  const top = table.top;
  let card;
  if (top.color === 'wild') {
    // A grid of the four colors; the chosen one stays bright and colors the
    // border. A Wild +4 has "+4" on top.
    const grid = el('div', { class: 'wild-grid' });
    for (const color of ['red', 'yellow', 'green', 'blue']) {
      grid.append(el('div', { class: `bg-${color}${color === table.color ? '' : ' faded'}` }));
    }
    card = el('div', { class: 'card bg-wild wild' }, grid);
    if (top.kind === 'wildDrawFour') card.append(el('div', { class: 'plus4' }, '+4'));
    card.style.borderColor = `var(--${table.color})`;
  } else {
    const symbol = top.kind === 'number' ? String(top.value) : SYMBOLS[top.kind];
    card = el('div', { class: `card bg-${top.color}${top.color === 'yellow' ? ' yellow' : ''}` }, symbol);
  }

  const penalty = table.penalty || 0;
  const status = !table.turn
    ? ''
    : penalty > 0
      ? `${nameOf(lobby, table.turn)}: stack or draw ${penalty}`
      : `${nameOf(lobby, table.turn)}'s turn`;
  const log = el('div', { class: 'log' });
  for (const entry of table.log.slice(-5).reverse()) log.append(el('div', {}, entry));

  return el(
    'div',
    { class: 'game' },
    players,
    el(
      'div',
      { class: 'table-row' },
      el('div', { class: 'pile', title: 'Draw pile' }, String(table.drawPile)),
      card,
      el(
        'div',
        { class: 'side' },
        el('div', {}, table.direction === 1 ? '↻' : '↺'),
        el('div', { class: `dot bg-${table.color}` }),
        penalty > 0 ? el('div', { class: 'penalty' }, `+${penalty}`) : ''
      )
    ),
    el('div', { class: 'status' }, status),
    log
  );
});
