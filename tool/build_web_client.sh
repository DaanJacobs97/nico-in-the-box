#!/usr/bin/env bash
# Builds the browser player client and packs it into the host app's assets.
#
#   tool/build_web_client.sh
#
# Output: assets/generated/web_client.zip (git-ignored). See the .ps1 twin
# for details; both must produce the same archive layout.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/assets/generated/web_client.zip"

cd "$root/web_client"
flutter pub get
# Served from /play/ by the host; no CDN so it works on an offline LAN.
flutter build web --release --base-href /play/ --no-web-resources-cdn --no-wasm-dry-run

mkdir -p "$(dirname "$out")"
rm -f "$out"
cd build/web
# Browsers load canvaskit/ (full) or canvaskit/chromium/; the other engines are
# only for --wasm builds or opt-in flags, and .symbols files are debug-only.
# Game art (nico_shared's assets) is served by the host from its own copy.
zip -q -r -9 "$out" . \
  -x 'canvaskit/skwasm.*' 'canvaskit/skwasm_heavy.*' 'canvaskit/wimp.*' \
     'canvaskit/webparagraph/*' '*.symbols' '.last_build_id' \
     'assets/packages/nico_shared/*'
ls -l "$out"
