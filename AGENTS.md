# Instructions for AI coding assistants

Nico in the Box: Flutter LAN party games. Read [README.md](README.md) first, for the project layout, how to run and
test, and the contribution rules.

## Rules

- **Never commit or push to `main`.** Work on a branch (`feature/…`, `fix/…`, `chore/…`, `docs/…`), push it and
  open a pull request. Leave merging to a human unless one explicitly asks you to merge.
- Before opening a pull request, run the format, analyze and test commands in the README for every package you
  touched. CI runs the same checks.
- `packages/nico_shared` must stay **web-safe**: no `dart:io` imports (it also runs in browsers).
- If you change a network message's shape, bump `kProtocolVersion` in `packages/nico_shared/lib/net/protocol.dart`.
- Don't weaken or delete tests to make a change pass; fix the code.

## Common tasks

- **Adding a game:** follow [docs/ADDING_A_GAME.md](docs/ADDING_A_GAME.md) step by step. Run
  `flutter test test/games/registry_consistency_test.dart` early; its failures name the missing piece.
- **Design and history:** [PLAN.md](PLAN.md) explains the architecture and the decisions behind it.
- **Testing on devices without a second player:** `flutter test tool/bot/lan_bot_test.dart --dart-define=HOST=<ip>`.

## Windows notes

- Format explicit folders (see the README). `dart format .` can crash on the Caster's Android build output.
- In Windows PowerShell 5.1, write commit messages to a file and use `git commit -F <file>`. Double quotes inside
  `-m` arguments get mangled.
