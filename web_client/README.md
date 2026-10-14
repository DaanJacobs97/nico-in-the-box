# Nico in the Box: browser client

A Flutter **web** app for players who can't use the native app. The host app serves it at
`http://<host-ip>:47800/play/`, and it connects back to the same host over `/ws`, like the app does.

It's built from the shared screens in `packages/nico_shared`, so every game playable in the app is playable here.
It can't host rooms or scan for them, because browsers can't open server or UDP sockets. The host's address is
simply the page's own address.

## Building

Don't run `flutter build web` by hand for release. Use the repo script, which sets the right flags and packs the
output into the host app:

```bash
powershell -ExecutionPolicy Bypass -File tool/build_web_client.ps1   # Windows
tool/build_web_client.sh                                            # macOS / Linux
```

What the script does:
- builds with `--base-href /play/`, because the host serves the client under that path
- builds with `--no-web-resources-cdn`, so it works on a LAN without internet
- keeps only the CanvasKit engine variants a non-wasm build can load, and drops debug symbols
- writes `assets/generated/web_client.zip`, which the host app bundles

Rebuild whenever this folder or `packages/nico_shared` changes. Otherwise the host serves a stale client.

## Development

`flutter run -d chrome` starts the client on Flutter's own dev server, so it tries to join a room *there* and
fails. To try changes, run the build script, start a room in the host app, and open `http://<host-ip>:47800/play/`.
Widget tests (`flutter test` in this folder) cover the join screen.

## Future: shared screen in Flutter web (stub)

The shared screen is served at `/screen` as lightweight HTML/JS (see PLAN.md). A Flutter web version could later
live here as a second route. It would read the same read-only `/display` WebSocket feed and plug into the host as
a `FlutterWebDisplayFrontend`. Nothing is built for this yet.
