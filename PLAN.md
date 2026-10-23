# NicoInTheBox — Implementation Plan

A Jackbox-style LAN party game app in Flutter. One app does both jobs: it can **host** a room, or **join** one.
Platforms: Windows + Android first, with iOS as an untested stub.

## Decisions (confirmed)

| Topic | Choice |
|---|---|
| Flutter SDK | Official stable SDK cloned to `C:\src\flutter` and added to the user PATH |
| Clients | Every player runs this app, so all devices get a native UI |
| Discovery | UDP broadcast, plus manual IP entry as a fallback |
| Uno-style rules | Core rules (details below) |
| Host participation | The host joins its own room automatically as a player |
| Host view | The host sees the game plus a session-controls panel (details below) |
| Nicknames | The host and every player pick a nickname when entering a session |

## Host & nicknames

- **Auto-join:** when the host taps *Create room*, the server starts and the host's app connects to it straight away
  over loopback, using the host's nickname. There's no separate join step, and the host takes a player seat
  (e.g. one of the 2 Tic Tac Toe seats).
- **Host privileges come from the server.** The server marks the first loopback connection as `hostId`, and only that
  player's control messages are accepted. The UI just hides controls from everyone else, so the server's check is what
  actually enforces it.
- **Host session controls**, shown in a collapsible panel or app-bar menu that only the host sees:
  - Lobby:
    - *Start game*, enabled once there are at least `minPlayers`
    - *Kick player*
    - *Change game*, allowed only if the current players fit the new game's `maxPlayers`
    - *Close room*
  - In game:
    - *Restart game*: same players, new deal or board
    - *End game → lobby*
    - *Kick player*: this ends the round, then the host goes back to the lobby
    - *Close room*: disconnects everyone and returns them to the menu
  - Every destructive action asks for confirmation first.
- **Nicknames:**
  - Choosing one:
    - The host types their nickname on the host-setup screen.
    - A joining player types theirs in a dialog after picking a room from the scan list or entering an IP.
  - Rules:
    - 1–16 characters with surrounding spaces trimmed.
    - They must be unique within the room, ignoring case. If a name is taken, the server rejects the join
      with `nameTaken` and the dialog asks again. Duplicates are not silently renamed.
  - The last nickname used is saved on the device (`shared_preferences`) and pre-filled next time.
  - Everyone sees the nicknames in the lobby and in game, with the host marked by a crown.

## Recommendations (defaults unless you object)

1. **Host-authoritative server, and the host plays through loopback.** The host device runs the server and *also* connects
   to it as a normal client at `ws://127.0.0.1`. The host and remote players then share one code path, which leaves
   fewer bugs and nothing special to cheat with.
2. **No networking packages.** `dart:io` already provides `HttpServer` with a WebSocket upgrade, `WebSocket` and
   `RawDatagramSocket` on Windows, Android and iOS. This keeps dependencies small and avoids plugins that might not
   support Windows.
3. **Game logic is pure Dart, separate from the UI**, so it can be unit-tested without a device.
4. **Each player gets their own view of the game state.** The server never sends a player anyone else's cards.
5. **Call the Uno-style game "Color Clash"**, which avoids the Uno trademark.
6. **No reconnects in v1.** If a player drops mid-game, the game ends and everyone returns to the lobby.
   If the host closes the room, every client goes back to the menu. (Reconnects were added later; see
   *Feature: Reconnect after a short drop*.)
7. **State management:** `ChangeNotifier` + `ListenableBuilder` from Flutter itself; no state package needed at this size.
8. **Git:** the repo is `github.com/DaanJacobs97/nico-in-the-box` (private). Each milestone is committed to `main`.
   After the skeleton is pushed, work happens on feature branches merged through pull requests, with CI running
   `flutter analyze` and `flutter test`.

## Architecture

```
lib/
  main.dart
  app/            theme, routes
  net/
    protocol.dart        message types + JSON (de)serialization, protocol version
    game_server.dart     HttpServer -> WebSocket, room/lobby, routes actions to GameSession
    game_client.dart     WebSocket client, exposes ChangeNotifier state
    discovery.dart       UDP broadcaster (host) + listener/scanner (join)
    multicast_lock.dart  MethodChannel -> Android WifiManager.MulticastLock (no-op elsewhere)
  games/
    game_definition.dart  id, name, minPlayers, maxPlayers, createSession()
    game_session.dart     abstract: start(players), applyAction(pid, action), viewFor(pid), result
    registry.dart         list of available games
    tictactoe/            engine + widget
    color_clash/          engine + widget
  screens/
    home_screen.dart      [Host] [Join]
    host_setup_screen.dart  host nickname, room name, pick game (sets room size), create room -> auto-join
    join_screen.dart      live scan list + manual IP:port field -> nickname dialog
    lobby_screen.dart     players list with nicknames, host IP shown; host sees the controls panel
    game_screen.dart      shows the selected game's widget; host additionally sees the session-controls overlay
  widgets/
    host_controls.dart    host-only panel: start / restart / end game / kick / change game / close room
    nickname_dialog.dart  validation, pre-filled from shared_preferences
test/                     engine tests, protocol tests, in-process server+clients integration test
```

### Network details
- **Game port:** TCP 47800 (WebSocket at `/ws`). If 47800 is taken, the server tries the next few ports.
- **Discovery port:** UDP 47801. While the lobby is open, the host broadcasts once a second to `255.255.255.255`
  and to each interface's subnet broadcast address. The payload is
  `{"app":"nicobox","v":1,"room":"...","host":"...","game":"tictactoe","players":1,"max":2,"port":47800}`.
  The scanner lists every host it has heard from in the last 3 s and drops hosts that go quiet.
  Rooms that are full or already in a game are shown greyed out.
- **Messages** are JSON with a `type` field:
  - client → server: `hello{nickname, protocol}`, `action{...}`
  - host-only (the server checks the sender is `hostId`): `start`, `restart`, `endGame`, `kick{playerId}`,
    `changeGame{gameId}`, `closeRoom`
  - server → client: `welcome{playerId, isHost}`, `lobby{room, game, players[{id, nickname}], max, hostId}`,
    `gameState{view}`, `gameOver{result}`, `error{code, msg}`, `kicked`, `closed{reason}`
  - joins are rejected when the nickname is taken, the room is full, a game is running, or the protocol version
    doesn't match
- **The host's IP addresses** come from `NetworkInterface.list()` and are shown in the lobby, so other players can
  type one in manually.

### Platform setup
- **Android:** permissions `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE` and `CHANGE_WIFI_MULTICAST_STATE`,
  plus `usesCleartextTraffic="true"` (needed for `ws://`). A small Kotlin MethodChannel holds the multicast lock
  while scanning, because many phones drop broadcast packets without it.
- **Windows:** the first server start triggers a Windows Defender Firewall prompt. You need to allow it on
  *Private* networks, and I'll put a note about this in the lobby UI.
- **iOS (stub):** generated by `flutter create`. I'll add `NSLocalNetworkUsageDescription` to Info.plist.
  It isn't built or tested, because that needs a Mac. Real iOS broadcast later also needs Apple's multicast
  entitlement (`com.apple.developer.networking.multicast`).

## Games

**Tic Tac Toe:** exactly 2 players (the host plus one other). The host is X and moves first. The game detects a
win or draw. The host can then use *Restart game*, which starts a rematch where the players swap X and O.

**Color Clash (Uno-style, core rules):** 2–4 players.
- **Deck:** standard 108 cards. Each color has 0 ×1 and 1–9 ×2, plus Skip, Reverse and Draw Two ×2 each.
  There are also 4 Wild and 4 Wild Draw Four. Each player is dealt 7 cards.
