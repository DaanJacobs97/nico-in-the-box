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
   If the host closes the room, every client goes back to the menu.
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
  - Draw Two and Wild Draw Four make the next player draw and lose their turn.
  - There's no stacking and no challenges.
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

**Status:** planned, not started.

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
assets/landing/index.html      NEW tiny page at /: "Join as player" / "Show the shared screen"
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
- **Host without a seat (option B):** the host's hello includes `seat: false`. The connection keeps host rights but
  isn't a player. Room size and the reserved host seat then follow `hostPlays`.
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
- **Size budget:** at most 4 MB in the host app. CI fails if the build gets larger.
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
- The web client builds with `--no-web-resources-cdn`, stays under the 4 MB budget, and loads on a host with no
  internet connection. To check this, unplug the router's internet uplink during the device test.
- Privacy test: for every game and every state reached by the random computer-played games, `tableView()` contains
  no card IDs from anyone's hand.
- Device runs for browser players and all three screen types, as in milestone 8. Each plays Tic Tac Toe and Color Clash to the end, checks
  that players get the compact view while a screen is connected, and pulls the screen mid-game to confirm the fall
  back to the full view.

## Out of scope for this feature
- Hosting from a browser. Browsers can't open server sockets, so the host is always a native app.
- Finding rooms by scanning from a browser. Browser players use the address or the QR code.
- Installing the web client as an offline app (PWA) or serving it over HTTPS.
- Google Cast / Chromecast and AirPlay.
- More than one Caster per room. (Browsers can be several, since they're read-only.)
- Sound on the shared screen.
- A finished Flutter web display. Only the stub and its contract are in scope.
