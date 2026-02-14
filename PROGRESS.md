# PROGRESS

## 2026-02-13
- Initialized macOS SwiftUI scaffolding with `xcodegen` configuration.
- Added minimal compile-ready app target and source/resource directory layout.
- Deferred all feature implementation logic by design.

## 2026-02-13 (Core models and settings persistence)
- Added `App/Sources/Core/Models` with compile-ready shared domain models: `AgentType`, `SessionStatus`, `Session`, `SessionsResponse`, `GitDiffStats`, `ProjectGroup`, plus display/card-click enums and notification install-state types.
- Added `App/Sources/Core/Settings` with typed settings enums, storage keys aligned to existing TS key strings, and a `UserDefaults`-backed `SettingsStore`.
- Implemented typed getters/setters for hotkeys, mini viewer behavior, editor/terminal defaults and custom commands, card click action, display mode, experimental VS Code opening, theme (dark/light), background image, overlay settings, per-project run/build commands, and per-session custom names/URLs.
- Verified compile success with `xcodebuild -project AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`.

## 2026-02-13 (Core native services: system/session/actions)
- Added `App/Sources/Services/System/ShellCommandRunner.swift` with safe command execution (cwd/env/timeout), structured stdout/stderr capture, and shell-command helper support.
- Added `App/Sources/Services/System/ProcessIntrospectionService.swift` with `ps`-based process snapshots and `lsof` helpers for cwd/open-file/session-file discovery, descendant traversal, and process-group kill primitives.
- Added `App/Sources/Services/Session/SessionParsingSupport.swift` with shared parsing/status/date/path/git utilities, JSONL extraction, Claude status inference helpers, and session sorting support.
- Added `App/Sources/Services/Session/ClaudeSessionDetector.swift` implementing:
  - running `claude` process detection with subagent/ACP filtering
  - project root scanning across `~/.claude/projects` and profile roots
  - JSONL parsing with message-role/tool signals + stale/idle thresholds
  - active subagent counting from `agent-*.jsonl`
  - best-effort GitHub remote URL derivation
  - pid-based dedupe with active-session preference.
- Added `App/Sources/Services/Session/CodexSessionDetector.swift` implementing:
  - `codex` process detection excluding `app-server`
  - session roots from inferred `CODEX_HOME`-like paths with fallback roots
  - recursive newest-session-file collection and parsing
  - status derivation from CPU/role/age rules
  - background helper classification for low-signal low-CPU sessions.
- Added `App/Sources/Services/Session/OpenCodeSessionDetector.swift` implementing:
  - `opencode` process detection and active session file matching
  - storage scanning at `~/.local/share/opencode/storage`
  - project/session/message/part parsing and latest-session matching
  - status derivation aligned to current app behavior.
- Added `App/Sources/Services/Session/SessionDetectionService.swift` aggregating all 3 detectors into `SessionsResponse` with active-first sort, separate background sort, and count metrics.
- Added `App/Sources/Services/Actions/GitDiffStatsService.swift` implementing `git -C <path> diff --numstat HEAD` additions/deletions with graceful zeroed fallback.
- Added `App/Sources/Services/Actions/CoreActionsService.swift` implementing non-UI core actions:
  - kill session pid + descendants + process group retry logic
  - open in editor by setting (including custom command)
  - open in terminal by setting (including custom command)
  - run project command in terminal
  - focus session via tty (iTerm/Terminal AppleScript) with path fallback.
- Verified compile success with:
  - `xcodebuild -project AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`.

## 2026-02-13 (Native services: notifications/hotkeys/menu bar/mini viewer)
- Added `App/Sources/Services/Notifications/NotificationService.swift` with parity behaviors for:
  - install/check/uninstall of `~/.claude/hooks/notify-local-tts.sh`
  - `settings.json` `hooks.Stop` hook insertion/removal with duplicate protection
  - `~/.claude/CLAUDE.md` Voice Notifications section append/removal
  - bell mode check/toggle via full script-content replacement (`say` vs `afplay`).
- Added `App/Sources/Services/Hotkeys/GlobalHotkeyManager.swift` implementing:
  - separate register/unregister flows for app-toggle and mini-viewer hotkeys
  - callback-based API for each hotkey target
  - robust shortcut parser for strings like `Command+Control+Shift+Space` with key/modifier aliases and fallback registration behavior.
