#!/bin/bash
# Build macOS icons with light/dark mode and tinting support
# This script generates all required icon sizes and compiles the Asset Catalog

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_ROOT/assets/icon"
XCASSETS_DIR="$PROJECT_ROOT/src-tauri/Assets.xcassets"
APPICONSET_DIR="$XCASSETS_DIR/AppIcon.appiconset"
ICONS_DIR="$PROJECT_ROOT/src-tauri/icons"

# Source images (1024x1024 with proper macOS padding)
PADDED_DIR="$ASSETS_DIR/padded"
# Default/Light appearance - shown in light mode
LIGHT_SOURCE="$PADDED_DIR/Icon-macOS-ClearLight-512x512@2x.png"
# Dark appearance - shown in dark mode
DARK_SOURCE="$PADDED_DIR/Icon-macOS-Default-512x512@2x.png"
# Tinted appearance - monochrome for macOS Sequoia tinting
TINTED_SOURCE="$PADDED_DIR/Icon-macOS-TintedLight-512x512@2x.png"

# Icon sizes needed for macOS
SIZES=(16 32 128 256 512)

echo "=== Building macOS Icons with Appearance Variants ==="
echo "Light source: $LIGHT_SOURCE"
echo "Dark source: $DARK_SOURCE"
echo "Tinted source: $TINTED_SOURCE"

# Generate padded icons if they don't exist
if [ ! -f "$LIGHT_SOURCE" ] || [ ! -f "$DARK_SOURCE" ] || [ ! -f "$TINTED_SOURCE" ]; then
    echo "Generating padded icons first..."
    "$SCRIPT_DIR/add-icon-padding.sh"
fi

# Check source files exist
for src in "$LIGHT_SOURCE" "$DARK_SOURCE" "$TINTED_SOURCE"; do
    if [ ! -f "$src" ]; then
        echo "Error: Source file not found: $src"
        exit 1
    fi
done

# Ensure output directories exist
mkdir -p "$APPICONSET_DIR"
mkdir -p "$ICONS_DIR"

echo ""
echo "Generating icon sizes..."

# Generate all sizes for each appearance
for size in "${SIZES[@]}"; do
    size2x=$((size * 2))

    # Light/Default appearance (1x)
    echo "  ${size}x${size} (light)"
    sips -z $size $size "$LIGHT_SOURCE" --out "$APPICONSET_DIR/icon_${size}x${size}.png" >/dev/null 2>&1

    # Light/Default appearance (2x)
    echo "  ${size}x${size}@2x (light)"
    sips -z $size2x $size2x "$LIGHT_SOURCE" --out "$APPICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null 2>&1

    # Dark appearance (1x)
    echo "  ${size}x${size} (dark)"
    sips -z $size $size "$DARK_SOURCE" --out "$APPICONSET_DIR/icon_${size}x${size}_dark.png" >/dev/null 2>&1

    # Dark appearance (2x)
    echo "  ${size}x${size}@2x (dark)"
    sips -z $size2x $size2x "$DARK_SOURCE" --out "$APPICONSET_DIR/icon_${size}x${size}@2x_dark.png" >/dev/null 2>&1

    # Tinted appearance (1x)
    echo "  ${size}x${size} (tinted)"
    sips -z $size $size "$TINTED_SOURCE" --out "$APPICONSET_DIR/icon_${size}x${size}_tinted.png" >/dev/null 2>&1

    # Tinted appearance (2x)
    echo "  ${size}x${size}@2x (tinted)"
    sips -z $size2x $size2x "$TINTED_SOURCE" --out "$APPICONSET_DIR/icon_${size}x${size}@2x_tinted.png" >/dev/null 2>&1
done

echo ""
echo "Generating standard Tauri icons..."

# Generate standard Tauri icon files (using dark appearance as default)
sips -z 32 32 "$DARK_SOURCE" --out "$ICONS_DIR/32x32.png" >/dev/null 2>&1
sips -z 128 128 "$DARK_SOURCE" --out "$ICONS_DIR/128x128.png" >/dev/null 2>&1
sips -z 256 256 "$DARK_SOURCE" --out "$ICONS_DIR/128x128@2x.png" >/dev/null 2>&1
sips -z 512 512 "$DARK_SOURCE" --out "$ICONS_DIR/icon.png" >/dev/null 2>&1

echo ""
echo "Generating .icns file..."

# Create iconset for icns generation
ICONSET_DIR="$ICONS_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Generate iconset images (using dark as default for .icns)
sips -z 16 16 "$DARK_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1
sips -z 32 32 "$DARK_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
sips -z 32 32 "$DARK_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1
sips -z 64 64 "$DARK_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
sips -z 128 128 "$DARK_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1
sips -z 256 256 "$DARK_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
sips -z 256 256 "$DARK_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1
sips -z 512 512 "$DARK_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
sips -z 512 512 "$DARK_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1
sips -z 1024 1024 "$DARK_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1

# Convert to icns
iconutil -c icns "$ICONSET_DIR" -o "$ICONS_DIR/icon.icns"
rm -rf "$ICONSET_DIR"

echo ""
echo "Generating .ico file..."

# For ICO, we need multiple sizes. Using ImageMagick if available, otherwise just copy largest
if command -v magick &> /dev/null; then
    magick "$DARK_SOURCE" -define icon:auto-resize=256,128,64,48,32,16 "$ICONS_DIR/icon.ico"
elif command -v convert &> /dev/null; then
    convert "$DARK_SOURCE" -define icon:auto-resize=256,128,64,48,32,16 "$ICONS_DIR/icon.ico"
else
    echo "  Warning: ImageMagick not found. Using existing .ico or creating basic one."
    # Create a basic ico from png using sips (limited)
    sips -z 256 256 "$DARK_SOURCE" --out "$ICONS_DIR/icon_256.png" >/dev/null 2>&1
    # Note: sips cannot create .ico, so we'll leave existing one if present
fi

echo ""
echo "=== Icon Generation Complete ==="
echo ""
echo "Generated files:"
echo "  - Asset Catalog: $APPICONSET_DIR/"
echo "  - Standard icons: $ICONS_DIR/"
echo ""
echo "To compile the Asset Catalog into your app bundle, run:"
echo "  ./scripts/inject-assets-car.sh"
echo ""
