'use strict';

// Color Clash table: everyone's card count in turn order, the draw pile, the
// top card, the active color, direction and the move log. Never a hand: the
// table view doesn't contain one. Mirrors ColorClashTable in nico_shared.
NicoDisplay.register('colorclash', (table, lobby, { el, nameOf }) => {
  const SYMBOLS = {
    skip: '⊘',
    reverse: '⇄',
    drawTwo: '+2',
    wild: 'W',
    wildDrawFour: '+4',
  };

  const players = el('div', { class: 'chips' });
  for (const p of table.players) {
    players.append(
      el(
        'span',
        { class: `chip${p.id === table.turn ? ' turn' : ''}` },
        p.id === table.turn ? '▶ ' : '',
        nameOf(lobby, p.id),
        ` · ${p.cards}`,
        p.calledLast ? el('span', { class: 'badge' }, 'LAST!') : ''
      )
    );
  }

  const top = table.top;
  const symbol = top.kind === 'number' ? String(top.value) : SYMBOLS[top.kind];
  // A wild shows the color that was chosen as its border.
  const card = el('div', { class: `card bg-${top.color}${top.color === 'yellow' ? ' yellow' : ''}` }, symbol);
  if (top.color === 'wild') card.style.borderColor = `var(--${table.color})`;

  const status = table.turn ? `${nameOf(lobby, table.turn)}'s turn` : '';
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
        el('div', { class: `dot bg-${table.color}` })
      )
    ),
    el('div', { class: 'status' }, status),
    log
  );
});
