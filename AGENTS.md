# Instructions for AI coding assistants

Nico in the Box: Flutter LAN party games (host/join app, Caster app, browser client).

## Start here (in this order, and stop when you have enough)

1. **[docs/CODE_MAP.md](docs/CODE_MAP.md):** every source file with a one-line purpose, a *"where to change what"*
   table, the protocol cheat sheet, where each test lives, and known gotchas. Read this instead of exploring the repo.
2. **The files the code map points you to.** Big files are marked with line counts; read the parts you need.
3. **Only if needed:** [README.md](README.md) (running, branch rules), [PLAN.md](PLAN.md) (why things are the way
   they are), [docs/ADDING_A_GAME.md](docs/ADDING_A_GAME.md) (adding a game).

**Don't read:** `android/`, `ios/`, `windows/` (also under `caster/` and `web_client/`), `build/`, `.dart_tool/`,
`assets/generated/`, `web_client/web/` or `pubspec.lock` files, unless the task is about them. They are generated
or scaffolding.

## Rules

- **Never commit or push to `main`.** Work on a branch (`feature/…`, `fix/…`, `chore/…`, `docs/…`), push it and
  open a pull request. Leave merging to a human unless one explicitly asks you to merge.
- **Write the pull request description from [.github/pull_request_template.md](.github/pull_request_template.md).**
  `gh pr create --body-file` does not apply it for you, so copy its sections. Report only checks you actually ran.
- **Before opening a pull request, run the full check:** it formats-checks, analyzes and runs all five test suites.

  ```bash
  powershell -ExecutionPolicy Bypass -File tool/check.ps1 -Fix   # Windows
  tool/check.sh --fix                                           # macOS / Linux
  ```

- `packages/nico_shared` must stay **web-safe**: no `dart:io` imports (it also runs in browsers).
- If you change a network message's shape or add a game, bump `kProtocolVersion` in
  `packages/nico_shared/lib/net/protocol.dart`.
- **Added, moved or deleted a source file, or changed its size a lot? Update [docs/CODE_MAP.md](docs/CODE_MAP.md).**
  `test/docs/code_map_test.dart` fails until you do. It also caps source files at 600 non-blank lines: split a
  file that grows past that by job (see `game_server.dart` + `web_routes.dart`), don't raise the cap.
- Don't weaken or delete tests to make a change pass; fix the code.

## Common tasks

- **Adding a game:** run `dart run tool/new_game.dart <id> "<Name>" [min] [max]` to generate every piece with
  placeholder rules, then follow [docs/ADDING_A_GAME.md](docs/ADDING_A_GAME.md) to replace them.
  `flutter test test/games/registry_consistency_test.dart` names any missing piece.
- **Testing on devices without a second player:** `flutter test tool/bot/lan_bot_test.dart --dart-define=HOST=<ip>`.

## Windows notes

- Don't run `dart format .` (it crashes on the Caster's Android build output); `tool/check.ps1` formats the right
  folders.
- In Windows PowerShell 5.1, write commit messages to a file and use `git commit -F <file>`. Double quotes inside
  `-m` arguments get mangled.
