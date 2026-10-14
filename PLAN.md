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
Reconnecting after a drop, a browser join client, more than one room per host, a polished iOS build, sound and
animations beyond the basics.
