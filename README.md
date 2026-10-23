# Nico in the Box

Jackbox-style LAN party games built with Flutter. One device hosts a room, and friends on the same Wi-Fi find it
automatically and join with a nickname. No internet connection and no accounts are needed.

> **Status:** v0.3. Playable on Windows and Android over a LAN, and from any browser. See
> [CHANGELOG.md](CHANGELOG.md) for what each version added and [PLAN.md](PLAN.md) for the design.

## Features

- **Host or join from the same app.** The host joins their own room automatically and gets extra session controls:
  start, restart, end game, kick a player, change game, close room.
- **Automatic room discovery** over the local network using UDP broadcast. If scanning doesn't find a room, you can
  type in the host's IP address instead.
- **The game sets the room size.** The host picks a game, and that decides how many players can join.
- **Private views.** Each player only receives the state they're allowed to see, so nobody can peek at other hands.
- **Single game screen.** The host can put the table on one shared screen: their own device, a TV browser at
  `http://<host-ip>:47800/screen`, or a device running **Nico Caster** picked from a list. Players then see only
  their hand and buttons; if the screen drops, they get the full table back.
- **No app? Use a browser.** The host also serves a browser version of the game, so anyone on the network can join
  by scanning a QR code. It works without internet.

### Games

| Game | Players | Description |
|---|---|---|
| Tic Tac Toe | 2 | The classic game, with the host against one other player |
| Color Clash | 2–4 | An Uno-style card game: match by color or number, with Skip, Reverse, Draw Two and Wild cards. Swipe a card up to play it. The host chooses whether +2 and +4 can be stacked, and whether drawing them costs your turn |
| Sea Siege | 2 | Battleship-style: hide five ships, then take turns firing at the enemy grid. The host can let a hit earn another shot |
| Blackjack | 2–8 | Play seat by seat against an AI dealer with one deck: hit, stand, double, split. The host picks "First to x wins" or "Most chips after x hands" (x = 3, 5, 10 or 20) |

## Platforms

| Platform | Status |
|---|---|
| Windows | Supported |
| Android | Supported |
| iOS | Stub only (not built or tested yet) |

## Getting started

### Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
- **Windows builds:** Visual Studio 2022 with the *Desktop development with C++* workload, and Windows
  **Developer Mode** turned on (Flutter plugins need its symlink support). You'll find it under Settings → System →
  For developers.
- **Android builds:** the Android SDK, through Android Studio or the command-line tools

Run `flutter doctor` to check your setup.

### Run

```bash
flutter pub get
flutter run -d windows     # or: flutter run -d <android-device-id>
```

`flutter pub get` also resolves the local `packages/nico_shared` dependency.

To let players without the app **join from a browser**, build the web client into the host app first, and again
whenever `web_client/` or `packages/nico_shared` changes (the host app carries a copy, so a stale copy means a
stale browser client):

```bash
powershell -ExecutionPolicy Bypass -File tool/build_web_client.ps1   # Windows
tool/build_web_client.sh                                            # macOS / Linux
```

Without that step the app still works; browser join then shows a *not included in this build* page and the lobby
hides the QR code.

### Project layout

The table below gives the big picture. **[docs/CODE_MAP.md](docs/CODE_MAP.md)** lists every source file, says where to change
what, and maps the tests.

| Path | What lives there |
|---|---|
| `lib/` | The host/join app: server, LAN discovery, hosting and joining screens. Native-only code (`dart:io`) belongs here |
| `packages/nico_shared/` | Protocol, client, game engines, game widgets and session screens, shared by every app. **Web-safe:** no `dart:io` imports, so it also runs in browsers |
| `packages/nico_native/` | Native-only LAN code (`dart:io`): UDP announcements and scanning, shared by the app and the Caster |
| `caster/` | **Nico Caster**: a separate app that turns any Windows PC, Android tablet or Android TV into the shared screen. The host picks it from a list (see PLAN.md) |
| `web_client/` | Flutter **web** app for players without the app. The host serves it at `/play/` |
| `tool/` | `build_web_client` scripts: build `web_client/` and pack it into `assets/generated/web_client.zip` (git-ignored). Game art isn't packed: the host serves it from its own copy |
| `integration_test/` | The end-to-end LAN test on real devices |

### Test

```bash
flutter analyze
flutter test
```

```bash
cd packages/nico_shared
flutter test
flutter test --platform chrome
```

The root `flutter test` runs the server, discovery and in-process server/client tests over real loopback sockets.
The shared package's tests cover the game engines and protocol. `--platform chrome` runs them compiled for the web,
which proves the package stays browser-safe. It needs Google Chrome: pointing `CHROME_EXECUTABLE` at Edge was tried
and hangs while loading. CI always runs this step with Chrome, so you can also leave it to CI.

Compiling for the web does **not** catch a stray `dart:io` import; Dart only fails when that code runs. CI therefore
also rejects any `dart:io` import in `packages/nico_shared`.

### End-to-end test on two devices

[`integration_test/lan_play_test.dart`](integration_test/lan_play_test.dart) drives the real app on two devices at
once. It plays two rounds of Tic Tac Toe, switches to Color Clash and plays it to a winner, then the host closes the
room. Start the two sides at roughly the same time (each waits up to 5 minutes for the other):

```bash
flutter devices                                                         # find device ids
flutter test integration_test/lan_play_test.dart -d windows --dart-define=ROLE=host
flutter test integration_test/lan_play_test.dart -d <android-id> --dart-define=ROLE=join
```

The joiner finds the room by scanning. Add `--dart-define=JOIN_IP=<host ip>` to test manual IP entry instead.
Any device can take either role.

