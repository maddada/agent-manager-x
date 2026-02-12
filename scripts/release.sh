#!/bin/bash
set -e

# Release script for Agent Manager X
# This script builds, signs, notarizes, creates DMGs, publishes to GitHub, and updates Homebrew

# Configuration
APP_NAME="Agent Manager X"
BUNDLE_ID="com.agent-manager-x"
SIGNING_IDENTITY="YOUR_SIGNING_IDENTITY_HERE"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAURI_DIR="$PROJECT_ROOT/src-tauri"
HOMEBREW_TAP_REPO="maddada/homebrew-tap"

# Get version from tauri.conf.json
VERSION=$(grep '"version"' "$TAURI_DIR/tauri.conf.json" | head -1 | sed 's/.*"version": "\([^"]*\)".*/\1/')

echo "=== Agent Manager X Release Script ==="
echo "Version: $VERSION"
echo "Project root: $PROJECT_ROOT"
echo ""

# Check for required credentials
if [ -z "$APPLE_ID" ] || [ -z "$APPLE_PASSWORD" ] || [ -z "$APPLE_TEAM_ID" ]; then
    echo "Error: Missing Apple credentials. Please set:"
    echo "  APPLE_ID - Your Apple ID email"
    echo "  APPLE_PASSWORD - App-specific password"
    echo "  APPLE_TEAM_ID - Your Team ID"
    exit 1
fi

# Function to build for a specific architecture
build_arch() {
    local arch=$1
    local target=$2

    echo "=== Building for $arch ($target) ==="
    cd "$PROJECT_ROOT"
    pnpm run tauri build -- --target "$target"
    echo "Build complete for $arch"
}

# Function to sign app with hardened runtime
sign_app() {
    local arch=$1
    local target=$2
    local app_path="$TAURI_DIR/target/$target/release/bundle/macos/${APP_NAME}.app"

    echo "=== Signing app for $arch ==="
    codesign --force --deep --sign "$SIGNING_IDENTITY" --timestamp --options runtime "$app_path"
    echo "Signed: $app_path"
}

# Function to create DMG from signed app with Applications shortcut
create_dmg() {
    local arch=$1
    local target=$2
    local dmg_name="AgentManagerX_${VERSION}_${arch}.dmg"
    local app_path="$TAURI_DIR/target/$target/release/bundle/macos/${APP_NAME}.app"
    local output_dir="$PROJECT_ROOT/release"
    local dmg_path="$output_dir/$dmg_name"
    local dmg_temp_dir=$(mktemp -d)

    echo "=== Creating DMG for $arch ==="
    mkdir -p "$output_dir"
    rm -f "$dmg_path"

    # Copy signed app and create Applications symlink
    cp -R "$app_path" "$dmg_temp_dir/"
    ln -s /Applications "$dmg_temp_dir/Applications"

    # Create DMG with both app and Applications shortcut
    hdiutil create -volname "Agent Manager X" -srcfolder "$dmg_temp_dir" -ov -format UDZO "$dmg_path"

    # Cleanup
    rm -rf "$dmg_temp_dir"
    echo "DMG created at $dmg_path"
}

# Function to sign DMG
sign_dmg() {
    local arch=$1
    local dmg_name="AgentManagerX_${VERSION}_${arch}.dmg"
    local dmg_path="$PROJECT_ROOT/release/$dmg_name"

    echo "=== Signing DMG for $arch ==="
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$dmg_path"
    echo "Signed: $dmg_path"
}

# Function to notarize DMG
notarize_dmg() {
    local arch=$1
    local dmg_name="AgentManagerX_${VERSION}_${arch}.dmg"
    local dmg_path="$PROJECT_ROOT/release/$dmg_name"

    echo "=== Notarizing DMG for $arch ==="
    xcrun notarytool submit "$dmg_path" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait

    echo "=== Stapling notarization ticket for $arch ==="
    xcrun stapler staple "$dmg_path"
    echo "Notarization complete for $arch"
}

# Function to calculate SHA256
calc_sha256() {
    local arch=$1
    local dmg_name="AgentManagerX_${VERSION}_${arch}.dmg"
    local dmg_path="$PROJECT_ROOT/release/$dmg_name"

    shasum -a 256 "$dmg_path" | awk '{print $1}'
}

