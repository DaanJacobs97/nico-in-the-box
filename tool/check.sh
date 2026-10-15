#!/usr/bin/env bash
# Runs every check CI runs (except the web build): format, analyze, and all
# five test suites. Use before every pull request.
#
#   tool/check.sh          # check only
#   tool/check.sh --fix    # format first
set -uo pipefail
cd "$(dirname "$0")/.."

sources=(lib test integration_test tool
  packages/nico_shared/lib packages/nico_shared/test
  packages/nico_native/lib packages/nico_native/test
  caster/lib caster/test web_client/lib web_client/test)
failed=()

step() {
  local name=$1; shift
  echo "== $name"
  if ! "$@"; then failed+=("$name"); echo "   FAILED"; fi
}

[[ "${1:-}" == "--fix" ]] && step "format (fix)" dart format "${sources[@]}"
step "format check" dart format --output=none --set-exit-if-changed "${sources[@]}"
step "analyze" flutter analyze
for suite in . packages/nico_shared packages/nico_native caster web_client; do
  step "test $suite" bash -c "cd '$suite' && flutter test"
done

if (( ${#failed[@]} )); then
  echo; echo "Failed: ${failed[*]}"; exit 1
fi
echo; echo "All checks passed."
