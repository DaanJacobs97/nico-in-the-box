#!/usr/bin/env bash
# Builds the Android release APKs of the app and the Caster and checks they
# are signed with the release key, not the debug key.
#
#   tool/release/package_android.sh [--skip-web-client]
#
# Output in build/release/: NicoInTheBox-<version>-android.apk and
# NicoCaster-<version>-android.apk. Needs the release key: key.properties at
# the repo root, or ANDROID_KEYSTORE_PATH/_PASSWORD and ANDROID_KEY_ALIAS (see
# "Release builds" in the README). Used by .github/workflows/release.yml.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$(pwd)
out="$root/build/release"
mkdir -p "$out"

version=$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' pubspec.yaml)
echo "Packaging version $version for Android"

# The host app serves the browser client, so it must be built first.
[[ "${1:-}" == "--skip-web-client" ]] || tool/build_web_client.sh

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${LOCALAPPDATA:-}/Android/Sdk}}"
apksigner=$(ls -d "$sdk"/build-tools/*/ | sort -V | tail -1)apksigner
[[ -e "$apksigner" ]] || apksigner="$apksigner.bat"

package() {
  local project=$1 name=$2
  (cd "$project" && flutter build apk --release)
  local apk="$project/build/app/outputs/flutter-apk/app-release.apk"
  local signer
  signer=$("$apksigner" verify --print-certs "$apk" | grep -m1 'certificate DN')
  echo "$name: $signer"
  if [[ "$signer" == *"Android Debug"* ]]; then
    echo "$name is signed with the debug key: set up the release key first." >&2
    exit 1
  fi
  cp "$apk" "$out/$name-$version-android.apk"
  echo "Wrote $out/$name-$version-android.apk"
}

package "$root" NicoInTheBox
package "$root/caster" NicoCaster
