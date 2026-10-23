'use strict';

const tacticalPortraits = {
  hero: { closeCombat: 'aldric', ranged: 'seren', trapper: 'mora' },
  enemy: { closeCombat: 'hollow_guard', ranged: 'hollow_archer', trapper: 'blight_hound' },
};

NicoDisplay.register('tacticalvoxelrpg', (table, lobby, { el, nameOf }) => {
  const unitAt = new Map(table.units.map((unit) => [`${unit.x},${unit.y}`, unit]));
  const trapsAt = new Set(table.traps.map((trap) => `${trap.x},${trap.y}`));
  const active = table.units.find((unit) => unit.id === table.activeUnit);
  const planned = new Set((active?.route || []).map((point) => `${point.x},${point.y}`));
  const damage = table.lastAction &&
    (table.lastAction.type === 'attack' || table.lastAction.type === 'trapHit')
    ? table.lastAction
    : null;

  function animationFor(unit) {
    const action = table.lastAction;
    if (!unit.sprite || !action) return 'idle';
    if (action.type === 'move' && action.unit === unit.id) return 'walk';
    if (action.type === 'trap' && action.unit === unit.id) return 'special';
    if (action.type === 'trapHit' && action.unit === unit.id) return 'hurt';
    if (action.type === 'attack') {
      if (action.target === unit.id) return 'hurt';
      if (action.unit === unit.id) return action.animation || 'melee';
    }
    return 'idle';
  }

  function portraitFor(unit) {
    const team = unit.owner === '__ai__' ? 'enemy' : 'hero';
    const name = tacticalPortraits[team][unit.kind];
    // The host serves game art from its own copy (see web_routes.dart).
    return name ? `/art/tacticalvoxelrpg/characters/${name}.png` : null;
  }

  const cells = table.tiles.map((tile) => {
    const key = `${tile.x},${tile.y}`;
    const unit = unitAt.get(key);
    const classes = [
      'tvrpg-cell',
      `terrain-${tile.terrain}`,
      `biome-${tile.biome}`,
      planned.has(key) ? 'planned' : '',
      unit ? (unit.owner === '__ai__' ? 'enemy' : 'hero') : '',
      trapsAt.has(key) ? 'trapped' : '',
    ].filter(Boolean).join(' ');
    const mark = unit
      ? unit.kind === 'closeCombat' ? 'V' : unit.kind === 'ranged' ? 'R' : 'T'
      : trapsAt.has(key) ? '×' : '';
    const animation = unit ? animationFor(unit) : 'idle';
    const portrait = unit && portraitFor(unit);
    const characterAnimation = animation === 'idle' || animation === 'walk'
      ? animation
      : animation === 'hurt'
      ? 'hurt'
      : animation === 'special'
      ? 'special'
      : 'attack';
    const sprite = portrait
      ? el('span', {
          class: `tvrpg-sprite character-sprite character-${characterAnimation}`,
          role: 'img',
          'aria-label': unit.name,
          style: `background-image:url('${portrait}')`,
        })
      : null;
    if (sprite && characterAnimation !== 'idle' && characterAnimation !== 'walk') {
      sprite.addEventListener('animationend', () => {
        sprite.classList.remove(`character-${characterAnimation}`);
        sprite.classList.add('character-idle');
      }, { once: true });
    }
    return el(
      'div',
      { class: classes, 'data-cell': key },
      unit ? (sprite || el('span', { class: 'tvrpg-sprite' }, mark)) :
        trapsAt.has(key) ? el('span', { class: 'tvrpg-trap' }, mark) : '',
      unit ? el('small', { class: 'tvrpg-hp' }, `${unit.hp} HP`) : '',
      damage && damage.x === tile.x && damage.y === tile.y
        ? el('strong', { class: 'tvrpg-damage' }, `−${damage.damage}`)
        : ''
    );
  });

  const roster = table.units.map((unit) => {
    const percent = Math.max(0, Math.round((unit.hp / unit.maxHp) * 100));
    return el(
      'div',
      { class: `tvrpg-unit ${unit.owner === '__ai__' ? 'enemy' : 'hero'}` },
      el('span', { class: 'tvrpg-unit-name' }, `${unit.name}${unit.owner === '__ai__' ? '' : ` · ${nameOf(lobby, unit.owner)}`}`),
      el('span', { class: 'tvrpg-unit-stats' }, `${unit.hp} HP · ${unit.energy} energy · Move ${unit.movement}`),
      el('div', { class: 'tvrpg-health-bar' },
        el('span', { style: `width:${percent}%` })
      )
    );
  });

  const turnName = table.turn ? nameOf(lobby, table.turn) : 'Battle';
  const title = table.winner
    ? table.winner === '__ai__' ? 'AI victory' : 'Mission complete'
    : `${turnName}’s turn`;
  const map = el('div', { class: 'tvrpg-map' }, ...cells);
  const mapWidth = table.width || 40;
  const mapHeight = table.height || 30;
  const cellSize = Math.min(
    window.innerWidth * 0.88 / mapWidth,
    window.innerHeight * 0.72 / mapHeight,
  );
  map.style.gridTemplateColumns = `repeat(${mapWidth}, ${cellSize}px)`;
  map.style.gridAutoRows = `${cellSize}px`;
  const viewport = el('div', { class: 'tvrpg-viewport' }, map);
  const event = damage
    ? `−${damage.damage} HP · ${damage.targetHp} HP remaining`
    : `Round ${table.round} · ${table.traps.length} traps placed`;

  if (table.lastAction && Number.isInteger(table.lastAction.x) && Number.isInteger(table.lastAction.y)) {
    requestAnimationFrame(() => {
      const target = map.querySelector(`[data-cell="${table.lastAction.x},${table.lastAction.y}"]`);
      if (target) target.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'center' });
    });
  }

  return el(
    'div',
    { class: 'game tvrpg-game' },
    el('div', { class: 'tvrpg-heading' },
      el('h2', {}, 'TACTICAL VOXEL RPG'),
      el('div', { class: 'status' }, title),
      el('div', { class: 'log' }, event)
    ),
    viewport,
    el('div', { class: 'tvrpg-roster' }, ...roster)
  );
});
