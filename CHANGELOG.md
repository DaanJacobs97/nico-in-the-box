# Changelog

What each version of Nico in the Box added. Version numbers stay below 1.0 until iOS builds, release signing and app
icons are done. Bump the version in every `pubspec.yaml` (app, Caster, browser client and both packages) together,
and tag the merge commit `vX.Y.Z`.

The network protocol has its own number (`kProtocolVersion`, currently 5). It changes whenever a message changes,
so builds of different versions refuse to play together.

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
