# Nico in the Box

Jackbox-style LAN party games built with Flutter. One device hosts a room, and friends on the same Wi-Fi find it
automatically and join with a nickname. No internet connection and no accounts are needed.

> **Status:** early development. See [PLAN.md](PLAN.md) for the design and milestones.

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
- **Windows builds:** Visual Studio 2022 with the *Desktop development with C++* workload
- **Android builds:** the Android SDK, through Android Studio or the command-line tools

Run `flutter doctor` to check your setup.

### Run

```bash
flutter pub get
flutter run -d windows     # or: flutter run -d <android-device-id>
```

### Test

```bash
flutter analyze
flutter test
```

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

- `main` should always build. Do your work on a feature branch, e.g. `feature/color-clash-ui`, and open a pull
  request.
- Before you push, run `dart format .`, `flutter analyze` and `flutter test`. CI runs the same checks on every pull
  request.

## License

Private hobby project. All rights reserved. See [LICENSE](LICENSE).
