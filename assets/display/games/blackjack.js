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

  function hand(h, active) {
    const total = h.natural ? 'Blackjack' : `${h.total}${h.total > 21 ? ' bust' : ''}`;
    const bet = chipsMode ? ` · ${h.bet}${h.doubled ? ' (x2)' : ''}` : '';
    const result = RESULTS[h.result];
    return el(
      'div',
      { class: `bj-hand${active ? ' active' : ''}` },
      el('div', { class: 'cards' }, ...h.cards.map(card)),
      el('div', {}, total + bet),
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
        el('div', { class: 'muted' }, score + extra),
        ...s.hands.map((h, i) => hand(h, i === turnHand))
      )
    );
  }

  const turn = table.turn ? `${nameOf(lobby, table.turn.player)}'s turn` : '';
  return el(
    'div',
    { class: 'game' },
    el('div', { class: 'muted' }, `${header} · ${table.cardsLeft} cards left${reshuffled}`),
    el(
      'div',
      { class: 'bj-dealer' },
      el('div', { class: 'name' }, dealerLabel),
      el('div', { class: 'cards' }, ...dealerCards)
    ),
    el('div', { class: 'status' }, turn),
    seats
  );
});
