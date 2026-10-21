# Changelog

What each version of Nico in the Box added. Version numbers stay below 1.0 until there are iOS builds. To release,
bump the version in every `pubspec.yaml` (app, Caster, browser client and both packages) together, then tag the merge
commit `vX.Y.Z`: pushing the tag builds the downloads (see "Release builds" in the README).

The network protocol has its own number (`kProtocolVersion`, currently 6). It changes whenever a message changes,
so builds of different versions refuse to play together.

## Unreleased

- **Sea Siege looks the part:** every ship type has its own top-down sprite. Players see their fleet drawn as ships,
  and the shared screen shows sunk ships as burnt-out wrecks. The water moves on every board, on players' devices
  too. On the shared screen the host's board comes first, and the boards sit side by side on a wide screen and
  stacked on a tall one, in the Caster and the browser alike. The shared screen no longer lists the ships still
  afloat.
- **Sea Siege: clearer turns and a tidier screen:**
  - **Whose turn:** a gold banner says who is firing at whom. The board being fired at glows with a crosshair,
    and the other board dims. On your own device, "Your turn: fire!" pulses.
  - **Layout:** players' boards sit side by side when the device is in landscape.
  - **Shot messages:** the text feed at the bottom is gone, so the boards no longer change size. New shots pop
    up as short-lived messages over the board they hit, and the square flashes. On your turn these messages
    never cover the board you tap.
  - **Protocol 6:** shots in the log are numbered.
- **The Caster turns with the device:** a tablet Caster can stand in portrait instead of being locked to landscape.

## 0.3.1 (2026-10-15)

The first version with installable demo builds; the games are the same as in 0.3.0.

- **Downloads:** each release has a Windows zip and an Android APK of the app and of the Caster, built by GitHub
  Actions from the version tag. The Windows zips include the Visual C++ runtime. (#33)
- **Release signing:** Android builds are signed with the project's key, so later versions install as updates. (#31)
- **App icons:** the app, the Caster and the browser client have their own icons instead of Flutter's default.
  (#32)

## 0.3.0 (2026-10-15)

- **Sea Siege:** a Battleship-style game for 2 players. Hide five ships, then take turns firing at the enemy grid.
  Ships still afloat never leave the host, and a sunk ship is revealed. (#25)
- **Easier ship placement:** drag a ship with a live green or red preview, double-tap to turn it, and ships that
  don't fit are nudged to the nearest spot that does. (#27)
- **Game options:** a game can declare rules the host switches in the lobby. Sea Siege's first option is "Hit =
  shoot again". Players and shared screens see the active rules. (#24)
- **Reconnect:** a player whose connection drops briefly gets their seat back in the same running game. The seat is
  kept for 60 seconds. (#29)
- **For contributors:**
  - a code map and a one-command check script (#20)
  - a file size cap (#21)
  - a new-game generator (#23)
  - a pull request template (#22)
  - the LAN bot and the device test can play Sea Siege (#26)

## 0.2.0 (2026-10-15)

- **Single game screen:** the table moves to one shared screen, and players' devices show only their own hand and
  buttons. The screen can be:
  - a browser page served by the host (#14)
  - the separate Nico Caster app (#15, #16)
  - the host's own device (#13)
- **Join from a browser:** anyone on the network can play without installing the app. (#11)
- **The hosting device stays awake** while a room is open. (#18)
- **For contributors:** a guide for adding games, enforced by a consistency test. (#19)

## 0.1.0 (2026-10-14)

- **One app that hosts and joins** on Windows and Android, with an iOS stub. (#1)
- **Rooms on the LAN:** found by scanning, or joined by IP address. (#4)
- **Nicknames, a lobby, and host session controls:** start, restart, end game, kick and close room. (#3, #5)
- **Games:** Tic Tac Toe for 2 players (#2) and Color Clash, an Uno-style card game for 2–4 players (#6).
- Verified on a Windows PC and an Android tablet. (#8)