- **Playing:** you can play a card that matches the top card's color, number or symbol, or any Wild.
  Playing a Wild means choosing a color.
- **Drawing:** if you draw, you draw 1 card. You may play it straight away if it's playable; otherwise your turn ends.
- **Action cards:**
  - Reverse acts as Skip when there are 2 players.
  - Draw Two and Wild Draw Four make the next player draw (and, with "Play after drawing a penalty" off, lose their
    turn).
  - With "Stack +2 and +4" on, the next player may answer instead: a +2 on a +2, or a Wild +4 on either. The
    total passes on until someone draws it all. A +2 can't go on a +4.
  - Both options are on by default. There are no Wild Draw Four challenges.
- **Last card:** press "Last card!" when you're down to one card. If another player catches you before you call it,
  you draw 2.
- **Deck refills:** when the draw pile runs out, the discard pile (minus its top card) is reshuffled.
- **Winning:** the first player to empty their hand wins the round.

## Milestones (each one ends with a commit)

1. ✅ **Toolchain:** install Flutter by cloning the official stable repository to `C:\src\flutter` (winget has no official package), then run `flutter doctor`. Fix anything it reports
   for Windows and Android, accepting Android licenses only with your OK.
2. ✅ **Scaffold:** in the repo root, run
   `flutter create --project-name nico_in_the_box --org com.daanjacobs97 --platforms=windows,android,ios .`,
   then add the lint rules in `analysis_options.yaml`.
3. ✅ **Core:** protocol, the GameSession interface and the game registry. Then the Tic Tac Toe engine with unit tests.
4. ✅ **Networking:** server, client and lobby, including host auto-join, nickname checks and the host-only commands.
   An in-process integration test covers:
   - a server and 2 clients playing Tic Tac Toe from start to finish
   - a duplicate nickname being rejected
   - a non-host `restart` being refused
   - a kick
   - closing the room
5. ✅ **Discovery:** UDP broadcaster and scanner, plus the Android multicast lock.
6. ✅ **UI:** home, host setup, join (scan + manual IP), the nickname dialog, the lobby, the host-controls panel, and
   the Tic Tac Toe screen.
7. ✅ **Color Clash:** engine with thorough unit tests (deck size, playability, every action card, reverse with 2
   players, reshuffle, the last-card rule), then its UI.
8. ✅ **Platform polish:** manifest and Info.plist entries, the firewall note, error handling (disconnects, full room,
   host leaving).
9. ✅ **Verification** (below), then a README with run instructions.

## Verification

- `flutter analyze` is clean and `flutter test` passes (engines, protocol, integration).
- `flutter build windows` succeeds. Then I run **two Windows instances side by side**: one hosts, the other joins
  through Scan and through manual `127.0.0.1`, and they play a full game of Tic Tac Toe and a 2-player game of
  Color Clash.
- `flutter build apk --debug` succeeds.
- **Limit:** an Android *emulator* sits behind NAT and won't see LAN broadcasts, so a real Windows ↔ Android LAN
  test needs your physical phone. I'll give you the steps to run it.

**Result (2026-10-14):** analyze is clean and 61 unit/integration tests pass. The Windows and Android debug builds
succeed. Instead of two Windows instances, the real app was driven on two physical devices (a Windows PC and an Android
10 tablet on the same Wi-Fi) by `integration_test/lan_play_test.dart`. Each run played two rounds of Tic Tac Toe
(marks swap), switched to Color Clash, played it to a winner, and closed the room:
- Windows hosts, the tablet joins by Scan: passed
- The tablet hosts, Windows joins by Scan: passed
- Windows hosts, the tablet joins by manual IP: passed

Two app bugs found this way and fixed:
- Closing a room told guests that the host had *left* rather than *closed* it.
- The closed notice could be lost because the server shut down before it was delivered.

## Out of scope for v1
Reconnecting after a drop, a browser join client (now planned below), more than one room per host, a polished iOS build, sound and
animations beyond the basics.

---

# Feature: Single game screen & browser join

**Status:** done; all 8 milestones merged. The device results are in the *Verification* section below.
Native-only LAN code moved to `packages/nico_native` so the host app and the Caster can share it.

**Changes made during milestone 4:**
- **One 3-way choice instead of two.** The host picks "Where is the shared screen?": *This device*, *A browser* or
  *Caster app*. *This device* is option B (the host takes no seat).
- **The host only sits out while the screen is on.** If the host switches Single game screen off, they get their seat
  back (`DisplaySettings.hostIsScreen` = enabled && !hostPlays).
- **The host's Start button is pinned to the bottom of the lobby.** The new settings card made the lobby long enough
  to push it off-screen.

The host can turn on a *shared screen*. The game table moves to one big screen everyone watches, and each player's
device only shows their own hand plus the buttons they need, Jackbox style.

As a fallback, someone who can't install or run either app can **join as a player from a regular browser**. They get
the same player screens, served by the host.

> **Note:** Flutter does *not* use a webview; native builds are compiled code that draws its own UI. Browser support
> therefore comes from a separate **Flutter web build** of the player screens, which the host serves as files.

## Decisions (confirmed)

| Topic | Choice |
|---|---|
| Where the shared screen runs | The host picks one of two sub-options: **Browser**, where the host serves a web page any browser can open, or **Caster**, a separate app the host connects to |
| Caster | A **separate Flutter app** (`caster/`) for Windows and Android (Android TV included), with an iOS stub |
| How the host finds a Caster | **The host picks a Caster**: Casters announce themselves on the LAN, and the host chooses one from a list or types its IP |
| Shared screen web page | **Lightweight HTML/JS** (best for smart-TV browsers), plus a **stub for a later Flutter web version** that uses the same data feed |
| Host's own device | **Host chooses**: (A) the host plays on their device as usual, or (B) the host's device *is* the shared screen and the host doesn't take a seat. Host session controls stay available either way |
| Browser players | Anyone can **join as a player from a browser**. The client is a **Flutter web build** (`web_client/`) that reuses the shared player widgets, so new games work in the browser automatically |

## Recommendations (defaults unless you object)

1. **One "display feed" for every kind of screen.** The server produces a single `display` message type, and the
   browser page, the Caster app and option B all consume it. Each game gets a new `tableView()` that holds only public
   information (no hands), so a shared screen can never leak cards.
2. **Reuse the existing server for everything web.** The game server on TCP 47800 already speaks HTTP. It also serves:
   - `/`: a tiny landing page with two big buttons, *Join as player* and *Show the shared screen*, so typing just the
     address always leads somewhere useful
   - `/play`: the Flutter web player client
   - `/screen`: the HTML/JS shared screen, with its read-only WebSocket at `/display`

   No second server is needed. Players' WebSocket stays at `/ws`, used by the apps and browser players alike.
3. **Extract shared code into a package first.** The protocol, game engines, display widgets and discovery code move
   to `packages/nico_shared`, which both apps depend on. Doing this first, as its own pull request, keeps the move
   reviewable and limits merge conflicts with your friend's work.
4. **Fall back to the full view when no screen is connected.** Players get the hand-only view only while at least one
   shared screen is connected. If the TV disconnects mid-game, players' devices show the full table again, so the
   game never becomes unplayable.
5. **Players keep a one-line status** ("Your turn" / "Waiting for Daan") above their hand, so nobody has to look up
   to know they're on.
6. **Tic Tac Toe's board is the input.** Players still see and tap the board on their device. The shared screen shows
   it larger, with names, whose turn it is, and the winning line.
7. **Caster accepts one host at a time.** A busy Caster is shown as *In use* in the host's list. The host can
   disconnect it from the lobby. The Caster keeps the screen awake (`wakelock_plus`).