# Function to create GitHub release
create_github_release() {
    local aarch64_dmg="$PROJECT_ROOT/release/AgentManagerX_${VERSION}_aarch64.dmg"
    local x64_dmg="$PROJECT_ROOT/release/AgentManagerX_${VERSION}_x64.dmg"
    local aarch64_sha=$(calc_sha256 "aarch64")
    local x64_sha=$(calc_sha256 "x64")

    echo "=== Creating GitHub Release ==="

    # Create and push tag
    git tag "v$VERSION" 2>/dev/null || echo "Tag v$VERSION already exists"
    git push origin "v$VERSION" 2>/dev/null || echo "Tag already pushed"

    # Create release with DMGs
    gh release create "v$VERSION" \
        "$aarch64_dmg" \
        "$x64_dmg" \
        --title "v$VERSION" \
        --notes "## Downloads

- **Apple Silicon (M1/M2/M3)**: \`AgentManagerX_${VERSION}_aarch64.dmg\`
- **Intel**: \`AgentManagerX_${VERSION}_x64.dmg\`

## SHA256 Checksums
\`\`\`
$aarch64_sha  AgentManagerX_${VERSION}_aarch64.dmg
$x64_sha  AgentManagerX_${VERSION}_x64.dmg
\`\`\`

## Install via Homebrew
\`\`\`bash
brew tap maddada/tap
brew install --cask agent-manager-x
\`\`\`
"

    echo "GitHub release created: https://github.com/maddada/agent-manager-x/releases/tag/v$VERSION"
}

# Function to update Homebrew tap
update_homebrew() {
    local aarch64_sha=$(calc_sha256 "aarch64")
    local x64_sha=$(calc_sha256 "x64")
    local tmp_dir=$(mktemp -d)

    echo "=== Updating Homebrew Tap ==="

    cd "$tmp_dir"
    gh repo clone "$HOMEBREW_TAP_REPO" homebrew-tap

    cat > homebrew-tap/Casks/agent-manager-x.rb << EOF
cask "agent-manager-x" do
  version "$VERSION"

  on_arm do
    sha256 "$aarch64_sha"
    url "https://github.com/maddada/agent-manager-x/releases/download/v#{version}/AgentManagerX_#{version}_aarch64.dmg"
  end

  on_intel do
    sha256 "$x64_sha"
    url "https://github.com/maddada/agent-manager-x/releases/download/v#{version}/AgentManagerX_#{version}_x64.dmg"
  end

  name "Agent Manager X"
  desc "macOS desktop app to monitor running Claude Code sessions"
  homepage "https://github.com/maddada/agent-manager-x"

  depends_on macos: ">= :monterey"

  app "Agent Manager X.app"

  zap trash: [
    "~/Library/Preferences/com.agent-manager-x.plist",
    "~/Library/Saved Application State/com.agent-manager-x.savedState",
  ]
end
EOF

    cd homebrew-tap
    git add Casks/agent-manager-x.rb
    git commit -m "bump agent-manager-x to v$VERSION"
    git push

    cd "$PROJECT_ROOT"
    rm -rf "$tmp_dir"

    echo "Homebrew tap updated to v$VERSION"
}

# Main release process
main() {
    local skip_build=false
    local skip_notarize=false
    local skip_github=false
    local skip_homebrew=false
    local arch_filter=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-build)
                skip_build=true
                shift
                ;;
            --skip-notarize)
                skip_notarize=true
                shift
                ;;
            --skip-github)
                skip_github=true
                shift
                ;;
            --skip-homebrew)
                skip_homebrew=true
                shift
                ;;
            --arch)
                arch_filter=$2
                shift 2
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --skip-build      Skip the build step (use existing builds)"
                echo "  --skip-notarize   Skip notarization (for testing)"
                echo "  --skip-github     Skip GitHub release creation"
                echo "  --skip-homebrew   Skip Homebrew tap update"
                echo "  --arch <arch>     Build only for specific arch (aarch64 or x64)"
                echo "  --help            Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Determine which architectures to build
    local archs=()
    if [ -z "$arch_filter" ]; then
        archs=("aarch64" "x64")
    else
        archs=("$arch_filter")
    fi

    # Helper function to map arch to target
    get_target() {
        case "$1" in
            aarch64) echo "aarch64-apple-darwin" ;;
            x64) echo "x86_64-apple-darwin" ;;
        esac
    }

    # Build
    if [ "$skip_build" = false ]; then
        for arch in "${archs[@]}"; do
            build_arch "$arch" "$(get_target "$arch")"
        done
    fi

    # Sign apps
    for arch in "${archs[@]}"; do
        sign_app "$arch" "$(get_target "$arch")"
    done

    # Create DMGs
    for arch in "${archs[@]}"; do
        create_dmg "$arch" "$(get_target "$arch")"
    done

    # Sign DMGs
    for arch in "${archs[@]}"; do
        sign_dmg "$arch"
    done

    # Notarize DMGs
    if [ "$skip_notarize" = false ]; then
        for arch in "${archs[@]}"; do
            notarize_dmg "$arch"
        done
    fi

    # Print summary
    echo ""
    echo "=== Build Complete ==="
    echo "Version: $VERSION"
    echo ""
    echo "DMG files in $PROJECT_ROOT/release/:"
    for arch in "${archs[@]}"; do
        local dmg_name="AgentManagerX_${VERSION}_${arch}.dmg"
        local sha=$(calc_sha256 "$arch")
        echo "  $dmg_name"
        echo "    SHA256: $sha"
    done

    # Create GitHub release
    if [ "$skip_github" = false ]; then
        create_github_release
    fi

    # Update Homebrew tap
    if [ "$skip_homebrew" = false ]; then
        update_homebrew
    fi

    echo ""
    echo "=== Release Complete ==="
    echo "Version: $VERSION"
    echo "GitHub: https://github.com/maddada/agent-manager-x/releases/tag/v$VERSION"
    echo "Homebrew: brew install --cask maddada/tap/agent-manager-x"
}

main "$@"
