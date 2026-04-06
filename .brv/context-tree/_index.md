---
children_hash: 4c00b3c60e50db65042462f078507dfff9e1a78c30858d51c27a3cc741787b0c
compression_ratio: 0.9897094430992736
condensation_order: 3
covers: [architecture/_index.md]
covers_token_total: 1652
summary_level: d3
token_count: 1635
type: summary
---
# architecture

## Domain Overview
Agent Manager X architecture is organized around a dual-source session system that keeps the UI stable while allowing different upstream retrieval mechanisms. The central design decision is to normalize both process-backed and VSmux-backed sessions into the same shared `Session` / `SessionsResponse` boundary, with orchestration primarily in `App/Sources/AppState/AppStore.swift`.

Primary drill-down:
- `context.md`
- `session_management/_index.md`

## Core Topic: `session_management`
`session_management/_index.md` is the main detailed topic for how sessions are retrieved, normalized, displayed, and acted on.

### Retrieval modes
Two session detail sources exist:
- `processBased`
- `vsmuxSessions`

These modes share downstream rendering and model consumption, but differ in transport, update behavior, and available actions.

## Shared Model Boundary
From `session_models.md`:

- Normalization layer: `App/Sources/Core/Models/SessionModels.swift`
- Source discriminator: `SessionDetailsSource`
- Shared model: `Session`
- Stable response shape: `SessionsResponse` remains unchanged

### Important model fields
`Session` carries source-specific metadata without changing the downstream response contract:
- `detailsSource`
- `vsmuxWorkspaceID`
- `vsmuxThreadID`
- `sessionFilePath`

### Architectural decisions
- Source-specific ingestion is converted before UI rendering
- This avoids downstream churn across dashboard and mini viewer
- `AgentType.t3` was added
- `renderID` was redesigned to avoid collisions by incorporating:
  - `detailsSource`
  - workspace ID fallback
  - agent type
  - pid
  - id

Drill-down:
- `session_models.md`

## Source Transport Patterns

### Process mode
From `dashboard_session_source.md` and `vsmux_live_session_mode.md`:

- Default persisted mode
- Polling-based
- Poll interval: `5.0 seconds`
- Supports process-derived telemetry and management controls

### VSmux mode
From `vsmux_live_session_mode.md`:

- Push-based via local broker
- Uses broker-backed updates instead of normal process refresh
- `AppStore` discards stale process refresh results after mode switches away from `.processBased`

Drill-down:
- `dashboard_session_source.md`
- `vsmux_live_session_mode.md`

## VSmux Broker Architecture
`vsmux_live_session_mode.md` defines a local WebSocket broker in:

- `App/Sources/Services/Session/VSmuxSessionBroker.swift`

### Broker details
- Port: `47652`
- Incoming envelope: `workspaceSnapshot`
- Outgoing command: `focusSession`

### Platform/network stack
- `NWListener`
- `NWConnection`
- `NWProtocolWebSocket`

### Broker responsibilities
- Store snapshots keyed by `workspaceId`
- Emit sorted workspace updates
- Queue pending focus requests until the workspace, session, and client connection are available

Drill-down:
- `vsmux_live_session_mode.md`

## End-to-End Session Flows

### Process-backed flow
- `AppStore` polls for sessions
- Sessions include telemetry like PID, CPU, memory, conversation preview, and active subagent count
- Dashboard can expose process management controls in this mode

### VSmux-backed flow
- User selects `vsmuxSessions`
- `AppStore` switches to broker-backed updates
- Publishers connect on port `47652`
- `workspaceSnapshot` updates broker state
- Snapshots map into shared `Session` / `SessionsResponse`
- Dashboard and mini viewer consume the normalized output
- Open flow:
  - open project in editor first
  - send `focusSession` with `workspaceId` and `sessionId`

Drill-down:
- `vsmux_live_session_mode.md`

## UI Partitioning by Source
From `dashboard_session_source.md`:

### Source selector
Implemented via:
- `App/Sources/Core/Settings/SettingsTypes.swift`
- `App/Sources/Views/MainDashboardView.swift`

Key UI details:
- segmented `Picker`
- `labelsHidden()`
- fixed width `260`
- hover popover descriptions per mode

Label split:
- persisted/raw: `Process based`, `VSmux sessions`
- displayed: `Processes`, `VSmux`

### Process-only controls
Gated by:
- `store.sessionDetailsRetrievalMode == .processBased`

Available only in process mode:
- Background sessions button/panel
- Kill idle sessions
- Kill stale sessions
- Kill-all by agent type:
  - `claude`
  - `codex`
  - `opencode`
- Project-group kill-all controls

Constraint:
- Kill actions do not work for VSmux sessions

Drill-down:
- `dashboard_session_source.md`

## Source-Aware Session Card Rendering
Defined across `dashboard_session_source.md`, `session_models.md`, and `vsmux_live_session_mode.md`.

### Process-based cards
- Show CPU, memory, PID, and other telemetry
- Can show full-message popovers
- Support richer process metrics

### VSmux cards
- Use live-session metadata
- Display `session.displayName` as preview text
- Suppress full-message popovers
- Show relative activity time with optional thread suffix
- Open/focus the exact VS Code session instead of controlling a process

### Shared layout behavior
- Full message popover disabled for VSmux
- Popover delays:
  - show: `0.65s`
  - hide: `0.16s`
- Masonry layout:
  - minimum column width `360`
  - spacing `14`

Drill-down:
- `dashboard_session_source.md`
- `session_models.md`
- `vsmux_live_session_mode.md`

## VSmux Mapping Rules
From `vsmux_live_session_mode.md`:

### VSmux → `Session`
- `id = session.sessionId`
- `projectName = workspace.workspaceName`
- `projectPath = workspace.workspacePath`
- `lastMessage = session.displayName`
- `detailsSource = .vsmuxSessions`
- `vsmuxWorkspaceID = workspace.workspaceId`
- `vsmuxThreadID = session.threadId`

### Status mapping
- `working -> processing`
- `attention -> waiting`
- all others -> `idle`

### Agent mapping
Explicit mappings:
- `claude`
- `codex`
- `gemini`
- `t3`

Fallback:
- `opencode`

Drill-down:
- `vsmux_live_session_mode.md`

## Mini Viewer Relationship
From `vsmux_live_session_mode.md`:

The mini viewer relies on an injected VSmux session open handler so open actions route through `AppStore` rather than process control.

Operational constraints:
- diff cache TTL: `60 seconds`
- diff project cap: `6`

Drill-down:
- `vsmux_live_session_mode.md`

## Drill-Down Map
- `session_management/_index.md` — overall dual-source architecture and mode relationships
- `session_models.md` — shared model boundary, `SessionDetailsSource`, VSmux metadata, `renderID`, `AgentType.t3`
- `vsmux_live_session_mode.md` — broker design, WebSocket transport, mapping rules, session open/focus flow
- `dashboard_session_source.md` — mode picker, process-only controls, source-specific card rendering and layout