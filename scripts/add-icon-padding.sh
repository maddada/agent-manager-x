#!/bin/bash
# Add proper macOS icon padding to match Apple's icon grid
# Apple recommends ~80% icon size with ~10% margins on each side

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_ROOT/assets/icon"
PADDED_DIR="$ASSETS_DIR/padded"

# Source images (1024x1024)
SOURCES=(
    "Icon-macOS-ClearLight-512x512@2x.png"
    "Icon-macOS-Default-512x512@2x.png"
    "Icon-macOS-TintedLight-512x512@2x.png"
    "Icon-macOS-Dark-512x512@2x.png"
    "Icon-macOS-ClearDark-512x512@2x.png"
    "Icon-macOS-TintedDark-512x512@2x.png"
)

# Icon should be ~80% of canvas (824px in 1024px canvas)
# This means ~100px padding on each side (10%)
CANVAS_SIZE=1024
ICON_SIZE=824  # 80% of 1024
PADDING=100    # (1024 - 824) / 2

echo "=== Adding macOS Icon Padding ==="
echo "Canvas: ${CANVAS_SIZE}x${CANVAS_SIZE}"
echo "Icon artwork: ${ICON_SIZE}x${ICON_SIZE} (centered)"
echo ""

mkdir -p "$PADDED_DIR"

for src in "${SOURCES[@]}"; do
    SRC_PATH="$ASSETS_DIR/$src"
    OUT_PATH="$PADDED_DIR/$src"

    if [ ! -f "$SRC_PATH" ]; then
        echo "Skipping (not found): $src"
        continue
    fi

    echo "Processing: $src"

    # Create a transparent canvas and composite the resized icon centered
    # Using sips to resize, then ImageMagick or Python to add padding

    if command -v magick &> /dev/null; then
        # ImageMagick available - use it for better quality
        magick "$SRC_PATH" \
            -resize ${ICON_SIZE}x${ICON_SIZE} \
            -gravity center \
            -background transparent \
            -extent ${CANVAS_SIZE}x${CANVAS_SIZE} \
            "$OUT_PATH"
    else
        # Fallback: use Python with PIL
        python3 << PYTHON_SCRIPT
from PIL import Image
import os

src = "$SRC_PATH"
out = "$OUT_PATH"
canvas_size = $CANVAS_SIZE
icon_size = $ICON_SIZE

# Open and resize the icon
img = Image.open(src).convert('RGBA')
img = img.resize((icon_size, icon_size), Image.LANCZOS)

# Create transparent canvas
canvas = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))

# Calculate position to center the icon
offset = (canvas_size - icon_size) // 2

# Paste icon centered
canvas.paste(img, (offset, offset), img)

# Save
canvas.save(out, 'PNG')
print(f"  Saved: {out}")
PYTHON_SCRIPT
    fi
done

echo ""
echo "=== Padding Complete ==="
echo "Padded icons saved to: $PADDED_DIR"
echo ""
echo "To use these icons, update build-macos-icons.sh to use the padded versions,"
echo "or copy them over the originals."