Other options:
- `SCREEN=browser|caster|host` tests Single game screen:
  - `browser`: the host waits for a browser at `/screen`
  - `caster`: the host connects the first Nico Caster it finds
  - `host`: the host's device is the screen and doesn't play
- `GAMES=ttt` skips Color Clash. `GAMES=sea` plays only Sea Siege, twice: with "Hit = shoot again" off, then on.
  Both sides use every placement control and check the turn rule after each shot.
- `EXPECT_WEB_PLAYER=true` makes the host expect a browser player.

Keep the host's test window visible. Flutter stops drawing a minimized window, which stalls the test.

**Flaky Wi-Fi on an Android device?** Tunnel the game port over USB and join by IP instead of scanning:

```bash
adb reverse tcp:47800 tcp:47800
```

Then use `--dart-define=JOIN_IP=127.0.0.1` on that device, or open `http://127.0.0.1:47800/screen/` or `/play/` in
its browser. Discovery doesn't go through the tunnel, so this tests everything except finding the room.

**Only one device free?** Use the scripted player as the other seat. It joins over the real protocol and plays Tic
Tac Toe, Color Clash, Sea Siege and Blackjack until the room closes:

```bash
flutter test tool/bot/lan_bot_test.dart --dart-define=HOST=<host ip>
```

Add `--dart-define=MOVE_DELAY_MS=1000` to slow it down, for example while watching a shared screen.

### Release builds

Android release builds of the app and the Caster are signed with the project's release key. Its owner keeps the key
outside the repository; CI gets it from the `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and
`ANDROID_KEY_ALIAS` repository secrets.

To sign locally, create `key.properties` in the repository root. It's git-ignored, so it is never committed:

```properties
storeFile=C:/Users/<you>/keys/nico-release.jks
storePassword=<password>
keyAlias=nico
```

Without it, release builds are signed with the debug key and Gradle prints a warning. That's fine for testing, but
don't hand those builds out: a build signed with another key can't be installed over them as an update.

**Making a release** (the downloads go to a draft GitHub Release, which only collaborators can see):

1. On a branch, bump `version:` in every `pubspec.yaml` and add a section to `CHANGELOG.md`; merge it.
2. Optionally do a dry run first: tag `vX.Y.Z-rc1` and push it. It builds a draft pre-release.
3. Tag the merge commit `vX.Y.Z` and push the tag. `.github/workflows/release.yml` checks the tag matches
   `pubspec.yaml`, builds the four files with `tool/release/package_windows.ps1` and `package_android.sh`, and
   drafts the release with the changelog section and the install notes from `.github/release_install_notes.md`.
4. Download and try the files, then publish the draft.

The packaging scripts also run locally (output in `build/release/`), which is handy for checking a build before
tagging.

## Playing on a LAN

1. All devices must be on the **same network**. Guest Wi-Fi networks often block traffic between devices.
2. On the host device, tap **Host**, choose a nickname and a game, then tap **Create room**.
3. On Windows, the first time you host, **allow the app through Windows Defender Firewall on Private networks**.
4. Players tap **Join**. The room should appear in the list; if it doesn't, enter the IP address shown in the host's
   lobby.
5. Each player picks a nickname. When enough players have joined, the host starts the game.
6. The hosting device keeps its screen on while the room is open, so a tablet used as the shared screen doesn't dim
   or sleep. It goes back to normal when the room closes. The Caster app does the same.
7. **No app?** The host's lobby shows a QR code and a link like `http://192.168.0.156:47800/play`. Scanning it
   with a phone camera (or typing it into any browser on the same network) opens the browser version: pick a
   nickname and play like everyone else. Browser players are marked with a globe icon in the lobby.

**Ports used:** TCP 47800 for the game connection, UDP 47801 for room discovery. The Caster uses UDP 47802 to announce
itself and TCP 47803 for the host's connection.

> The Android emulator sits behind NAT and can't see LAN broadcasts. To test discovery, use a physical device.

## Contributing

### `main` is protected

**Don't commit or push directly to `main`.** This applies to human contributors and to AI coding assistants
(Claude, Copilot, Cursor, Codex, etc.).

- All changes go through a **pull request** from a feature branch. Name branches
  `feature/<short-description>`, `fix/<short-description>` or `chore/<short-description>`.
- A pull request can only be merged when **CI passes** (formatting, `flutter analyze`, `flutter test`).
- Never force-push to `main`, rewrite its history or delete it.
- AI assistants: create a branch, commit there, push the branch and open a pull request. Leave the merge to a human
  unless one explicitly tells you to merge.

### Adding a game

Follow **[docs/ADDING_A_GAME.md](docs/ADDING_A_GAME.md)**. It covers the six pieces a game needs, where each one goes,
the required tests, and a pull-request checklist. `test/games/registry_consistency_test.dart` fails until a new game
is fully wired in. To start, `dart run tool/new_game.dart <id> "<Name>" [min] [max]` generates every piece with
placeholder rules that already pass the checks.

### Before opening a pull request

- Run the full check (format, analyze, all five test suites):
  `powershell -ExecutionPolicy Bypass -File tool/check.ps1 -Fix` on Windows, `tool/check.sh --fix` elsewhere.
  CI runs the same checks on every pull request.
- Added, moved or deleted a source file? Update [docs/CODE_MAP.md](docs/CODE_MAP.md). A test checks it.
- Keep each pull request focused on one feature or fix. New pull requests start from
  [the template](.github/pull_request_template.md): fill in what changed, which checks ran and what you tested on
  devices.
- Don't edit `kProtocolVersion` by hand: every pull request into `main` gets main's version + 1 automatically, so
  builds from different merges refuse to talk to each other instead of misbehaving. After the bot's "Set protocol
  version" commit lands on your branch, `git pull` before pushing again.

## License

Private hobby project. All rights reserved. See [LICENSE](LICENSE).
