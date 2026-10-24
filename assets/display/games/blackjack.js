'use strict';

// Blackjack table: the header line, the dealer (hole card face down until
// the dealer plays; it's never sent before that) and every seat with its
// hands. Mirrors BlackjackTable in packages/nico_shared.
NicoDisplay.register('blackjack', (table, lobby, { el, nameOf }) => {
  // U+FE0E asks for the plain glyph; Android otherwise draws emoji suits.
  const SUITS = { spades: '♠︎', hearts: '♥︎', diamonds: '♦︎', clubs: '♣︎' };
  const RANKS = { 1: 'A', 11: 'J', 12: 'Q', 13: 'K' };
  const RESULTS = {
    blackjack: ['Blackjack!', 'bj'],
    win: ['Win', 'win'],
    push: ['Push', 'push'],
    lose: ['Lose', 'lose'],
  };
  const chipsMode = table.mode === 'chips';

  function card(c) {
    if (!c) return el('div', { class: 'pcard back' });
    const red = c.suit === 'hearts' || c.suit === 'diamonds';
    return el(
      'div',
      { class: `pcard${red ? ' red' : ''}` },
      el('div', {}, RANKS[c.rank] || String(c.rank)),
      el('div', {}, SUITS[c.suit])
    );
  }

  // Chip values, biggest first; blackjack pays 3:2, so a 5 can turn up.
  const CHIP_VALUES = [500, 100, 50, 10, 5];

  // An amount as stacks of chips, one per value, biggest left.
  function chips(amount) {
    const stacks = el('div', { class: 'chip-stacks' });
    let left = amount;
    for (const value of CHIP_VALUES) {
      const count = Math.floor(left / value);
      if (!count) continue;
      left %= value;
      const stack = el('div', { class: 'chip-stack' });
      for (let i = 0; i < Math.min(count, 8); i++) {
        stack.append(el('div', { class: `cchip v${value}` }, String(value)));
      }
      stacks.append(stack);
    }
    return stacks;
  }

  function betLine(amount, doubled) {
    return el(
      'div',
      { class: 'bj-bet' },
      chips(amount),
      `Bet: ${amount} chips${doubled ? ' (doubled)' : ''}`
    );
  }

  function hand(h, active) {
    const total = h.natural ? 'Blackjack' : `${h.total}${h.total > 21 ? ' bust' : ''}`;
    const result = RESULTS[h.result];
    return el(
      'div',
      { class: `bj-hand${active ? ' active' : ''}` },
      el('div', { class: 'cards' }, ...h.cards.map(card)),
      el('div', {}, total),
      chipsMode ? betLine(h.bet, h.doubled) : '',
      result ? el('div', { class: `bj-result ${result[1]}` }, result[0]) : ''
    );
  }

  const played = table.handsPlayed;
  const header = chipsMode
    ? `Most chips · ${played} of ${table.hands} hands played`
    : `First to ${table.hands} wins · ${played} hands played`;
  const reshuffled = table.reshuffled && table.playing ? ' (reshuffled)' : '';

  const dealerCards = table.dealer.cards.map(card);
  if (table.dealer.hidden) dealerCards.push(card(null));
  const dealerLabel = table.dealer.cards.length
    ? `Dealer · ${table.dealer.total}${table.dealer.hidden ? ' + ?' : ''}`
    : 'Dealer';

  const seats = el('div', { class: 'bj-seats' });
  for (const s of table.seats) {
    const turnHand = table.turn && table.turn.player === s.id ? table.turn.hand : -1;
    const score = chipsMode ? `${s.chips} chips` : `${s.wins} wins`;
    const extra = s.out ? ' · out' : !table.playing && s.ready ? ' · ready' : '';
    seats.append(
      el(
        'div',
        { class: `bj-seat${turnHand >= 0 ? ' turn' : ''}` },
        el('div', { class: 'name' }, nameOf(lobby, s.id)),
        el('div', { class: 'muted' }, chipsMode ? el('span', { class: 'cchip v100 icon' }) : '', score + extra),
        // A bet placed for the next hand, before the cards come.
        chipsMode && !table.playing && s.bet > 0 ? betLine(s.bet, false) : '',
        ...s.hands.map((h, i) => hand(h, i === turnHand))
      )
    );
  }

  const turn = table.turn ? `${nameOf(lobby, table.turn.player)}'s turn` : '';
  return el(
    'div',
    { class: 'game bj-game' },
    el('div', { class: 'muted' }, `${header} · ${table.cardsLeft} cards left${reshuffled}`),
    el(
      'div',
      { class: 'bj-dealer' },
      el('div', { class: 'name' }, dealerLabel),
      el('div', { class: 'cards' }, ...dealerCards),
      // Printed on the felt, as on a real table.
      el('div', { class: 'bj-rule' }, 'BLACKJACK PAYS 3 TO 2 · DEALER STANDS ON 17')
    ),
    el('div', { class: 'status' }, turn),
    seats
  );
});
