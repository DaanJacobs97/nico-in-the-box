'use strict';

// Shared screen for Nico in the Box. Connects to the host's read-only
// /display WebSocket and redraws the lobby, the game table or the result
// from each `display` message. Games add a renderer with
// NicoDisplay.register(gameId, (table, lobby, ui) => element).
//
// Everything is built with DOM calls and text nodes, never by parsing HTML
// strings, so nicknames and room names can't inject markup.
const NicoDisplay = (() => {
  const app = document.getElementById('app');
  const renderers = {};
  let state = null;
  let roomClosed = false;
  let retryTimer = null;

  /** Creates an element: el('div', {class: 'x'}, 'text', childElement). */
  function el(tag, attrs, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
      if (value === undefined || value === null || value === false) continue;
      if (key === 'class') node.className = value;
      else node.setAttribute(key, value);
    }
    for (const child of children.flat()) {
      if (child === null || child === undefined || child === false) continue;
      node.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return node;
  }

  function nameOf(lobby, playerId) {
    const player = (lobby.players || []).find((p) => p.id === playerId);
    if (player) return player.nickname;
    if (playerId === lobby.hostId && lobby.hostName) return lobby.hostName;
    return '?';
  }

  const ui = { el, nameOf };

  function show(...children) {
    app.replaceChildren(...children);
  }

  function message(title, text) {
    show(el('div', { class: 'center' }, el('h1', {}, title), el('p', { class: 'muted big' }, text)));
  }

  function renderLobby({ lobby, gameName, rules }) {
    const chips = el('div', { class: 'chips' });
    for (const p of lobby.players) {
      const icon = p.away ? '📵' : p.id === lobby.hostId ? '🏆' : p.web ? '🌐' : '👤';
      chips.append(el('span', { class: p.away ? 'chip away' : 'chip' }, icon, ' ', p.nickname));
    }
    for (let i = lobby.players.length; i < lobby.max; i++) {
      chips.append(el('span', { class: 'chip free' }, 'Free seat'));
    }
    return el(
      'div',
      { class: 'center' },
      el('h1', {}, lobby.room),
      el('h2', {}, gameName || lobby.game),
      rules && rules.length ? el('p', { class: 'big' }, rules.join('  ·  ')) : '',
      chips,
      el(
        'p',
        { class: 'muted big' },
        'Join on your phone: open Nico in the Box, tap Join a game and pick "',
        lobby.room,
        '".'
      ),
      el('p', { class: 'muted' }, 'No app? Open ', location.host, '/play in a browser.')
    );
  }

  function render() {
    if (!state) return;
    const { lobby, game, table, result } = state;
    const renderer = renderers[game];
    if (lobby.phase === 'lobby' || !table || !renderer) {
      show(renderLobby(state));
      return;
    }
    const view = renderer(table, lobby, ui);
    if (result) {
      show(
        view,
        el(
          'div',
          { class: 'result' },
          el('div', { class: 'big' }, '🎉 ', result.summary || ''),
          el('div', {}, 'Waiting for the host…')
        )
      );
    } else {
      show(view);
    }
  }

  function connect() {
    clearTimeout(retryTimer);
    const socket = new WebSocket(`ws://${location.host}/display`);
    socket.onmessage = (event) => {
      let msg;
      try {
        msg = JSON.parse(event.data);
      } catch (_) {
        return;
      }
      if (msg.type === 'display') {
        roomClosed = false;
        state = msg;
        render();
      } else if (msg.type === 'closed') {
        roomClosed = true;
        state = null;
        message('Nico in the Box', 'The room was closed. Waiting for a new one…');
      }
    };
    socket.onclose = () => {
      if (!roomClosed) {
        state = null;
        message('Nico in the Box', 'Connection lost. Reconnecting…');
      }
      retryTimer = setTimeout(connect, 2000);
    };
  }

  // Full screen on demand; a TV browser usually has its own control too.
  const fullscreen = document.getElementById('fullscreen');
  fullscreen.addEventListener('click', () => {
    if (document.fullscreenElement) document.exitFullscreen();
    else document.documentElement.requestFullscreen().catch(() => {});
  });

  connect();

  return {
    register(gameId, renderer) {
      renderers[gameId] = renderer;
      render();
    },
  };
})();
