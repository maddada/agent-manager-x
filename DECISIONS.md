# DECISIONS

## 2026-02-13 - Initial scaffold boundary
- Decision: Create only baseline project scaffolding for a macOS SwiftUI app.
- Rationale: Establish a stable foundation for parallel feature work without premature implementation.
- Consequence: Feature modules, app behavior, and domain logic remain intentionally unimplemented.

## 2026-02-13 - Native settings compatibility and simplification
- Decision: Reuse the exact storage key strings from the TypeScript app for the native `UserDefaults` settings store.
- Rationale: Preserves cross-implementation naming consistency and reduces migration risk as native replaces web/tauri pieces.
- Consequence: Native code intentionally carries forward the existing `expiremental` key typo for compatibility.

- Decision: Constrain native theme preference to `dark`/`light` while still accepting legacy saved theme values as input.
- Rationale: Matches native-port scope while avoiding broken behavior for users with older theme values.
- Consequence: Persisted theme values from native are normalized to two options, and legacy light-theme names map to `.light`.

## 2026-02-13 - Core native service layer architecture for sessions/actions
- Decision: Implement the native service layer as modular Swift services under `App/Sources/Services/{System,Session,Actions}` with shared helpers in `SessionParsingSupport`.
- Rationale: Keeps process inspection, per-agent detection logic, and actions decoupled so behavior can evolve per agent without cross-impact.
- Consequence: Service APIs are compile-ready and reusable by any future UI/view-model wiring.

- Decision: Mirror Tauri status heuristics and sorting behavior closely, including active-first priority, background session separation, stale/idle thresholds, Claude tool/message role signals, Codex low-signal background classification, and OpenCode message-part parsing.
- Rationale: Preserves expected operational semantics while moving to native Swift implementation.
- Consequence: Session lists and counts should remain behaviorally aligned with the current app for common runtime scenarios.

- Decision: Use `ps` + `lsof` command-based process introspection with lightweight parsing instead of private APIs.
- Rationale: Matches requested scope, keeps implementation transparent, and avoids tighter coupling to unstable platform internals.
- Consequence: Some metadata (like explicit env var maps) is inferred heuristically when unavailable, with robust fallback paths.

## 2026-02-13 - Native notifications/hotkeys/menu bar/mini viewer service strategy
- Decision: Re-implement notification install state and bell mode using the same filesystem paths, hook shape, and script semantics as the existing app (`~/.claude/hooks/notify-local-tts.sh`, `settings.json` `hooks.Stop`, and `CLAUDE.md` Voice Notifications section handling).
- Rationale: Ensures behavioral parity and avoids migration drift while replacing Tauri handlers with native Swift services.
- Consequence: Notification behavior and installation detection remain compatible with existing user environments.

- Decision: Use Carbon global hotkeys (`RegisterEventHotKey`) with a dedicated parser for string shortcuts and per-target registration (`appToggle` vs `miniViewerToggle`).
- Rationale: Provides global shortcut reliability with explicit callback routing and simple API boundaries.
- Consequence: Parser accepts common aliases and applies fallback shortcut registration when input is malformed.

- Decision: Implement menu bar behavior with manual left/right click handling on `NSStatusItem` rather than default left-click menu display.
- Rationale: Requirement prioritizes left-click show/focus behavior while still exposing a tray menu (`Show Window`, `Quit`).
- Consequence: Left click always routes to show/focus callback; right click opens the status menu.

- Decision: Implement mini viewer as an external helper lifecycle service that compiles `MiniViewer.swift` into Application Support, streams payload every 3s, and handles helper stdout actions with a deterministic fallback chain.
- Rationale: Mirrors current architecture and keeps viewer UI process isolated from app lifecycle concerns.
- Consequence: `focusSession` attempts VS Code/code first, then terminal focus, then terminal open; side and experimental VS Code flags are managed by the controller state and persisted via settings.

