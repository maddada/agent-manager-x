#!/bin/bash
set -e

# Release script for Agent Manager X
# This script builds, signs, notarizes, creates DMGs, publishes to GitHub, and updates Homebrew

# Configuration
APP_NAME="Agent Manager X"
BUNDLE_ID="com.agent-manager-x"
SIGNING_IDENTITY="Developer ID Application: Mohamad Youssef (KTKP595G3B)"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAURI_DIR="$PROJECT_ROOT/src-tauri"
HOMEBREW_TAP_REPO="maddada/homebrew-tap"
NOTARY_PROFILE="notarytool-profile"
RELEASE_DIR="$PROJECT_ROOT/release"
BUNDLE_DIR="$TAURI_DIR/target/release/bundle/macos"

# Get version from tauri.conf.json
VERSION=$(grep '"version"' "$TAURI_DIR/tauri.conf.json" | head -1 | sed 's/.*"version": "\([^"]*\)".*/\1/')

echo "=== Agent Manager X Release Script ==="
echo "Version: $VERSION"
echo "Project root: $PROJECT_ROOT"
echo ""

# Function to sign an app bundle with hardened runtime
sign_app() {
    local app_path=$1
    echo "  Signing: $app_path"
    codesign --force --deep --sign "$SIGNING_IDENTITY" --timestamp --options runtime "$app_path"
}

# Function to create and sign a DMG
create_signed_dmg() {
    local arch=$1
    local app_path=$2
    local dmg_name="AgentManagerX_${VERSION}_${arch}.dmg"
    local dmg_path="$RELEASE_DIR/$dmg_name"
    local dmg_temp_dir=$(mktemp -d)

    echo "  Creating DMG: $dmg_name"
    mkdir -p "$RELEASE_DIR"
    rm -f "$dmg_path"

    cp -R "$app_path" "$dmg_temp_dir/"
    ln -s /Applications "$dmg_temp_dir/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$dmg_temp_dir" -ov -format UDZO "$dmg_path"
    rm -rf "$dmg_temp_dir"

    echo "  Signing DMG"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$dmg_path"
    echo "  DMG ready: $dmg_path"
}

# Function to notarize a DMG
notarize_dmg() {
    local arch=$1
    local dmg_name="AgentManagerX_${VERSION}_${arch}.dmg"
    local dmg_path="$RELEASE_DIR/$dmg_name"

    echo "=== Notarizing $dmg_name ==="
    xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "  Stapling notarization ticket"
    xcrun stapler staple "$dmg_path"
    echo "  Notarization complete"
}

# Function to calculate SHA256
calc_sha256() {
    local arch=$1
    local dmg_path="$RELEASE_DIR/AgentManagerX_${VERSION}_${arch}.dmg"
    shasum -a 256 "$dmg_path" | awk '{print $1}'
}

# Function to create GitHub release
create_github_release() {
    local aarch64_dmg="$RELEASE_DIR/AgentManagerX_${VERSION}_aarch64.dmg"
    local x64_dmg="$RELEASE_DIR/AgentManagerX_${VERSION}_x64.dmg"
    local aarch64_sha=$(calc_sha256 "aarch64")
    local x64_sha=$(calc_sha256 "x64")

    echo "=== Creating GitHub Release ==="

    git tag "v$VERSION" 2>/dev/null || echo "Tag v$VERSION already exists"
    git push origin "v$VERSION" 2>/dev/null || echo "Tag already pushed"

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
brew install --cask maddada/tap/agent-manager-x
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
    git commit -m "Add agent-manager-x cask v$VERSION"
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

    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-build) skip_build=true; shift ;;
            --skip-notarize) skip_notarize=true; shift ;;
            --skip-github) skip_github=true; shift ;;
            --skip-homebrew) skip_homebrew=true; shift ;;
            --help)
                echo "Usage: $0 [options]"
                echo "  --skip-build      Skip building (use existing builds)"
                echo "  --skip-notarize   Skip Apple notarization"
                echo "  --skip-github     Skip GitHub release creation"
                echo "  --skip-homebrew   Skip Homebrew tap update"
                exit 0
                ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    # Staging directory for prepared app bundles
    local staging_dir="$PROJECT_ROOT/release/staging"
    mkdir -p "$staging_dir"

    if [ "$skip_build" = false ]; then
        # === Step 1: Build aarch64 (native) ===
        echo "=== Building aarch64 (native) ==="
        cd "$PROJECT_ROOT"
        pnpm run tauri:build
        echo "Build complete for aarch64"

        # Copy the aarch64 bundle to staging
        rm -rf "$staging_dir/aarch64"
        mkdir -p "$staging_dir/aarch64"
        cp -R "$BUNDLE_DIR/${APP_NAME}.app" "$staging_dir/aarch64/"

        # === Step 2: Build x64 (cross-compile) ===
        echo "=== Building x64 (cross-compile) ==="
        cd "$PROJECT_ROOT"
        pnpm run tauri:build -- --target x86_64-apple-darwin
        echo "Build complete for x64"

        # Create x64 bundle by copying the app template and swapping the binary
        rm -rf "$staging_dir/x64"
        mkdir -p "$staging_dir/x64"
        cp -R "$BUNDLE_DIR/${APP_NAME}.app" "$staging_dir/x64/"
        # Replace the binary with the x64 one
        cp "$TAURI_DIR/target/x86_64-apple-darwin/release/agent-manager-x" \
           "$staging_dir/x64/${APP_NAME}.app/Contents/MacOS/agent-manager-x"
    fi

    # === Step 3: Sign and create DMGs ===
    echo "=== Signing aarch64 ==="
    sign_app "$staging_dir/aarch64/${APP_NAME}.app"
    create_signed_dmg "aarch64" "$staging_dir/aarch64/${APP_NAME}.app"

    echo "=== Signing x64 ==="
    sign_app "$staging_dir/x64/${APP_NAME}.app"
    create_signed_dmg "x64" "$staging_dir/x64/${APP_NAME}.app"

    # === Step 4: Notarize ===
    if [ "$skip_notarize" = false ]; then
        notarize_dmg "aarch64"
        notarize_dmg "x64"
    fi

    # === Summary ===
    echo ""
    echo "=== Build Complete ==="
    echo "Version: $VERSION"
    for arch in aarch64 x64; do
        local sha=$(calc_sha256 "$arch")
        echo "  AgentManagerX_${VERSION}_${arch}.dmg"
        echo "    SHA256: $sha"
    done

    # === Step 5: GitHub release ===
    if [ "$skip_github" = false ]; then
        create_github_release
    fi

    # === Step 6: Homebrew tap ===
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