8. **Protocol version 2.** All message changes ship together, so old app builds refuse new rooms with the existing
   "different app version" error.
9. **Keep the shared package web-safe.** `packages/nico_shared` must not import `dart:io`, because browsers don't have
   it. The client connects through `web_socket_channel`, which works on native platforms and the web. Hosting, the
   server, UDP discovery and the Caster stay in native-only code.
10. **Make the web build work without internet.** By default, Flutter web downloads its rendering engine (CanvasKit)
    from Google's CDN, which fails on an offline LAN. The client is built with `--no-web-resources-cdn` so everything
    is served by the host.
11. **QR code in the lobby.** Next to the host's addresses, the lobby shows a QR code for `http://<host-ip>:47800/play`.
    Someone without the app scans it with their phone camera and is in the nickname screen straight away.
12. **Browser players are full players.** They pick a nickname, take a seat, can be kicked, and get the compact view
    when a shared screen is on. The lobby marks them with a small browser icon. Host controls exist only in the native
    app, since a browser can't host.

## User flows

**Host setup / lobby:**
- New *Single game screen* switch, changeable in the lobby until the game starts.
- When it's on, the host chooses:
  - **Screen:** *Browser* or *Caster*.
  - **Host's device:** *I'm playing* (A) or *This device is the screen* (B). In B the host takes no seat, so Tic Tac
    Toe would need two other players.
- **Browser:** the lobby shows `http://192.168.0.156:47800/screen` (one line per LAN address) and how many browsers
  are connected.
- **Always shown, even with the shared screen off:** "No app? Join in a browser" with
  `http://192.168.0.156:47800/play` and its QR code.