## 2026-02-13 - Native app state/UI composition and parity strategy
- Decision: Implement a single `@MainActor` `AppStore` as the source of truth for session polling, action orchestration, settings persistence, and service integration (menu bar/hotkeys/mini viewer/notifications).
- Rationale: Keeps session data flow and cross-cutting app lifecycle concerns centralized, while enabling SwiftUI views to remain mostly declarative and lightweight.
- Consequence: UI components consume store-published state and trigger explicit store actions, minimizing duplicated side-effect logic in views.

- Decision: Mirror web stable-order semantics using coarse status tiers (`active` vs `idle` vs `stale`) when merging refreshed sessions.
- Rationale: Avoids noisy card reordering while preserving meaningful reorder events when session priority truly changes.
- Consequence: Foreground list behavior remains close to the current app UX during 3-second polling.

- Decision: Use an adaptive SwiftUI grid as the masonry approximation and preserve grouped-by-project presentation in both list and grid modes.
- Rationale: Satisfies parity requirements with native SwiftUI primitives while keeping implementation maintainable.
- Consequence: Layout is responsive and visually close to the web app, with lower complexity than full masonry algorithms.

- Decision: Validate compile behavior in an isolated generated-project copy (`xcodegen` + `xcodebuild`) rather than editing non-owned project files.
- Rationale: Ownership constraints prohibit modifying `AgentManagerX.xcodeproj`, but app-wide compile validation still needs to include new source files.
- Consequence: Verification confirms new store/UI code compiles; remaining failure is an existing non-owned service issue.

## 2026-02-13 - Final integration hardening
- Decision: Regenerate the Xcode project via `xcodegen` after service/UI migration instead of hand-editing `.xcodeproj` entries.
- Rationale: Ensures all source/resource additions are consistently captured and reduces project-file drift risk.
- Consequence: Build/test instructions now assume `xcodegen generate` as part of local setup when project layout changes.

- Decision: Add explicit shutdown path on app terminate (`NSApplication.willTerminateNotification` -> `store.stop()`).
- Rationale: Ensures hotkey registrations, menu bar service, and mini viewer helper are torn down predictably.
- Consequence: Native services have cleaner lifecycle behavior and reduced chance of orphaned helper/hotkey state.

## 2026-02-13 - Claude process-only fallback policy
- Decision: In `ClaudeSessionDetector`, emit a process-only fallback session for unmatched Claude PIDs after active-file and project-file matching attempts are exhausted.
- Rationale: Prevents active Claude processes from disappearing due to transient file-parsing failures or path-matching edge cases.
- Consequence: Claude session visibility is more robust; fallback metadata remains conservative (prefer `cwd` for project path, infer status from CPU plus observable activity when possible, and use safe defaults when signal is missing).

## 2026-02-13 - AppStore refresh and diff-stats concurrency strategy
- Decision: Replace refresh-generation queue draining with a single in-flight detection refresh plus a coalesced pending-refresh flag.
- Rationale: Polling/manual refresh bursts were queuing redundant detection work; coalescing preserves eventual freshness while preventing backlog growth.
- Consequence: At most one detection run executes at a time, and any number of overlap triggers schedule exactly one immediate follow-up refresh.

- Decision: Compute git diff stats asynchronously on a background queue and guard main-thread publication with a monotonic generation token.
- Rationale: Synchronous git diff calls in `apply(response:)` were blocking the main actor and causing UI hitching under load.
- Consequence: `apply(response:)` remains lightweight; stats update shortly after refresh, and older async computations are dropped instead of overwriting newer state.

## 2026-02-13 - Editor launch parity and responsive overflow policy
- Decision: Centralize all editor opens through `CoreActionsService.openInEditor(...)` and include native equivalents of old Tauri inputs (`experimentalVSCodeSessionOpening`, `projectName`) instead of splitting experimental logic in `AppStore`.
- Rationale: Keeps behavior consistent across click paths and reduces divergence from the old implementation.
- Consequence: Session-card clicks and explicit open actions now use one launch path with a predictable fallback sequence.

- Decision: Resolve non-absolute executables via an enriched login-shell PATH before launching processes.
- Rationale: Bundled macOS apps often run with a minimal PATH, which breaks editor/terminal CLI commands unless PATH is explicitly enriched and searched.
- Consequence: Commands like `code`, `cursor`, `zed`, `kitty`, and similar now launch reliably when installed in user PATH locations.

