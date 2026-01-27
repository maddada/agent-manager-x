#!/bin/bash
# Compile Asset Catalog and inject into Tauri app bundle
# Run this after `npm run tauri build` to add light/dark/tinted icon support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
XCASSETS_DIR="$PROJECT_ROOT/src-tauri/Assets.xcassets"

# App bundle locations
DEBUG_APP="$PROJECT_ROOT/src-tauri/target/debug/bundle/macos/Agent Manager X.app"
RELEASE_APP="$PROJECT_ROOT/src-tauri/target/release/bundle/macos/Agent Manager X.app"

# Determine which app bundle to use
if [ -n "$1" ]; then
    APP_BUNDLE="$1"
elif [ -d "$RELEASE_APP" ]; then
    APP_BUNDLE="$RELEASE_APP"
elif [ -d "$DEBUG_APP" ]; then
    APP_BUNDLE="$DEBUG_APP"
else
    echo "Error: No app bundle found. Run 'npm run tauri build' first."
    echo "Or specify the path to the .app bundle as an argument."
    exit 1
fi

echo "=== Injecting Asset Catalog into App Bundle ==="
echo "App bundle: $APP_BUNDLE"
echo "Asset Catalog: $XCASSETS_DIR"

# Check if actool is available
if ! command -v xcrun &> /dev/null; then
    echo "Error: Xcode command line tools not found. Install with: xcode-select --install"
    exit 1
fi

# Create temp directory for compilation
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Compile the Asset Catalog
echo ""
echo "Compiling Asset Catalog..."
xcrun actool \
    --compile "$TEMP_DIR" \
    --platform macosx \
    --minimum-deployment-target 10.13 \
    --app-icon AppIcon \
    --output-partial-info-plist "$TEMP_DIR/Info.plist" \
    "$XCASSETS_DIR"

# Check if Assets.car was created
if [ ! -f "$TEMP_DIR/Assets.car" ]; then
    echo "Error: Failed to compile Asset Catalog"
    exit 1
fi

# Inject into app bundle
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
echo "Injecting Assets.car into: $RESOURCES_DIR"

cp "$TEMP_DIR/Assets.car" "$RESOURCES_DIR/Assets.car"

# Update Info.plist if needed (to reference AppIcon)
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    # Check if CFBundleIconFile is set
    if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$INFO_PLIST" &>/dev/null; then
        echo "Adding CFBundleIconFile to Info.plist..."
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string 'AppIcon'" "$INFO_PLIST"
    fi

    # Add CFBundleIconName for Asset Catalog icons
    if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$INFO_PLIST" &>/dev/null; then
        echo "Adding CFBundleIconName to Info.plist..."
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string 'AppIcon'" "$INFO_PLIST"
    else
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconName 'AppIcon'" "$INFO_PLIST"
    fi
fi

# Clear icon cache to see changes immediately
echo ""
echo "Clearing icon cache..."
sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true

echo ""
echo "=== Asset Catalog Injection Complete ==="
echo ""
echo "The app now has light/dark mode and tinting support!"
echo "You may need to restart the app or log out/in to see icon changes."
echo ""
