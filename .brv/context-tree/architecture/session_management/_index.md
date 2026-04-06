---
children_hash: e709e6268d1fc3f03fb9e3bc1cba4dde87e3654953df31f7bff81f50555e433d
compression_ratio: 0.5157830217591174
condensation_order: 1
covers: [context.md, dashboard_session_source.md, session_models.md, vsmux_live_session_mode.md]
covers_token_total: 3263
summary_level: d1
token_count: 1683
type: summary
---
# session_management

## Overview
`context.md` defines `session_management` as the architecture for dual-mode session retrieval in Agent Manager X: traditional process-based polling and the new VSmux-backed live session mode. The topic centers on a shared `Session` model boundary, a local WebSocket broker, AppStore mode switching, and dashboard/UI behavior that changes based on the active source.

## Child Entries
- `dashboard_session_source.md`
- `session_models.md`
- `vsmux_live_session_mode.md`

## Architectural Structure

### Dual retrieval modes
Across `vsmux_live_session_mode.md`, `session_models.md`, and `dashboard_session_source.md`, session retrieval is split into:
- `processBased`
- `vsmuxSessions`

Key relationship:
- `App/Sources/AppState/AppStore.swift` chooses the retrieval path.
- Process mode continues async polling.
- VSmux mode uses push updates from a local broker and bypasses normal process refresh behavior.

### Normalization boundary
`session_models.md` establishes `App/Sources/Core/Models/SessionModels.swift` as the shared normalization layer:
- `SessionDetailsSource` has `processBased` and `vsmuxSessions`
- `Session` now carries both process-oriented fields and VSmux metadata:
  - `detailsSource`
  - `vsmuxWorkspaceID`
  - `vsmuxThreadID`
  - `sessionFilePath`

Architectural decision:
- `SessionsResponse` stays unchanged to minimize downstream churn.
- Source-specific ingestion is converted into the same `Session` shape before UI rendering.

### VSmux transport and broker
`vsmux_live_session_mode.md` introduces `App/Sources/Services/Session/VSmuxSessionBroker.swift`:
- Local WebSocket broker
- Port: `47652`
- Accepts incoming envelope type `workspaceSnapshot`
- Sends outgoing command type `focusSession`

Dependencies called out there:
- Apple Network framework:
  - `NWListener`
  - `NWConnection`
  - `NWProtocolWebSocket`

Broker responsibilities:
- Store snapshots keyed by `workspaceId`
- Emit sorted workspace updates
- Queue pending focus requests until:
  - workspace exists
  - requested session exists
  - client connection exists

## End-to-End Flow

### Process mode
From `vsmux_live_session_mode.md` and `dashboard_session_source.md`:
- Process mode remains the default persisted mode.
- Polling interval remains `5.0 seconds`.
- Dashboard exposes process-derived controls and telemetry.
- Session cards can show:
  - PID
  - CPU
  - memory
  - conversation preview
  - active subagent count

### VSmux mode
From `vsmux_live_session_mode.md`:
1. User switches source to `vsmuxSessions`
2. `AppStore` starts broker-backed updates
3. VSmux publishers connect on port `47652`
4. `workspaceSnapshot` payloads update broker state
5. `AppStore` maps snapshots into shared `Session` / `SessionsResponse`
6. Dashboard and mini viewer render from the same shared pipeline
7. Opening a session triggers:
   - open project in editor first
   - then send `focusSession` for `workspaceId` + `sessionId`

Important rule:
- If an old process refresh completes after the source changed away from `processBased`, `AppStore` discards the results and clears refresh flags.

## UI and Behavior Differences

### Dashboard source selector
`dashboard_session_source.md` documents `App/Sources/Core/Settings/SettingsTypes.swift` and `App/Sources/Views/MainDashboardView.swift`:
- Segmented `Picker`
- `labelsHidden()`
- segmented style
- fixed width `260`
- hover popover description based on selected mode

Important distinctions:
- Persisted/raw labels: `Process based`, `VSmux sessions`
- Display labels: `Processes`, `VSmux`
- The visible label is hidden specifically to avoid header layout breakage.

### Process-only controls
`dashboard_session_source.md` states these are gated by:
- `store.sessionDetailsRetrievalMode == .processBased`

Only shown in process mode:
- Background sessions button/panel
- Kill idle sessions
- Kill stale sessions
- Kill-all-by-agent-type for:
  - `claude`
  - `codex`
  - `opencode`

Also:
- Project group kill-all controls only appear in process mode.
- Kill actions do not work for VSmux sessions.

### Session card rendering
Relationship between entries:
- `session_models.md` provides the model fields
- `dashboard_session_source.md` documents rendering differences
- `vsmux_live_session_mode.md` explains why those differences exist

Process-based cards:
- use process telemetry
- can show full-message popovers
- can show CPU/memory/PID and richer process metrics

VSmux cards:
- use live-session metadata
- show `session.displayName` as visible preview text
- suppress full-message popovers
- metrics show relative activity time with optional thread suffix
- focus the exact session in VS Code rather than managing a process

Additional UI facts from `dashboard_session_source.md`:
- full message popover is disabled for VSmux sessions
- popover timing is:
  - show delay `0.65s`
  - hide delay `0.16s`
- masonry layout:
  - minimum column width `360`
  - spacing `14`

## Model and Identity Details

From `session_models.md`:
- `AgentType.t3` was added.
- `renderID` was updated to avoid collisions across session sources and workspaces.

`renderID` includes:
- `detailsSource`
- workspace ID fallback
- agent type
- pid
- id

This is a key SwiftUI list-rendering decision: repeated logical IDs from different transport layers or workspaces should not collide.

## Data Mapping and Semantics

### VSmux session mapping
From `vsmux_live_session_mode.md`, VSmux sessions map into shared `Session` fields such as:
- `id = session.sessionId`
- `projectName = workspace.workspaceName`
- `projectPath = workspace.workspacePath`
- `lastMessage = session.displayName`
- `detailsSource = .vsmuxSessions`
- `vsmuxWorkspaceID = workspace.workspaceId`
- `vsmuxThreadID = session.threadId`

### Status and agent mapping
Also from `vsmux_live_session_mode.md`:
- Status mapping:
  - `working -> processing`
  - `attention -> waiting`
  - all others -> `idle`
- Agent mapping:
  - explicit: `claude`, `codex`, `gemini`, `t3`
  - fallback: `opencode`

## Mini Viewer Relationship
`vsmux_live_session_mode.md` notes the mini viewer depends on an injected VSmux session open handler so actions route through AppStore instead of process control. Related facts:
- diff cache TTL: `60 seconds`
- diff project cap: `6`

## Drill-Down Guide
- Read `vsmux_live_session_mode.md` for broker architecture, port `47652`, `workspaceSnapshot` ingestion, and `focusSession` workflow.
- Read `session_models.md` for `SessionDetailsSource`, VSmux metadata fields, `AgentType.t3`, and `renderID` uniqueness.
- Read `dashboard_session_source.md` for segmented picker behavior, process-only action gating, session-card UI differences, hover descriptions, and layout constraints.