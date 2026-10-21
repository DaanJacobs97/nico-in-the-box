<!--
Fill in every section. Delete lines that don't apply rather than leaving them unchecked.
AI assistants: say what you actually ran and saw. "Not run" is a fine answer; a guess is not.
-->

## What and why

<!-- One or two sentences: the problem and the change. Link the issue if there is one. -->

## Changes

<!-- Bullets, one per meaningful change. Name the files a reviewer should start with. -->

-

## Checks

- [ ] `tool/check.ps1` (Windows) or `tool/check.sh` (macOS/Linux) passes. Test counts: app _, shared _, native _, caster _, web _
- [ ] [`docs/CODE_MAP.md`](https://github.com/DaanJacobs97/nico-in-the-box/blob/main/docs/CODE_MAP.md) updated for added, moved, deleted or much bigger files
- [ ] "Protocol version" check passes (`kProtocolVersion` is set to main + 1 automatically; don't edit it by hand)
- [ ] Browser client rebuilt with `tool/build_web_client` and tried (changed `web_client/` or `nico_shared`) — or not needed
- [ ] New game: every box in the [checklist](https://github.com/DaanJacobs97/nico-in-the-box/blob/main/docs/ADDING_A_GAME.md#8-checklist) ticked — or not a game

## Tested on devices

<!-- What ran where, for example "Windows host + tablet app, Color Clash, 3 rounds" or "Not tested on devices: docs only". -->

| Role | Device and client | Result |
|---|---|---|
| Host | | |
| Player | | |
| Shared screen | none / browser / Caster / host device | |

## Screenshots

<!-- For UI changes: before and after. Delete this section otherwise. -->
