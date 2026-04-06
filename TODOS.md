# Agent Manager X Performance TODOs

These todos are based on profiling the live app while it was showing up in macOS "Using Significant Energy".

## Highest Priority

### [Done] Share one session snapshot between the main app and mini viewer

Details:
- The main app and mini viewer currently run separate refresh loops and both call `SessionDetectionService.getAllSessions()`.
- This duplicates the most expensive work in the app, including process scanning, `lsof` calls, and session-file parsing.
- Best direction: have one canonical refresh pipeline produce a shared session snapshot, then let both the main UI and mini viewer consume that result.

### [Done] Cache per-PID process metadata to avoid repeated `lsof` work

Details:
- `workingDirectory(pid:)` and `newestOpenFile(pid:...)` are expensive because they shell out to `lsof`.
- These are currently hit repeatedly across refreshes for the same long-lived processes.
- Best direction: cache `cwd` and `activeSessionFile` by PID with a short TTL, and invalidate when the process disappears or its elapsed/start info changes.
- This should reduce both CPU and subprocess churn significantly.

### [Done] Cache parsed session files by path and modification date

Details:
- Claude, Codex, and OpenCode repeatedly decode the same session files even when the file contents have not changed.
- Best direction: add a parsed-session cache keyed by file path plus modification date, and reuse the decoded result until the file actually changes.
- This is especially important for large Codex JSONL files.

### [Done] Make Codex session discovery cheaper

Details:
- Codex fallback scanning can recurse through many directories and parse many candidate files per sweep.
- The current parse budget can scale up to 120 files, which is expensive for a periodic check.
- Best direction:
  - reduce the parse budget
  - make the budget adaptive to the active Codex process count
  - prefer direct active-session matches before fallback scanning
  - avoid reparsing unchanged candidates

## Medium Priority

### [Done] Only compute git diff stats when needed

Details:
- The mini viewer computes diff stats per visible project, and each calculation shells out to `git diff --numstat HEAD`.
- This is useful UI, but it should not refresh as aggressively as session state.
- Best direction:
  - only compute diff stats when the mini viewer is expanded
  - compute them only for the first visible projects instead of every project
  - increase the diff cache TTL
  - refresh diff stats on a slower cadence than session polling

### [Done] Stop prewarming the mini viewer when it is hidden

Details:
- The app currently starts the native mini viewer helper even when the viewer is not shown yet, to make toggling feel faster.
- That keeps the helper process, its timer, and its update path alive even when the user is not looking at it.
- Best direction: do not launch the helper until the viewer is actually shown, or only prewarm on explicit user opt-in.

### Split refresh cadence by data type

Details:
- Not all data needs the same freshness.
- Process discovery, session parsing, git diff stats, and UI projection are currently too tightly coupled.
- Best direction:
  - refresh process lists on one cadence
  - reparse only changed files on another cadence
  - refresh git diff stats even less frequently
- This should reduce unnecessary work while keeping the UI feeling current.

### Add a fast path for stable idle sessions

Details:
- Many sessions do not materially change every poll cycle.
- Stable idle sessions should be refreshed less aggressively than active/thinking/waiting sessions.
- Best direction: track whether a session has changed recently and apply a slower refresh policy when it has been stable for some time.

## Lower Priority

### Replace mini viewer hover polling with event-driven tracking

Details:
- The native mini viewer currently checks hover state on a 40 ms timer.
- That means it wakes up 25 times per second just to test pointer position.
- Best direction: replace the timer with event-driven mouse tracking so the helper does no work while the pointer is idle.

### Pause or simplify spinner animation work when not needed

Details:
- The mini viewer has a perpetual spinner animation for processing/thinking sessions.
- Repeated animation and layout churn adds cost, especially when combined with frequent model updates.
- Best direction:
  - disable the spinner when the viewer is collapsed
  - avoid animations when offscreen
  - consider using a lighter status treatment for background states

### Reduce unnecessary mini viewer layout churn

Details:
- The helper currently recomputes window frame and SwiftUI layout in response to frequent model changes.
- The profiling sample showed meaningful time in layout/display work.
- Best direction:
  - only update window frame when size-driving properties actually change
  - avoid pushing identical payloads to the helper
  - coalesce helper UI updates when multiple model values change together
