#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  node ../electrobun/package/bin/electrobun.cjs dev
  exit 0
fi

shopt -s nullglob
apps=(build/dev-macos-*/*.app)
if [[ ${#apps[@]} -eq 0 ]]; then
  echo "No dev app bundle found under build/dev-macos-*/"
  exit 1
fi

latest_app="$(ls -td "${apps[@]}" | head -n 1)"

if [[ -n "${ELECTROBUN_DEV_URL:-}" ]]; then
  launchctl setenv ELECTROBUN_DEV_URL "$ELECTROBUN_DEV_URL"
else
  launchctl unsetenv ELECTROBUN_DEV_URL >/dev/null 2>&1 || true
fi

open "$latest_app"
