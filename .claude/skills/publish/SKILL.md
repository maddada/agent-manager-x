---
name: publish
description: Bump version and publish a new release to GitHub and Homebrew
argument-hint: <version>
disable-model-invocation: true
---

Publish a new release of Agent Manager X at version **$ARGUMENTS**.

Follow these steps exactly:

1. **Bump the version** to `$ARGUMENTS` in all three files:
   - `src-tauri/tauri.conf.json` (`"version"` field)
   - `package.json` (`"version"` field)
   - `src-tauri/Cargo.toml` (`version` field)

2. **Commit and push**:
   - Stage all changes (including any uncommitted work)
   - Commit with message: `bump version to $ARGUMENTS`
   - Push to `origin main`

3. **Run the release script**:
   - Execute `./scripts/release.sh` (no flags)
   - This builds both aarch64 and x64, signs with Developer ID, notarizes via Apple, creates a GitHub release with DMGs, and updates the Homebrew tap
   - Run it in the background and wait for completion
   - The script takes several minutes due to compilation and notarization

4. **Report results** when done, including the GitHub release URL and brew install command.