- Added `App/Sources/Services/MenuBar/MenuBarService.swift` implementing:
  - `NSStatusItem` creation with template tray icon
  - left-click callback for show/focus behavior
  - right-click menu with `Show Window` and `Quit`
  - dynamic tray title formatting parity (`<total>` and `<total> (<waiting> idle)`).
- Added `App/Sources/Services/MiniViewer/MiniViewerController.swift` implementing:
  - side + experimental VS Code opening state controls
  - helper source resolution, `xcrun swiftc -O` compilation to Application Support, launch lifecycle management
  - payload streaming to helper every 3 seconds
  - stdout action handling: `focusSession` => open in editor(code) -> focus session -> open terminal fallback chain; `endSession` => kill session
  - show/toggle/shutdown and running-state checks.
- Copied native mini-viewer helper resources exactly to `App/Resources/native-mini-viewer/`:
  - `MiniViewer.swift`
  - `icons/{claude,codex,opencode}.{svg,png}`
- Copied tray icon asset to `App/Resources/tray/tray-icon.png` from the current app.
- Verification:
  - confirmed copied resource files are byte-identical to source files via `cmp`
  - type-checked new owned notification/hotkey/menu-bar services successfully
  - type-checked `MiniViewerController` with dependency stubs successfully
  - full repository type-check is currently blocked by pre-existing errors outside owned paths.

## 2026-02-13 (SwiftUI app store + full native UX wiring)
- Implemented `App/Sources/AppState/AppStore.swift` as the central app state/store (`ObservableObject`) with:
  - 3-second polling via `SessionDetectionService`
  - stable foreground session ordering merge behavior aligned to web ordering tiers
  - tracked state for sessions/background sessions/counts/agent counts/loading/error
  - actions for refresh, kill-by-type, kill-idle, kill-stale, kill background one/all, focus/open/kill session, open project, and run project command
  - menu bar integration (`MenuBarService`) including title/count updates and show/quit callbacks
  - global and mini viewer hotkey registration/callback flow (`GlobalHotkeyManager`)
  - mini viewer lifecycle/settings integration (`MiniViewerController`) including side, experimental VS Code flag, and optional show-on-start
  - notification install/bell mode state checks and install/uninstall/toggle actions (`NotificationService`)
  - settings-backed persistence wiring for theme/background/overlay/click action/editor/terminal/hotkeys/mini viewer options/custom names/custom URLs/project commands.
- Replaced scaffold app shell:
  - Updated `App/Sources/AgentManagerXApp.swift` to inject shared `AppStore`
  - Updated `App/Sources/ContentView.swift` to render the new dashboard and apply theme preference.
- Added modular UI under `App/Sources/Views`:
  - `MainDashboardView.swift` with full main window UX:
    - header badges, BG popover panel with per-item close + close-all,
    - idle/stale quick-kill buttons,
    - per-agent kill-all buttons,
    - bell/voice toggle when installed,
    - list/grid mode toggle,
    - settings + refresh controls.
    - loading/error/empty states and list/adaptive-grid content modes.
    - project grouping with clickable headers (respecting click-action setting), branch and git +/- stats display, and run/build quick actions with edit dialog flow.
    - session cards/items with status badge/colors, preview + full-text help tooltip, pid/cpu/memory/time/subagent line, agent marker, top-left kill button, context menu actions, rename dialog, URL dialog, custom URL launcher, and GitHub open action.
  - `SettingsSheetView.swift` implementing settings scope:
    - light/dark theme selector,
    - background image + overlay color/opacity,
    - click-action selector,
    - default editor + custom command + experimental VS Code toggle,
    - default terminal + custom command,
    - global hotkey recorder/save/clear,
    - mini viewer hotkey recorder/save/clear + side + show-on-start,
    - notification install/uninstall + bell mode,
    - inline error/saved confirmation surfaces.
  - `HotkeyRecorderRow.swift` reusable key-combo recorder control.
  - `WindowAccessor.swift` to bind and manage the main window reference for focus/toggle behavior.
- Verification:
  - `xcodebuild` against the in-place project currently fails because `AgentManagerX.xcodeproj` only includes scaffold files and not `App/Sources/**`.
  - Generated-project validation (`xcodegen` + `xcodebuild`) was executed in an isolated temp copy to avoid modifying non-owned paths.
  - In the generated build, newly added app store/UI files compile; build is blocked by a pre-existing compile error in non-owned file `App/Sources/Services/System/ProcessIntrospectionService.swift` (argument order in `split(...)`).