- Decision: Prefer text truncation/compression over control overflow in dashboard headers and session rows.
- Rationale: The old app prioritizes keeping controls accessible while collapsing title/text under width pressure.
- Consequence: In narrow window sizes, titles/metadata truncate first and action controls remain onscreen instead of content shifting off the left/right edges.

## 2026-02-13 - Viewport-width enforcement for list/grid content
- Decision: Force project/session containers to adopt viewport width (`maxWidth: .infinity`, leading alignment) inside list/grid scroll views instead of relying on intrinsic content width.
- Rationale: Intrinsic-width stacks can exceed the visible scroll viewport and render partially off-window before truncation logic engages.
- Consequence: Cards now stay fully within the window bounds in both list and grid modes, while text truncates as needed.

- Decision: Use `ViewThatFits(in: .horizontal)` for the header's left section to collapse from `title + badges` to `badges-only` under width pressure.
- Rationale: Better matches the old app’s responsive behavior and avoids left-edge clipping artifacts when right-side controls are dense.
- Consequence: Header remains stable and readable without controls moving offscreen.

## 2026-02-13 - Agent indicator icon policy
- Decision: Replace text agent markers (`CL/CX/OC`) with high-quality agent logo images in the main session card UI.
- Rationale: Matches the visual language of the old app resources and improves scanability versus ambiguous two-letter tokens.
- Consequence: Session cards now display Claude/Codex/OpenCode logos, with a text fallback retained for resilience when icon files are unavailable.

- Decision: Resolve agent logos with layered fallback (bundle subdirectory -> bundle root -> development path derived from `#filePath`).
- Rationale: Current local runs may not always package resources in identical locations; fallback keeps UI stable during development and packaging transitions.
- Consequence: Icons render reliably in the current development environment without blocking on resource-bundle refactors.

## 2026-02-13 - Session identity strategy for UI stability
- Decision: Introduce a render-safe per-process identity (`Session.renderID = agentType + pid + logical session id`) and use it for UI list identity and stable-order merge maps.
- Rationale: Logical session IDs can legitimately repeat across multiple active processes; using them directly as unique keys causes SwiftUI `ForEach` undefined behavior and dictionary construction crashes.
- Consequence: Duplicate logical IDs no longer crash the app, while persisted per-session settings continue using the original logical `session.id`.

## 2026-02-14 - SVG-only agent marker policy
- Decision: Standardize agent marker assets on SVG-only and remove PNG fallback handling in `MainDashboardView` and `MiniViewer`.
- Rationale: SVG assets provide consistent rendering quality at multiple sizes/scales and eliminate extra fallback/resource-maintenance complexity.
- Consequence: Claude/Codex/OpenCode PNG icon variants are no longer required; marker rendering now depends on SVG resources as the single source of truth.

## 2026-02-14 - Refresh load-shedding and detector fast-path policy
- Decision: Timer-triggered refreshes no longer enqueue an immediate follow-up refresh when one is already in-flight; only non-timer refresh calls can set the pending-refresh flag.
- Rationale: Full session detection currently takes around or above the polling interval in some environments, so timer overlap was creating near-continuous back-to-back scans.
- Consequence: Polling keeps eventual consistency but avoids saturation loops that were causing periodic UI beachballing and elevated CPU.

- Decision: Codex/OpenCode detectors now prefer direct active-session-file resolution and only run broad fallback directory scans when processes remain unresolved.
- Rationale: Scanning/parsing large session trees on every poll is the dominant cost even when active files already provide enough information.
- Consequence: Session detection behavior is preserved while significantly reducing repeated disk I/O and JSON parse churn in the common case.

- Decision: Cache process snapshots from `ps` for a short TTL inside `ProcessIntrospectionService`.
- Rationale: All detectors run in the same refresh cycle and were repeatedly spawning `ps` within milliseconds.
- Consequence: A single detector cycle now reuses one process snapshot, cutting subprocess overhead without introducing materially stale data.

