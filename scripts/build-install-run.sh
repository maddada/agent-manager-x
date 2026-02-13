#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

APP_NAME="Agent Manager X.app"
BUILD_APP="$PROJECT_ROOT/src-tauri/target/release/bundle/macos/$APP_NAME"
INSTALL_APP="/Applications/$APP_NAME"
NOTARY_PROFILE="${AMX_NOTARY_PROFILE:-notarytool-profile}"
DO_NOTARIZE=false

if [ "${1:-}" = "--notarize" ]; then
  DO_NOTARIZE=true
elif [ $# -gt 0 ]; then
  echo "Usage: $0 [--notarize]"
  exit 1
fi

ZIP_PATH=""

cleanup() {
  if [ -n "$ZIP_PATH" ]; then
    rm -f "$ZIP_PATH"
  fi
}
trap cleanup EXIT

echo "=== Stop running app (if needed) ==="
if pkill -f "Agent Manager X" 2>/dev/null; then
  echo "Waiting for app to quit..."
  while pgrep -f "Agent Manager X" >/dev/null 2>&1; do
    sleep 0.5
  done
  echo "App stopped."
fi

echo "=== Build ==="
cd "$PROJECT_ROOT"
pnpm run tauri:build

if [ ! -d "$BUILD_APP" ]; then
  echo "Error: Built app not found at $BUILD_APP"
  exit 1
fi

echo "=== Install to /Applications ==="
rm -rf "$INSTALL_APP"
mv "$BUILD_APP" "$INSTALL_APP"

if [ "$DO_NOTARIZE" = true ]; then
  echo "=== Notarize with profile: $NOTARY_PROFILE ==="
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Error: notarytool profile '$NOTARY_PROFILE' is not available."
    echo "Create it with:"
    echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id \"<APPLE_ID>\" --team-id \"KTKP595G3B\" --password \"<APP_SPECIFIC_PASSWORD>\""
    exit 1
  fi

  ZIP_PATH="$(mktemp /tmp/agent-manager-x-notary.XXXXXX.zip)"
  ditto -c -k --sequesterRsrc --keepParent "$INSTALL_APP" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$INSTALL_APP"
fi

echo "=== Launch ==="
launchctl setenv AMX_DEBUG_LOG 1
open "$INSTALL_APP"

echo "Done."