## 2026-02-13 (Integration fixes + final compile validation)
- Regenerated `AgentManagerX.xcodeproj` using `xcodegen generate` so all newly added source/resource files are included in the build.
- Fixed compile blocker in `App/Sources/Services/System/ProcessIntrospectionService.swift` by correcting `split` argument ordering for Swift 6 toolchain compatibility.
- Fixed compile blocker in `App/Sources/Services/Session/ClaudeSessionDetector.swift` by correcting `lastMessage` truncation assignment to mutable binding.
- Added app-termination cleanup hook in `App/Sources/ContentView.swift` to call `store.stop()` on `NSApplication.willTerminateNotification` (ensures hotkeys/menu bar/mini viewer shutdown path runs).
- Verified full native project compiles successfully with:
  - `xcodebuild -project AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`

## 2026-02-13 (Claude session detection fallback hardening)
- Updated `App/Sources/Services/Session/ClaudeSessionDetector.swift` to always emit a process-backed Claude session when active-file parsing and project-directory matching fail.
- Added conservative fallback defaults: project path prefers process `cwd`, status derives from CPU plus observable file activity recency when available, and safe metadata defaults are applied when unavailable.
- Preserved visibility-first UX by keeping fallback Claude sessions foreground (`isBackground = false`) so active Claude processes are not silently dropped.
- Verified with `xcodebuild -project AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`.

## 2026-02-13 (AppStore refresh/diff responsiveness hardening)
- Updated `App/Sources/AppState/AppStore.swift` polling refresh flow to allow only one in-flight detection refresh at a time, with a coalesced `hasPendingRefresh` flag so bursty timer/manual refresh triggers collapse into a single follow-up run.
- Moved git diff stats computation out of the main-actor `apply(response:)` path onto a dedicated background queue, while keeping TTL caching behavior and adding generation checks so stale async results do not overwrite newer session state.

## 2026-02-13 (VS Code open parity + overflow layout hardening)
- Updated editor open flow to match old Tauri behavior more closely by routing card-click/editor opens through `CoreActionsService.openInEditor(...)` with explicit `experimentalVSCodeSessionOpening` + `projectName` inputs.
- Added PATH-based executable resolution in `CoreActionsService` so CLI editors/terminals (`code`, `cursor`, `zed`, `kitty`, etc.) are launched with enriched login-shell PATH semantics instead of relying on unresolved relative executable paths.
- Preserved experimental VS Code path opening behavior in native (`/usr/bin/open -b com.microsoft.VSCode <path>`) inside `CoreActionsService` with fallback to CLI open.
- Hardened `MainDashboardView` against horizontal overflow by adding truncation and compression-priority constraints for app header, project header, and session card text/metric rows, keeping action controls visible in narrow windows.
- Verified native project compiles successfully after these changes:
  - `xcodebuild -project /Users/madda/dev/agent-manager-x/AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`

## 2026-02-13 (Offscreen card rendering fix in list/grid containers)
- Further hardened `MainDashboardView` layout after reproducing that session/project cards could still render partially outside the window.
- Constrained list/grid content to viewport width by:
  - using `LazyVStack(alignment: .leading, ...)` with explicit `maxWidth: .infinity`,
  - applying per-card `frame(maxWidth: .infinity, alignment: .leading)`,
  - and keeping scroll containers pinned to `.topLeading`.
- Added `ViewThatFits(in: .horizontal)` for the app header left area so title+badges gracefully collapse to badges-only when controls consume width, matching old app behavior more closely.
- Verified compile success:
  - `xcodebuild -project /Users/madda/dev/agent-manager-x/AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`

## 2026-02-13 (Agent logo indicators in main session cards)
- Replaced text-only session agent markers (`CL/CX/OC`) with actual agent logos in `MainDashboardView` session cards.
- Wired icon loading to use the copied high-quality PNGs (`claude.png`, `codex.png`, `opencode.png`) with a robust lookup order:
  - bundled subdirectory (`native-mini-viewer/icons`),
  - bundled root fallback,
  - local development-path fallback under `App/Resources/native-mini-viewer/icons`.
- Kept the old text badge as a fallback if an icon cannot be loaded.
- Verified compile success:
  - `xcodebuild -project /Users/madda/dev/agent-manager-x/AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`