- **Caster:** the lobby has a *Choose screen* list of Casters found on the network (name, IP, *Available*/*In use*),
  plus *Enter IP* as a fallback. When one is connected, it shows with a *Disconnect* button.
- *Start game* shows a warning (but still works) when the shared screen is on and no screen is connected yet.

**Shared screen (browser, Caster, or host device in B):**
- **Lobby:** room name, game, the player list with the host's crown, free seats, and "Open *Nico in the Box* →
  Join → *room name*".
- **In game:** the table:
  - Tic Tac Toe: large board, X and O names, turn, winning line.
  - Color Clash: every player with card count and *LAST!* badge, the top card and active color, direction, draw-pile
    count, the move log, and a highlight on the current player.
- **Result:** a winner banner until the host restarts or returns to the lobby.
- **Room closed:** "The room was closed". The Caster then returns to its idle screen.

**Player devices (while a screen is connected):**
- Tic Tac Toe: status line plus the board.
- Color Clash: status line, the hand (playable cards lifted), and the *Draw*, *Pass*, *Last card!* and *Catch* buttons.

**Browser player (fallback):**
1. They scan the QR code or type `http://<host-ip>:47800`, then tap *Join as player*. Scanning for rooms isn't
   possible in a browser, so the address is how they find it.
2. They choose a nickname. The last one used is remembered in the browser, and a taken name asks again, exactly like
   the app.
3. They see the same lobby, game and result screens as app players. With the shared screen on, they get the compact
   view.
4. If the room is full, a game is running, or the host closes the room, they see the same message as app players and a
   *Try again* button.

**Caster app:**
- **Idle screen:** large text "Waiting for a host", the Caster's name (editable and remembered, defaulting to the
  device name), and its IP address(es).
- **When a host connects:** shows the display feed full-screen in landscape. It never needs input, so it works with a
  TV remote.

## Architecture

```
packages/nico_shared/          shared Flutter package (all three apps), WEB-SAFE: no dart:io
  lib/net/protocol.dart          (moved) + display/cast messages, protocol v2
  lib/net/game_client.dart       (moved) now on web_socket_channel (native + web)
  lib/games/...                  (moved) engines + player views
  lib/games/*/..._table.dart     NEW Flutter table widgets (used by Caster and option B)
  lib/screens/...                (moved) nickname dialog, lobby, session/game screens
lib/                           main app (host/join): native-only code stays here
  net/game_server.dart           + display feed, /display, static files for /, /play, /screen
  net/discovery.dart             (stays: UDP) generalized: room AND caster announcements
  net/caster_link.dart           NEW host → Caster outbound connection
  net/caster_scanner.dart        NEW listens for Caster announcements
  screens/...                    + single-screen options, screen picker, host display mode (B), QR code
lib/net/web_pages.dart         NEW tiny pages generated in code: landing at / and "not included" fallback
assets/display/                NEW HTML/JS shared screen, served at /screen
  index.html, app.js, style.css
  games/tictactoe.js, games/colorclash.js   one small renderer per game
assets/web_client/             GENERATED: copy of web_client's release build, served at /play (not committed)
web_client/                    NEW Flutter web app: browser player client
  lib/main.dart                  join by current URL → nickname → shared session screens
  README.md                      also holds the stub contract for a future Flutter web shared screen
tool/build_web_client.ps1|.sh  NEW builds web_client and copies the output into assets/web_client/
caster/                        NEW separate Flutter app (Windows, Android incl. TV, iOS stub)
  lib/main.dart, idle_screen.dart, display_screen.dart, cast_server.dart
```

### Engine and server changes
- `GameSession` gets a new `Json tableView()` that returns public state only. Its unit tests check it never includes
  a hand.
- The server keeps **room display settings**: `{enabled, target: browser|caster, hostPlays: bool}`, sent in every
  `lobby` message along with `displays: [{kind, name}]`.
- **Host without a seat (option B):** this is the room setting `hostPlays: false`, which the host changes with
  `setDisplay` in the lobby or passes when creating the room. The plan first had a `seat: false` field in the
  hello, but a room setting can be changed later. The host's connection keeps host rights but isn't seated. Room size
  and the reserved host seat follow `hostPlays`, and taking a seat back is refused when the room is full. The host's
  nickname still counts for uniqueness and is sent as `hostName`.
- **Display feed:** after every lobby or game change, the server builds one
  `display{lobby, game, table, result}` message and sends it to every display: browser sockets on `/display`, the
  connected Caster, and the host's own client in option B.
- **Player views:** `GameViewContext` gets a `sharedScreen` flag, which is true only while a display is connected.
  Each game's player widget then switches to its compact layout.

### Web routes on the host

| Path | Serves |
|---|---|
| `/` | Landing page with two buttons |
| `/play`, `/play/**` | Flutter web player client (`assets/web_client/`) |
| `/screen`, `/screen/**` | HTML/JS shared screen (`assets/display/`) |
| `/ws` | Player WebSocket (apps and browser players) |
| `/display` | Read-only shared-screen WebSocket |

- Every file comes from Flutter assets with the right content type, including `application/wasm` for the web
  engine. Every other path returns 404.
- The server ignores anything a browser sends on `/display`.

### Shared screen page
- `app.js` connects to `ws://<same host>/display`, draws the lobby, the table or the result from each `display`
  message, and reconnects every 2 s if the connection drops. Each game registers a renderer with
  `NicoDisplay.register('colorclash', render)`.
- **Flutter web stub:** the server's static files for the shared screen come through a small `DisplayFrontend`
  interface. `HtmlDisplayFrontend` is the only implementation for now. `web_client/README.md` describes the
  `/display` contract and how a `/screen` route inside the web client would later plug in as
  `FlutterWebDisplayFrontend`. Nothing is built yet.

### Browser player client
- `web_client/` is a Flutter web app that depends on `packages/nico_shared`. It reads the host from its own URL, so
  it needs no scanning or IP entry, then shows the shared nickname dialog, lobby and game screens.
- It's built with `flutter build web --release --base-href /play/ --no-web-resources-cdn`, so it works without
  internet. `tool/build_web_client` copies the output into `assets/web_client/`. The native host app must be built
  after this step. The generated folder is git-ignored, and CI builds it before analyzing and testing the main app.
- **Size budget:** at most **8 MB** zipped in the host app; CI fails if it grows past that. (The plan first said
  4 MB, but a real build is 40 MB raw: Flutter's web engine alone is 2–3 MB compressed per variant. The build
  script keeps only the two engine variants a non-wasm build can load, CanvasKit full and chromium, and drops
  debug symbols. That gives about 5.8 MB zipped. The host also gzips responses.)
- **Protocol:** the hello message gets an optional `client: "app"|"web"`, used only for the lobby's browser icon.
  Browser players follow exactly the same rules as app players.

### Caster connection
- **Announcements:** the Caster broadcasts on UDP **47802** every second:
  `{app: "nicobox-caster", v: 2, id, name, port, busy}`.
- **Its server:** the Caster runs a tiny WebSocket server on TCP **47803** at `/cast`.
- **Handshake:**
  - host → Caster: `castHello{protocol, room, host}`
  - Caster → host: `castWelcome` when it's free, or `error{code: casterBusy}` when another host is connected
- **Data:** the host then pushes the same `display` messages it sends to browsers. When the host disconnects or the
  room closes, the Caster goes back to its idle screen.
- **Android:** the Caster needs the same network permissions and multicast lock as the main app, and a *leanback*
  launcher entry so it appears on Android TV.

### Ports

| Port | Use |
|---|---|
| TCP 47800 | Game server and all web routes (`/`, `/play`, `/screen`, `/ws`, `/display`) |
| UDP 47801 | Room announcements (as today) |
| UDP 47802 | Caster announcements (new) |
| TCP 47803 | Caster WebSocket server (new) |

## Milestones (one stacked branch and pull request each)

1. **Shared package:** move the protocol, client, engines, game widgets and session screens to
   `packages/nico_shared` without changing any behaviour. Switch the client to `web_socket_channel` so the package
   is web-safe, and add a CI check that it compiles for the web. Update CI to analyze and test both packages. All
   existing tests pass unchanged.
2. **Browser join:** it doesn't depend on the shared screen, so the fallback ships early.
   - The `web_client/` app and the build script.
   - The `/`, `/play` and `/ws` routes, and the browser icon in the lobby.
   - The QR code and link in the host's lobby.
   - CI builds the web client and checks the size budget.
   - Tests: a server test that fetches `/play` assets with the right content types, plus a browser-player client test
     on the web platform.
3. **Table views and display feed:**
   - `tableView()` for both games, with privacy tests.
   - Protocol v2, the room display settings, and the host-without-seat option.
   - The `display` feed and `/display` socket.
   - Server tests covering browser displays, option B and the fallback when no display is connected.
4. **Player UI and host options:**
   - The compact player layouts and the status line, which browser players get automatically.
   - The single-screen switches in host setup and the lobby.
   - Option B: the host device shows the table using new shared table widgets.
5. **Browser shared screen:**
   - The `/screen` route, `index.html`, `app.js` and `style.css`, and both JS game renderers.
   - The URL and browser count in the lobby.
   - The `DisplayFrontend` interface and the stub contract in `web_client/README.md`.
   - A Dart test that fetches the page and reads the `/display` feed.
6. **Caster app:**
   - A `caster/` Flutter app for Windows, Android (with the TV launcher) and iOS stub.
   - Announcements, the `/cast` server, the idle and display screens, the name setting and the wakelock.
   - Tests for the handshake and the busy state.
7. **Host ↔ Caster:**
   - Caster scanner, *Choose screen* list, manual IP, connect and disconnect.
   - A notice when a Caster drops, with the automatic fall back to full player views.
   - Integration tests with a fake Caster.
8. **Verification on devices:**
   - **Browser player:** Windows hosts, the tablet's Chrome joins via the QR code, and a full Tic Tac Toe and Color
     Clash session is played with no app on the tablet. Then a mixed room: an app player plus a browser player in
     Edge on Windows.
   - **Browser screen:** Windows hosts with the shared screen in the tablet's browser, while Windows and the tablet
     play.
   - **Caster:** Windows hosts, the tablet runs the Caster, and the players are Windows plus a second device. Your
     phone can be the second device, or the Windows host in option A.
   - **Option B:** the tablet hosts as the screen and two Windows instances play.
   - The device test script gets a `SCREEN=browser|caster|host` setting. Browser players are driven with a small
     browser-automation script run against the tablet's Chrome.

## Verification
- `flutter analyze` is clean and `flutter test` passes in the root app, `packages/nico_shared`, `web_client/` and
  `caster/`.
- The web client builds with `--no-web-resources-cdn`, stays under the 8 MB budget, and loads on a host with no
  internet connection. To check this, unplug the router's internet uplink during the device test.
- Privacy test: for every game and every state reached by the random computer-played games, `tableView()` contains
  no card IDs from anyone's hand.
- Device runs for browser players and all three screen types, as in milestone 8. Each plays Tic Tac Toe and Color
  Clash to the end, checks that players get the compact view while a screen is connected, and pulls the screen
  mid-game to confirm the fall back to the full view.

**Result (2026-10-15).** The devices were a Windows PC and an Android 10 tablet on the same Wi-Fi. The second player
was the scripted bot in `tool/bot/lan_bot_test.dart`, which joins over the real protocol. All runs passed:

| Run | Host | Shared screen | Players | Games | Checked |
|---|---|---|---|---|---|
| R1 Browser player | Windows | none | Windows + **tablet Chrome** (web client) | Tic Tac Toe ×2 | Host saw an "In a browser" player; the browser got "host closed the room" |
| R2 Browser screen | Windows | **tablet Chrome at /screen** | Windows + bot | Tic Tac Toe ×2 + Color Clash | Host waited for the screen; both players in compact view; the table was live on the page (screenshot) |
| R3 Caster | Windows | **tablet Caster** | Windows + bot | Tic Tac Toe ×2 + Color Clash | Picked from *Choose screen*. **The Caster was force-stopped mid-Clash:** in the same second players got the notice and the full view, and the game finished |
| R4 Host is screen | **tablet** | the tablet itself | Windows app (joined by scan) + bot | Tic Tac Toe ×2 + Color Clash | The tablet showed the shared tables (screenshots) and kept the host controls; players were compact |

Offline loading was checked in milestone 2 through the browser's network log (every request went to the host) rather
than by unplugging the internet. **Not done on devices:** Color Clash *played from a browser*. The browser client
uses the same widgets as the app, which the widget tests cover, and its Tic Tac Toe sessions passed on desktop and
tablet browsers.

## Out of scope for this feature
- Hosting from a browser. Browsers can't open server sockets, so the host is always a native app.
- Finding rooms by scanning from a browser. Browser players use the address or the QR code.
- Installing the web client as an offline app (PWA) or serving it over HTTPS.
- Google Cast / Chromecast and AirPlay.
- More than one Caster per room. (Browsers can be several, since they're read-only.)
- Sound on the shared screen.
- A finished Flutter web display. Only the stub and its contract are in scope.

---

# Feature: Sea Siege (Battleship) and host-chosen game options

**Status:** done; milestones 1–3 merged (PRs #24, #25, #26), device verification passed (see *Verification*
below).

A Battleship-style game called **Sea Siege** (`seasiege`). Each player secretly places five ships on a 10×10 grid,
then players take turns firing at each other's grids. The first to sink the whole enemy fleet wins.

The host can choose whether a hit earns another shot. The system has no way for a host to pick game rules yet, so
this feature first adds **game options** that work for every game.

## Decisions (confirmed)

| Topic | Choice |
|---|---|
| Name | **Sea Siege**, id `seasiege` |
| Placing ships | **Both:** ships start in a random valid layout. Players can **Shuffle**, or tap a ship and then a cell to move it, and **Rotate** it. Then they press **Ready** |
| Players | **2**, with the engine built for a later **2–4 free-for-all** |
| After a hit | **The host decides:** strict turns (default), or *a hit earns another shot* |

## Recommendations (defaults unless you object)

1. **Game options are generic, not Sea Siege-only.**
   - A game declares its options on its `GameDefinition`. For now these are on/off switches: an id, a label, a
     one-line description and a default.
   - The host flips them in the **lobby**, under the game picker. Everyone else sees the active rules as text, and
     the shared screen's lobby shows them too.
   - Changing the game resets the options to that game's defaults.
   - The engine receives the chosen values when a session starts, so a restart keeps them.
   - Host setup stays as it is. Options live in the lobby only, where they can also change between games.
2. **Board and coordinates:** a 10×10 grid with columns A–J and rows 1–10, so a shot reads "D4".
3. **What's public:**
   - Every shot (hit or miss), whose turn it is, and who is still placing or ready.
   - Hits name the ship ("Hit! Cruiser"), as in your rules.
   - **A ship's position becomes public once it's sunk**, so the screen can draw it. Unsunk ships never leave the host.
   - The privacy test checks this at every move of 20 random games.
4. **Phases:**
   - **Placing:** players arrange their fleets privately. Ready locks a fleet, Unready unlocks it. The battle starts
     the moment every player is ready.
   - **Battle:** the first shooter alternates between rematches, as in Tic Tac Toe.
   - **Over:** the winner is the last player with ships afloat.
5. **The free-for-all stub:**
   - Every player has their own board, and a shot names its target (`{'type': 'fire', 'target': id, 'cell': n}`).
   - Turns skip players whose fleet is sunk, and the winner is the last fleet afloat.
   - With 2 players the target is simply the other player.
   - Turning on 2–4 later means: raise `maxPlayers`, add a target picker to the player view, lay out 3–4 boards on the
     table, and add tests. That isn't part of this feature.
6. **Player screens:**
   - **Placing:** your own ocean grid with your ships, plus Shuffle, Rotate and Ready.
   - **Battle:** the enemy grid on top (tap a cell to fire), with your own ocean grid smaller underneath, showing your
     ships and the shots fired at you.
   - **Compact mode** (a shared screen is on): both grids stay, because the enemy grid is the input and your ocean
     grid is private. The shot log and fleet status move to the shared screen.
7. **Shared screen** (Flutter and browser JS):
   - Both boards side by side, each showing hits, misses and sunk ships.
   - Whose turn it is, each fleet's remaining ships, and the last shots.
   - While players are placing, it shows who is placing and who is ready.
8. **The LAN bot learns Sea Siege:** it shuffles, readies and fires at random cells it hasn't tried. That lets me play
   a real session on one device plus the bot.
9. **Built from the generator** (`dart run tool/new_game.dart seasiege "Sea Siege" 2 2`), then the placeholder pieces
   are replaced. To stay under the file size cap, the engine is split into `seasiege_fleet.dart` (ships, geometry,
   random placement) and `seasiege_game.dart` (phases, turns, views). The UI is split into `seasiege_view.dart`
   (player) and `seasiege_table.dart` (shared screen and the grid widget both use).

## Milestones (one stacked branch and pull request each)

1. **Game options** (`feature/game-options`):
   - `GameOption` and `GameDefinition.options`; `createSession` gets the chosen values. Tic Tac Toe, Color Clash and
     the generator templates are updated, with no options of their own.
   - `LobbyState.gameOptions`, a host-only `setGameOptions` message (lobby phase only, validated), and the reset on
     `changeGame`. `kProtocolVersion` becomes 3.
   - The lobby switches for the host, a rules line for the others, and the rules on both shared-screen lobbies.
   - Tests:
     - protocol round trip
     - server: host-only, lobby-only, unknown or mistyped option rejected, reset on game change, values reach the
       session and survive a restart
     - lobby widgets for host and player
     - the registry check: every game's option ids are unique and each default is a valid value
2. **Sea Siege** (`feature/sea-siege`):
   - The engine, player view, Flutter table, JS table (with CSS) and registration. `kProtocolVersion` becomes 4.
   - Engine tests:
     - placement: in bounds, straight, no overlap; Shuffle always gives a valid fleet; Ready and Unready; no moves
       once ready
     - turns: out of turn rejected, a cell can't be shot twice, the first shooter alternates by round
     - hits, misses, the ship named on a hit, sinking (which reveals the ship)
     - both "after a hit" rules, and the win
     - 20 random games with the privacy check
   - Widget tests: select, move and rotate a ship; fire by tapping; compact view; the shared screen at TV size, while
     placing and in battle.
   - Docs: code map and the game guide's game list.
3. **Bot and device verification** (`feature/sea-siege-verify`):
   - The bot plays Sea Siege.
   - Device runs:
     - the Windows host plus the tablet app, once with each "after a hit" rule
     - the tablet's browser as the shared screen
     - a browser player on the tablet's Chrome
   - The results go into this plan.


## Verification

**Result (2026-10-15).** Devices: the Windows PC and the Android 10 tablet (SM-T590). All three runs passed.

| Run | Host | Shared screen | Players | Checked |
|---|---|---|---|---|
| V1 App vs app | Windows | none | Windows app + **tablet app**, both driven through the UI (`GAMES=sea`) | Two games, "Hit = shoot again" off then on. Both sides moved, rotated and shuffled, then readied; about 88 shots each per game; the turn rule held on all 351 shots it could check |
| V2 Browser screen | Windows | **tablet Chrome at /screen** | Windows app (compact view) + bot | Placing status, both boards with hits, misses and sunk ships, the shot log, and the "A hit earns another shot" line in game 2 (screenshots) |
| V3 Browser player | Windows | none | Windows app + **a person in the tablet's Chrome** (`/play/`) | The host saw "In a browser"; two full games, one with each setting, then the room closed |

**The tablet's Wi-Fi dropped every 10–30 seconds** during testing (−49 dBm, same network; Android logged a disconnect and
reconnect each time). Every drop ended the tablet player's session, in Tic Tac Toe as well, so the cause was the
link rather than Sea Siege. The runs above therefore went through a USB tunnel (`adb reverse tcp:47800 tcp:47800`,
joining `127.0.0.1`). This tests the real app and browser on the tablet, but not finding rooms over the LAN, which
was verified in earlier features. Surviving such drops needs **reconnect support**, which is proposed as its own
feature.

The Windows test also exposed a test bug: with Single game screen on, the host setup form is taller than the test
window, so the *Create room* tap missed. The test's tap helper now scrolls its target into view first.
## Out of scope for this feature
- Playing 3–4 players (only the engine stub is included).
- Option types other than on/off switches, such as number pickers or choice lists.
- Dragging ships. You tap to select, tap to move and press Rotate, which works the same with a mouse, touch and in
  browsers.
- Sounds or animations for hits and sinking.
- Computer opponents in the app (the LAN bot is a test tool).

## Follow-up: easier ship placement

**Status:** done, merged (PR #27). Verified on the Windows PC and the tablet (both sides used tap-to-move, Rotate,
double-tap, drag, Shuffle and Ready, then played two games). Feedback from playing V3: placing and turning ships felt awkward, and moves often landed
on invalid squares.

**Decisions (confirmed):**
- **Double-tap a ship to turn it.** It turns around the square you tapped. If the turned ship doesn't fit, it's
  **nudged** to the nearest spot where it does. If there's no room nearby, it stays put and the hint line says so.
  The Rotate button does the same for the selected ship, turning it around its middle.
- **Drag ships, with a live preview.** Grab any part of a ship and drag. A ghost shows where it will land, green
  when valid and red when not. Dropping on red snaps it back, so an invalid placement never reaches the server.
- **Tap a ship, then a square still works,** and now nudges too instead of failing.
- **A new PR stacked on #26,** so the open Sea Siege PRs don't change.

**How:**
- All client side; the engine and protocol don't change.
- `seasiege_fleet.dart` gains `Ship.fromJson`, `rotatedAround(cell)` and `nudgeToFit(others)`.
- `SeaGrid` handles gestures for the whole board (tap, double-tap, drag), maps positions to squares, and draws the
  preview.
- Tests:
  - unit tests for turning and nudging
  - widget tests for double-tap turning (including nudging), dragging to a valid square, and dropping on an
    invalid square, which sends nothing
  - the device test drags a ship too

**Found while building it:**
- A drag reported the square where Flutter *recognised* the drag, not where the finger first touched, so grabbing
  a ship could miss it. The board now uses the touch-down square.
- Flutter only starts a touch drag after about 36 px, more than a whole square on a phone, so one-square drags did
  nothing. The board scales that threshold to the square size.
- On a device, single taps only count once the double-tap window has passed in real time; the device test now
  waits for real.

---

# Feature: Reconnect after a short drop

**Status:** built on `feature/reconnect` (PR #29); a light device check passed (see *Verification*). Revisit after real games with people if reconnecting misbehaves.

During the Sea Siege device tests the tablet's Wi-Fi dropped every 10–30 seconds for about 4 seconds. Each drop
ends the player's session for good: the 5 s WebSocket ping times out, `GameServer._onDisconnect` removes the player
and a running game ends ("Ann left. The game was ended."). The goal: **a player (app or browser) who loses the
connection briefly gets back into the same seat and the same running game, without doing anything.**

## Decisions (confirmed)

| Topic | Choice |
|---|---|
| How long a seat is kept | **60 s.** A blip is about 4 s, plus up to 10 s before the ping notices. 60 s also covers a phone screen that locks or a browser tab switched away for a moment |
| Browser page reload | **Not in this feature.** The resume token lives in memory, so Wi-Fi drops and a backgrounded tab are covered, but a reload asks for a nickname again (and gets "name taken" until the seat expires). Keeping the token in `sessionStorage` is a small follow-up |
| What the others see | A notice ("Ann lost connection. Waiting up to 60 s…"), a reconnecting mark next to their name in the lobby and on the shared screen's lobby, a notice when they're back, and today's notice when the seat expires. The game just waits: every game is turn-based or waits for everyone (Sea Siege placing), so no game code changes. The host can still kick an away player or end the game |
| What the player who dropped sees | A **"Reconnecting…" banner** with a **Leave** button; the game is greyed out and not tappable, so no move seems to go through and then vanishes. After the seat expires: home with "Lost connection to the room.", as today |

## Recommendations (defaults unless you object)

1. **Only unexpected drops keep the seat.** Pressing Leave sends a new `leave` message first, so a deliberate exit
   still frees the seat at once ("Ann left."). Kicks, the room closing and the host leaving work as today.
2. **The host doesn't get a grace period.** The host's own client talks over loopback and won't blip; if it goes,
   the room closes as today.
3. **Resume tokens.**
   - `welcome` gives each player a random secret `resumeToken` (16 bytes, like `hostToken`) and the grace period
     (`graceMs`, in milliseconds so tests can use short ones). Only that player ever receives it; the host gets
     none.
   - `hello` may carry `resume: <token>` instead of a nickname. If a seat with that token is waiting (or still
     looks connected, see 4), the server reattaches it: same player id, nickname and token. It answers with
     `welcome` (same id), the lobby, and, during a game, that player's own `gameState` (and
     `gameOver` if the game finished meanwhile).
   - Wrong or expired token, or a kicked player: `error{resumeFailed}`, and the client goes home.
   - Resuming skips the "game in progress" and "room full" checks, since the seat is already theirs.
4. **A resume replaces a connection the server hasn't noticed is dead yet.** The client often notices the drop
   before the server's ping does. The old connection is then closed quietly, without counting as a disconnect.
5. **During the grace period** the seat stays in `players` (the game, seat count and nickname check all see it),
   messages to it are skipped, and its private view is rebuilt on resume, so nothing is queued.
6. **Client.** `GameClient` keeps the server address and token. On an unexpected close it sets `reconnecting`
   (instead of `disconnectReason`), notifies, and retries every 2 s until it gets back in or the grace period is up.
   Actions sent meanwhile are dropped (the UI blocks them anyway). `SessionScreen` shows the banner. The web client
   uses the same code, so browsers get it for free.
7. **Browsers and silent drops.** A browser can't see WebSocket pings, so it may not notice a dead link on its own.
   Chrome on Android closes sockets when the network changes, which covers the case we saw. If the device test shows
   a browser hanging instead, the server adds a small `ping` message every 5 s and the client treats 10 s of silence
   as a drop.
8. **Tests use short timers.** `GameServer` takes the grace period and `GameClient` the retry interval as
   parameters, so tests run in milliseconds over real loopback sockets.
9. **File size.** `game_server.dart` is at 591 of 600 non-blank lines, so seat bookkeeping (`_Connection`, seats,
   grace timers, resume) moves to a new part file `lib/net/player_seats.dart`.
10. **Protocol:** `kProtocolVersion` becomes 5 (`welcome.resumeToken` and `graceMs`, `hello.resume`,
    `PlayerInfo.away`, `Msg.leave`, `ErrorCode.resumeFailed`).

## Milestones

One branch and pull request, `feature/reconnect`, with the device results added before you merge:

1. **Server and protocol:** seats with grace timers, resume, `leave`, the away mark, notices; split into
   `player_seats.dart`.
2. **Client and UI:** reconnect loop in `GameClient`, banner in `SessionScreen`, away mark in the lobby list and the
   shared screens (Flutter and `assets/display/app.js`).
3. **Docs:** code map, protocol cheat sheet, this plan; the "No reconnects in v1" line above points here.
4. **Device verification** (results go into this plan).

## Verification

- **Server tests** (`test/net/reconnect_test.dart`, real loopback):
  - a drop mid-game keeps the seat; others get the notice and the away mark; resume within the grace period gets the
    same id and that player's own private view (Sea Siege fleet), and the game goes on
  - expiry: after the grace period the player is removed and the game ends, as today
  - a wrong token is rejected; a kicked player's token is rejected; `leave` frees the seat at once
  - resuming while the old connection still looks open replaces it
  - the nickname stays taken while the seat waits; a resume works even when the room is full or a game is running
- **Client and widget tests:** the client reconnects on its own after the server drops its socket; it gives up with
  `connectionLost` after the grace period or on `resumeFailed`; `SessionScreen` shows the banner, blocks the game and
  hides it again on resume; the lobby shows the away mark.
- **Protocol round trip** for the new fields; `tool/check.ps1` passes.
- **Devices** (Windows host + tablet, over the tablet's real Wi-Fi, no USB tunnel):
  - the tablet app plays Tic Tac Toe and Sea Siege through several real drops
  - the same with the tablet's Chrome as a browser player
  - airplane mode on for longer than the grace period: the seat expires and the game ends cleanly

**Result (2026-10-15).** Windows host app + the tablet (SM-T590) over its real Wi-Fi, no USB tunnel. A logcat watcher
showed the tablet dropping Wi-Fi for about 4 s at a time, often switching between two access points.

| Run | Result |
|---|---|
| Tablet app | No Wi-Fi drop happened during this run, so reconnecting was not exercised on the app (the loopback tests cover it) |
| Tablet Chrome (`/play/`) | The log showed five drops in about 90 s around this run. One visibly broke the connection: the browser showed *Reconnecting…*, the host got the notice, and the player was back in the same game. The others went unnoticed (the connection seems to have survived them) |
| Seat expiry, Leave | Not run on devices (covered by the server tests) |

The user judged this enough for now and will revisit after playing real games with people. Found along the way:
`flutter run --release` on Android fails because the `integration_test` plugin is registered but not packaged in
release builds, so the device run used a debug build.

## Out of scope for this feature

- Surviving a browser reload or an app restart.
- The host reconnecting, or handing the room to another player.
- Continuing a game without a player whose seat expired.

---

# Release builds (demo builds of every app)

**Status:** done. All four milestones merged; the `v0.3.1-rc1` dry run passed (downloads installed and started on
Windows and the tablet, icons shown), and v0.3.1 is the first release with downloads.

Ship installable builds of each app for a tagged version, so people can try Nico in the Box without a development
setup.

| File | Platform |
|---|---|
| `NicoInTheBox-<version>-windows.zip` | Windows: host and join app |
| `NicoInTheBox-<version>-android.apk` | Android: host and join app |
| `NicoCaster-<version>-windows.zip` | Windows: shared-screen app |
| `NicoCaster-<version>-android.apk` | Android and Android TV: shared-screen app |

The browser client isn't a separate download: the host app serves it, so it's built first and bundled. iOS needs a
Mac and is still a stub, so it isn't included.

## Decisions (confirmed)

- **One Android release key for both apps,** created by the owner and kept outside the repository. CI reads it
  from repository secrets; locally a git-ignored `key.properties` at the repo root points at it. Builds without it
  fall back to the debug key with a warning.
- **Collaborators only:** builds are published as a GitHub Release on the private repository, so only people with
  access to it can download them.

## Milestones

1. **Signing:** both Android apps sign release builds with the release key (environment variables in CI,
   `key.properties` locally, debug fallback otherwise); README *Release builds* section.
2. **App icons:** distinct icons for the app and the Caster, so they can be told apart on phones and TVs.
3. **Release workflow:** on a `v*` tag, GitHub Actions builds the browser client, then both apps for Windows
   (with the Visual C++ runtime DLLs in the zip) and Android, verifies the APK signatures, and attaches the four
   files to a draft release with the changelog section and install notes (Windows SmartScreen, Android unknown
   sources, firewall).
4. **Dry run:** a `-rc` tag; install and play from the downloaded files on Windows and the tablet before the real
   release (0.3.1, since the icons and signing land after the `v0.3.0` tag).

## Follow-up: Sea Siege visuals

**Status:** built on `feature/seasiege-visuals`; PR held back until the owner has nothing more to add.

**Request:** on the shared screen, stack the grids in portrait and put them side by side in landscape, show the
host's grid first, animate the water, and draw sprites for every ship type.

**Decisions (confirmed):**
- **Sprites appear for players too:** your own fleet is drawn as ships while placing and in battle. The shared
  screen still shows only sunk ships, as wrecks, so nothing secret leaks.
- **One source of art:** `paintShip` in `seasiege_sprites.dart` draws each ship with plain shapes. Flutter paints
  it directly, and `tool/sprites/` exports PNGs from it for the browser screen.
  `test/games/seasiege_sprites_test.dart` fails if the PNGs fall behind the painter.
- **Subtle animated water:** a slow shimmer and drifting wave lines (a `CustomPainter` in Flutter, CSS
  backgrounds in the browser). First on the shared screen only; after the tablet test the owner asked for it on
  players' boards too (app and browser client), moving like the screen. It stops when the system asks for reduced
  motion.
- **No "Afloat" list on the shared screen** (owner's request after the tablet test); the boards and the shot log
  say enough.
- **Layout follows the space the table actually has,** not the device orientation: wider than tall puts the boards
  side by side. When the host's device is the shared screen, the host has no board and join order stays.
- **The Caster may turn:** it used to lock itself to landscape on Android and iPad, so a tablet Caster never showed
  the stacked layout. TVs are landscape anyway.
- **Both boards are always the same size.** On the tablet Caster, a wrapped "Afloat" line made one board smaller.
  The line is gone now, and a widget test checks both boards match at many widths.

**Verified on the tablet** (Samsung SM-T590, USB tunnel, scripted second player, both rule settings):
- **Chrome `/screen/`:** side by side in landscape, stacked in portrait, host first. The water moves, and wrecks
  show both horizontal and vertical.
- **Release-signed Caster from this branch:** a full run in landscape passed both games. After the lock was
  removed, the Caster turned to portrait and showed the stacked layout and wrecks (screenshots). That run then
  failed: the tablet's Wi-Fi re-associated, the Caster dropped, and later it was no longer found by scanning. That
  issue is unrelated and is to be looked at separately.

### Second round: players' layout, turn cue, shot toasts

**Request:** stack or place side by side on the players' screens too, make it clearer whose turn it is, and replace
the shot feed at the bottom with disappearing messages in an overlay, so the boards keep their size. The messages
must not cover squares a player can tap.

**Decisions (confirmed):**
- **Players' battle screen:** side by side in landscape (enemy left, yours right, the same size), stacked in
  portrait as before. Placing is unchanged.
- **Turn cue:** the board being fired at glows gold with a crosshair by its title, and the other board dims.
  - **Shared screen:** a gold banner says "Ann is firing at Bob's fleet".
  - **Your device:** "Your turn: fire!" pulses. While you wait it says "Bob is aiming at your fleet".
  - **Free-for-all:** with more than one fleet left to pick from, nothing glows.
- **Toasts over the board that was hit,** fading after 3 s, with the square flashing for the first second.
  - On your device during your turn, toasts move over your own board.
  - Dimming never fades a toast.
  - Compact mode (a shared screen is on) shows no toasts on players' devices.
  - Shots already fired when a screen opens are not replayed.
- **Shot numbers:** each log entry gets `n` so screens can tell new shots from old ones. Protocol 6.
- **The browser screen is rebuilt on every update,** so it remembers what it has seen and keeps each toast's
  timing with a negative animation delay.

## Follow-up: keep the screen on while in a room

**Status:** done. Apps keep the screen on; browser players get a lobby tip (option 1 of 3, chosen by the owner).

**Decisions (confirmed):**
- **Scope:** the screen stays on for the whole time you're in a room: lobby, game and results.
  - `ScreenAwake` moved to `nico_shared`, and `SessionScreen` holds it.
  - The host already held it through `HostedRoom`; the counter handles both holds.
- **Browsers where supported.** The same code runs in the browser client.

**Verified on the tablet:**
- **App:** a screen wake lock for the app was taken when joining and dropped after leaving.
  - Waiting out the timeout couldn't prove anything: the tablet has "Stay awake while charging" on and was
    plugged in.
- **Browser (Chrome, `http://192.168.0.156:47800/play/`):** no wake lock.
  - The page isn't a secure context, so `navigator.wakeLock` is missing.
  - wakelock_plus then falls back to a hidden looping video (NoSleep.js). Its data-URI video loads its metadata
    but never decodes a frame (`readyState` 1, `currentTime` stuck at 0). Chrome doesn't count it as playing,
    even when added to the page at 300 px.
- **Browser outcome (owner's choice of three):**
  - **Chosen:** browser players see a tip in the lobby ("Your screen may lock while you wait…"). The wake lock
    call stays in place, so it starts working by itself if the host ever serves HTTPS.
  - **Not chosen:** our own looping video, whether Chrome honours it is uncertain; HTTPS with a self-signed
    certificate, which shows a full-page warning to every browser player.

## Follow-up: Color Clash update

**Status:** done. The owner played it on the Windows app and the tablet (app and Caster) from release builds of
this branch: "works great".

**Request:** new art for Wild and Wild +4, players' screens use all their space when a shared screen is on,
swipe a card up to play it, and two options: stacking +2 and +4, and keeping your turn after drawing one (both
on by default).

**Decisions (confirmed):**
- **Wild art:** a 2×2 grid of the four colors; Wild +4 adds a white "+4". On the pile the chosen color's
  square stays bright and the others fade, and the border keeps the chosen color. Same in the browser screen.
- **Stacking:** a +2 or +4 becomes a pending `penalty` (in the table view) for the next player. They may stack
  a +2 on a +2 or a Wild +4 on either (a +2 can't go on a +4), or draw the whole total.
- **Play after drawing a penalty** covers +2, +4 and a stacked total: the drawer then takes a normal turn.
- **The engine's options default to off;** only the game definition turns them on. So the original engine
  tests still check the classic rules, and the random bot games run every combination.
- **Compact player screen:** a status line with a small top card, the active color and any penalty, the buttons,
  then the hand as a fan of large cards. Cards shrink until the fan fits the width (down to 60 px), and only a
  bigger hand than that scrolls.
- **Swipe to play:** a playable card follows the finger on a vertical drag and plays when let go above 45% of a
  card's height (or flicked up); otherwise it springs back. Tapping still works. Sideways drags are left to the
  hand's scrolling. A Wild still asks for a color, and backing out returns the card.

# Automatic protocol version

**Problem:** two branches that both bump `kProtocolVersion` from 5 to 6 merge silently, because Git sees the same
edit on both sides. Builds with and without the second branch's changes would then both claim protocol 6 and
connect, then misbehave. This came up with a friend's game branch started before #35 (which went to 6).

**Decisions (confirmed):**
- **Nobody edits the number.** Every PR into `main` gets main's version + 1, even docs-only ones; the owner tests
  with release builds or builds from one branch, so that costs nothing.
- **No tokens or secrets.** The "Set protocol version" workflow commits to the PR's own branch, never to `main`,
  so the branch protection holds.
  - Pushes with the built-in token don't start other workflows, so it then starts CI with `workflow_dispatch`, the
    one kind of run that token may start.
- **Safety net:** the CI job "Protocol version" (`tool/protocol_version.dart check`) must be a required check on
  `main`. It catches fork PRs (their branch can't be pushed to) and failed runs, and says which number to set.
- **Branch protection on `main`:** "Require branches to be up to date before merging" is on, so the number is
  always worked out against the newest `main`.

**Known costs:**
- **`git pull` after the bot's commit** before pushing again.
- **Rare conflict:** if two PRs merge while a third is open, updating the third conflicts on the version line.
  Either side will do; the workflow then sets the right number.
- **"Awaiting approval" runs:** GitHub also creates `pull_request` runs for the bot's commit and holds them for
  approval. They aren't needed (the started CI run covers the commit) and don't block merging. Approving them just
  runs CI again, and the workflow finds the number already right.

**Not covered:** a changed message shape is no longer detected separately. It doesn't need to be, since every PR
bumps anyway.

# Serve game art from the host

**Status:** built on `chore/serve-game-art`. Checked with a real browser against a host serving the real
browser client and asset bundle (art at both URLs, 404 for missing files). The tablet test was skipped at the
owner's request.

**Problem:** art a game draws with `Image.asset(..., package: 'nico_shared')` lives in `packages/nico_shared/assets/`,
so it is packed into the browser client (`assets/generated/web_client.zip`), which every host app carries and CI caps
at 8 MB. Tactical Voxel RPG's 8.2 MB of art took the zip to 14.3 MB; shrinking it bought about 400 KB of room, not
enough for the next sprite game. The browser screen also has its own copy under `assets/display/games/<id>/`, so the
host app carries each game's art three times.

**How it works today:**
- Flutter web doesn't compile assets into the code. It fetches each one over HTTP when first drawn, from
  `assets/<asset key>` under the base href, so `/play/assets/packages/nico_shared/assets/…` for game art.
- The host app already bundles the same files under the same keys (`packages/nico_shared/assets/…`), because it
  depends on `nico_shared`. So does the Caster.

**Decisions (confirmed):**
- **The host serves game art; the zip leaves it out.** No change to game code: `Image.asset(..., package:
  'nico_shared')` keeps working in apps, the Caster and browsers alike. App players and the Caster keep their
  bundled copy, so they don't depend on the network for art.
- **One copy for the browser screen too:** the `/screen/` page loads the same files from the host, and
  `assets/display/games/<id>/` no longer holds copies of game art.
- **Tactical art stays shrunk.** `docs/ADDING_A_GAME.md` gets a guideline for art sizes.
- **Built now,** since the Tactical PR (#38) is merged.

## Steps

1. **Leave `nico_shared`'s assets out of the zip.** Both `tool/build_web_client` scripts skip
   `assets/packages/nico_shared/`. The browser client's `AssetManifest` still lists them, so lookups work; only the
   bytes come from the host. CI checks the zip has no such entries, next to the size budget (which stays, now for
   code only).
2. **Host routes** (`lib/net/web_routes.dart`):
   - `/play/assets/packages/nico_shared/<rest>`: served from the host's own bundle, key
     `packages/nico_shared/<rest>`, when the zip doesn't have the file.
   - `/art/<rest>`: the same files under a short name for the `/screen/` page (`packages/nico_shared/assets/<rest>`).
   - Loaded on request from the asset bundle (not all into memory at start, as the screen page is), behind a small
     interface so tests can supply files. Only keys under `packages/nico_shared/`; anything with `..` is refused.
3. **Browser screen:** `tacticalvoxelrpg.js` loads `/art/tacticalvoxelrpg/…`. Delete
   `assets/display/games/tacticalvoxelrpg/` and its six lines in the root `pubspec.yaml`. Sea Siege's PNGs stay:
   they're drawn for the browser screen only (Flutter paints the ships itself).
4. **Guard against new copies:** a test fails if any file under `assets/display/` is identical to one in
   `packages/nico_shared/assets/`.
5. **Docs:** `docs/ADDING_A_GAME.md`:
   - where art goes: `packages/nico_shared/assets/<game id>/`;
   - how the browser screen links to it: `/art/<game id>/…`;
   - sizes: about twice the largest size it's drawn at, RGBA PNG; the shrink settings used for Tactical as an
     example.

   Plus CODE_MAP, CHANGELOG and README (the `tool/` row). `tool/new_game.dart` needs nothing: generated games have
   no art.

## Tests

- `test/net/web_routes_test.dart`:
  - game art under `/play/` comes from the bundle;
  - a file in the zip still wins;
  - `/art/` works;
  - missing files give 404;
  - `..` and keys outside `nico_shared` are refused.
- `test/net/hosted_room_test.dart`: the real asset bundle serves a Tactical portrait at both URLs.
- The full check, plus the browser client build: the zip should drop to about 5.9 MB.

## Verification on devices

A Windows host with:
- a browser player on the tablet playing Tactical Voxel RPG, with portraits and slimes showing;
- the browser `/screen/` showing them too;
- the Caster still showing them (bundled).

The browser's network tab should show the art coming from `/play/assets/packages/nico_shared/…` with status 200.

## Not covered

- **Art still lives in the host app** (once now, instead of three times). Apps grow with every game's art. That's
  fine for a few games; downloading art on demand would be its own project.
- **Older hosts:** builds from before this change bundle art in the zip; builds after it serve it. Mixing isn't
  possible anyway, since every PR raises the protocol version.
