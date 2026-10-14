# Nico in the Box

Jackbox-style LAN party games built with Flutter. One device hosts a room, and friends on the same Wi-Fi find it
automatically and join with a nickname. No internet connection and no accounts are needed.

> **Status:** v0.1. Playable on Windows and Android over a LAN. See [PLAN.md](PLAN.md) for the design and
> milestones.

## Features

- **Host or join from the same app.** The host joins their own room automatically and gets extra session controls:
  start, restart, end game, kick a player, change game, close room.
- **Automatic room discovery** over the local network using UDP broadcast. If scanning doesn't find a room, you can
  type in the host's IP address instead.
- **The game sets the room size.** The host picks a game, and that decides how many players can join.
- **Private views.** Each player only receives the state they're allowed to see, so nobody can peek at other hands.

### Games

| Game | Players | Description |
|---|---|---|
| Tic Tac Toe | 2 | The classic game, with the host against one other player |
| Color Clash | 2–4 | An Uno-style card game: match by color or number, with Skip, Reverse, Draw Two and Wild cards |

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

### Project layout

| Path | What lives there |
|---|---|
| `lib/` | The host/join app: server, LAN discovery, hosting and joining screens. Native-only code (`dart:io`) belongs here |
| `packages/nico_shared/` | Protocol, client, game engines, game widgets and session screens, shared by every app. **Web-safe:** no `dart:io` imports, so it also runs in browsers |
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
which proves the package stays browser-safe; on Windows without Chrome, set `CHROME_EXECUTABLE` to Edge's
`msedge.exe`.

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

## Playing on a LAN

1. All devices must be on the **same network**. Guest Wi-Fi networks often block traffic between devices.
2. On the host device, tap **Host**, choose a nickname and a game, then tap **Create room**.
3. On Windows, the first time you host, **allow the app through Windows Defender Firewall on Private networks**.
4. Players tap **Join**. The room should appear in the list; if it doesn't, enter the IP address shown in the host's
   lobby.
5. Each player picks a nickname. When enough players have joined, the host starts the game.

**Ports used:** TCP 47800 for the game connection, UDP 47801 for room discovery.

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

### Before opening a pull request

- Run `dart format .`, `flutter analyze` and `flutter test` locally. CI runs the same checks on every pull request.
- Keep each pull request focused on one feature or fix, and describe what changed and how you tested it.
- If you change the network protocol (`lib/net/protocol.dart`), bump the protocol version so old and new app builds
  refuse to talk to each other instead of misbehaving.

## License

Private hobby project. All rights reserved. See [LICENSE](LICENSE).