## 2026-02-13 (Duplicate session-id crash fix)
- Fixed a runtime crash caused by duplicate logical session IDs appearing in foreground collections (`ForEach` + dictionary merge paths).
- Added a UI/render-safe identity on `Session` (`renderID = agentType + pid + logical id`) while preserving the original logical `session.id` for settings/URL/custom-name keys.
- Updated `AppStore.mergeWithStableOrder(...)` to key ordering/priority merge dictionaries by `renderID` instead of `id`.
- Updated session and background `ForEach` blocks in `MainDashboardView` to use `id: \.renderID`.
- Verified compile success:
  - `xcodebuild -project /Users/madda/dev/agent-manager-x/AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`

## 2026-02-14 (SVG-only agent indicators)
- Switched agent marker rendering to SVG-only assets and removed PNG fallback logic from both `MainDashboardView` and `MiniViewer`.
- Deleted legacy PNG icon files for Claude/Codex/OpenCode.
- Verified compile success:
  - `xcodebuild -project /Users/madda/dev/agent-manager-x/AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`

- 2026-02-14: Reduced refresh CPU load by preventing timer-driven in-flight refresh chaining, short-circuiting Codex/OpenCode fallback scans when direct active sessions resolve, and caching `ps` snapshots across detector runs.
- 2026-02-14: Confirmed native app does not use `WebView`/`WebKit`, reviewed and kept the performance patch, and documented runtime decisions in `DECISIONS.md` for traceability.

## 2026-02-14 (Hover-only close buttons + no tab-focus outline in header controls)
- Updated `MainDashboardView` header control buttons (top-right controls) to be non-focusable so keyboard tab selection no longer draws the blue focus outline.
- Updated project-header close button visibility to show only while hovering that project header row.
- Updated session-card close button visibility to show only while hovering that individual session card.
- Verified compile success:
  - `xcodebuild -project /Users/madda/dev/agent-manager-x/AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`

## 2026-02-14 (Skip <turn_aborted> preview message)
- Implemented a parser-level suppression rule for control/sentinel messages (including `<turn_aborted...>`) in `SessionParsingSupport`.
- Wired Claude/Codex/OpenCode message extraction paths to skip suppressed messages so the previous real message is retained as `lastMessage`.
- This fixes both dashboard cards and native mini viewer rows because both surfaces consume the same parsed `Session.lastMessage` value.
- Verified compile success:
  - `xcodebuild -project /Users/madda/dev/agent-manager-x/AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`

## 2026-02-14 (Project/session middle-click close + persistent red close styling)
- Updated `MainDashboardView` project header close button to use explicit red circular styling (white `xmark` on red background) so it does not shift to gray/secondary styling when shown.
- Added macOS middle-click handling to project headers so middle-click triggers the same destructive action as the project close button (`onKillAll`).
- Added macOS middle-click handling to session cards so middle-click triggers the same action as the session close button (`store.killSession(session)`).
- Updated session close button styling to use full `Color.red` fill (no opacity tint) for consistent destructive emphasis.

## 2026-02-14 (Separate main/mini UI element size settings)
- Added new `UIElementSize` enum (`small`, `medium`, `large`, `extraLarge`) with user-facing labels `Small`, `Medium`, `Large`, and `Extra Large`.
- Added two persisted settings in `SettingsStore`/`SettingsKeys`, both defaulting to `.small`:
  - main app UI element size
  - mini viewer UI element size.
- Extended `AppStore` to publish both values, initialize from settings, and provide update methods.
- Wired mini viewer size setting into `MiniViewerController` startup/change flow and included it in helper payload updates.
- Added two Settings pickers in `SettingsSheetView`:
  - `Main App UI Element Size`
  - `Mini Viewer UI Element Size`.
- Applied main app global font scaling via root-level `.dynamicTypeSize(...)` mapping in `ContentView`.
- Adjusted main-app mapping so `Small` equals baseline/current sizing (`.large`) and larger options step up from there (`.xLarge`, `.xxLarge`, `.xxxLarge`).
- Applied mini viewer text scaling by introducing payload-driven `uiElementSize` handling and environment-based font scaling in `App/Resources/native-mini-viewer/MiniViewer.swift`.
- Verified compile success with:
  - `xcodebuild -project /Users/madda/dev/agent-manager-x/AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`