## 2026-02-14 - Hover-first destructive controls and header focus behavior
- Decision: Keep destructive close controls hidden by default and reveal them only on pointer hover for each project header/session card.
- Rationale: Reduces constant visual noise and matches the intended UX where destructive actions are discoverable but not always prominent.
- Consequence: Project/session kill buttons are still one hover away, but the default dashboard state is cleaner.

- Decision: Make top-right header controls non-focusable for keyboard tab traversal.
- Rationale: The default macOS focus ring was appearing around header icon buttons and was called out as undesirable in this app's UX.
- Consequence: Tab navigation no longer outlines those header controls; interaction remains mouse-first for that control cluster.

## 2026-02-14 - Sentinel message suppression policy
- Decision: Treat `<turn_aborted...>` as a non-display control marker during session parsing and skip it when selecting `lastMessage`.
- Rationale: Users should see the most recent meaningful assistant/user content, not interruption metadata.
- Consequence: Dashboard and mini viewer previews now naturally fall back to the previous valid message because both consume parsed `Session.lastMessage`.

- Decision: Centralize suppression rules in `SessionParsingSupport.shouldSuppressPreviewMessage(...)` and reuse that rule from Claude/Codex/OpenCode detectors.
- Rationale: Keeps behavior consistent across agent types and prevents future drift between parsers.
- Consequence: One shared rule controls message sanitization for all session surfaces.

## 2026-02-14 - Middle-click destructive parity and explicit close-button color
- Decision: Use explicit close-button rendering (white `xmark` on a red circle) for project headers instead of relying on default symbol/button tint behavior.
- Rationale: Default styling could appear gray/secondary depending on hover/state context; destructive affordances must remain clearly red whenever visible.
- Consequence: Project close controls now maintain consistent red styling while preserving existing hover-to-show visibility.

- Decision: Use fully opaque red fill for session close buttons as well (`Color.red`) instead of semi-transparent red.
- Rationale: Ensures project and session destructive affordances have identical color semantics and avoids perceived dimming/state ambiguity.
- Consequence: Session close controls now match project close controls with consistent red appearance whenever visible.

- Decision: Add a reusable macOS local event monitor (`otherMouseUp`, button 2) scoped to project-header/session-card bounds to map middle-click to the same destructive actions as the visible close buttons.
- Rationale: SwiftUI lacks a native middle-mouse click gesture; monitoring `NSEvent` enables native middle-click close behavior without changing left-click open behavior.
- Consequence: Middle-click on a project header now closes that project group and middle-click on a session card kills that session, matching close-button behavior.

## 2026-02-14 - Separate UI element size settings and scaling strategy
- Decision: Introduce a shared `UIElementSize` enum (`small`, `medium`, `large`, `extraLarge`) and persist two independent preferences: one for the main app and one for the mini viewer.
- Rationale: Main dashboard and mini viewer have different density/readability needs, so one global setting was not sufficient.
- Consequence: Users can tune each surface independently; both settings default to `.small` for backward-compatible visual density.

- Decision: Apply main app font scaling globally using root view environment mapping (`.dynamicTypeSize(...)`) instead of touching every text declaration.
- Rationale: Environment-based scaling keeps the implementation maintainable and predictable as UI evolves.
- Consequence: Most SwiftUI text styles scale automatically from one central setting path in `ContentView`.

- Decision: Map `Small` to baseline dynamic type (`.large`) and reserve `Medium`/`Large`/`Extra Large` for progressively larger dynamic type sizes.
- Rationale: The user requested current UI density to remain the `Small` preset rather than shrinking below the existing baseline.
- Consequence: Switching to `Small` preserves current sizing; other options only increase text size.

- Decision: Include mini viewer UI size in the controller-to-helper payload and scale helper fonts via an environment-backed scale factor in `MiniViewer.swift`.
- Rationale: The mini viewer runs as a separate helper process, so it needs explicit size data and local rendering rules.
- Consequence: Mini viewer text reacts immediately to settings changes and startup state without coupling helper rendering to main app internals.
