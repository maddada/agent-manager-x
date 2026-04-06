---
title: Dashboard Session Source
tags: []
related: [architecture/session_management/context.md, architecture/session_management/vsmux_live_session_mode.md, architecture/session_management/session_models.md]
keywords: []
importance: 55
recency: 1
maturity: draft
updateCount: 1
createdAt: '2026-04-06T12:29:45.770Z'
updatedAt: '2026-04-06T16:35:16.496Z'
---
## Raw Concept
**Task:**
Document dashboard session source segmented control and process-based versus VSmux session behavior in Agent Manager X

**Changes:**
- Updated session source picker to hide visible label and use segmented display labels
- Added hover descriptions explaining process-based versus VSmux session details modes
- Restricted dashboard process actions and project kill-all actions to processBased mode
- Documented session card differences for previews, metrics, and full-message availability by details source

**Files:**
- App/Sources/Core/Settings/SettingsTypes.swift
- App/Sources/Views/MainDashboardView.swift

**Flow:**
user selects session source -> store.updateSessionDetailsRetrievalMode(_) persists mode -> dashboard conditionally shows process actions -> session cards render source-specific preview, metrics, and popover behavior

**Timestamp:** 2026-04-06

**Patterns:**
- `store\.sessionDetailsRetrievalMode\s*==\s*\.processBased` - Condition used to gate process-only dashboard and project actions
- `session\.detailsSource\s*==\s*\.vsmuxSessions` - Condition used to switch session card behavior for VSmux sessions

## Narrative
### Structure
Session source selection is defined in SettingsTypes.swift through SessionDetailsRetrievalMode with processBased and vsmuxSessions cases, then surfaced in MainDashboardView.swift as a segmented Picker with labelsHidden(), segmented style, fixed width 260, and a hoverPopover using the currently selected mode description. The visible labels are displayName values Processes and VSmux while the persisted enum raw values remain Process based and VSmux sessions.

### Dependencies
The dashboard depends on store.sessionDetailsRetrievalMode to decide whether to expose process-derived controls such as background sessions, idle/stale kill actions, and kill-all-by-agent-type controls. Session cards also depend on session.detailsSource to decide whether message previews, metrics, and destructive controls should use process-based process telemetry or VSmux live-session metadata.

### Highlights
processBased remains the default persisted mode. The UI hides the picker label specifically to prevent header layout breakage. VSmux mode focuses exact sessions in VS Code and suppresses full-message popovers, while process-based mode exposes CPU, memory, conversation preview, background-session management, and kill actions. Masonry layout places each next card in the shortest column and computes columns from available width, minimum width 360, and spacing 14.

### Rules
Shown only when `showsProcessActions` is true:
- Background sessions button/panel, if `!store.backgroundSessions.isEmpty`
- Kill idle sessions button, if `store.idleCount() > 0`
- Kill stale sessions button, if `store.staleCount() > 0`
- Kill-all-by-agent-type buttons for:
  - `claude`
  - `codex`
  - `opencode`

Exact hover descriptions:
- For `.processBased`:
  - `Processes reads live terminal processes and shows CPU, memory, and conversation previews. VSmux reads live sessions directly from VSmux and focuses the exact session in VS Code.`
- For `.vsmuxSessions`:
  - `VSmux reads live sessions directly from VSmux and focuses the exact session in VS Code. Processes reads terminal processes instead and shows CPU, memory, and conversation previews.`

### Examples
Picker example: labelsHidden segmented control bound to store.sessionDetailsRetrievalMode and using Text(mode.displayName). Session card examples include isNewSession returning false for VSmux sessions, previewText returning "No messages sent yet" for new process sessions, metricsLine rendering only time-ago plus optional thread prefix for VSmux sessions, and process sessions rendering PID, CPU percent, memory, time-ago, plus active subagent count.

## Facts
- **session_source_picker_label**: Session source picker hides its visible label to avoid header layout breakage. [project]
- **default_session_details_mode**: processBased remains the default persisted mode. [project]
- **session_source_display_labels**: Segmented control uses display-only labels Processes and VSmux. [project]
- **process_actions_visibility**: Process-only dashboard actions are shown only when store.sessionDetailsRetrievalMode == .processBased. [convention]
- **vsmux_full_message_popover**: VSmux sessions do not show a full message popover. [project]
- **message_popover_timing**: Message popover show delay is 0.65 seconds and hide delay is 0.16 seconds. [project]
- **masonry_layout_defaults**: Masonry layout minimum column width is 360 with spacing 14. [project]
- **project_group_kill_all_visibility**: Project group cards show kill-all controls only in processBased mode. [project]
- **session_file_path_behavior**: Session file path is shown when store.showSessionFilePath is enabled and tapping copies the path to NSPasteboard. [project]
