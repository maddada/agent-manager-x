---
children_hash: 22dd1d9ae969581e3fcc63d2eebcdf0c6f8a722ecedc647da989417ac09fab19
compression_ratio: 0.7434285714285714
condensation_order: 3
covers: [architecture/_index.md]
covers_token_total: 1750
summary_level: d3
token_count: 1301
type: summary
---
# architecture

## Structural Overview
The `architecture` domain centers on a single architectural decision: support two session-detail sources without splitting the app into separate rendering pipelines. `architecture/_index.md` compresses this around `session_management/_index.md`, which in turn organizes the model, broker, app-state, dashboard, and mini-viewer layers.

## Primary Topic
- `session_management/_index.md` — core topic for dual-source session retrieval and normalization
  - Drill-down entries:
    - `session_models.md`
    - `vsmux_live_session_mode.md`
    - `dashboard_session_source.md`

## Core Architecture Pattern
The app uses a two-mode session system:
- `processBased`
  - async polling path
  - retains process metrics and kill controls
  - polling interval: `5.0 seconds`
- `vsmuxSessions`
  - live local WebSocket push path
  - ingests workspace/session snapshots
  - disables process-only controls
  - uses workspace-aware focus/open behavior

The normalization boundary remains `App/Sources/Core/Models/SessionModels.swift`, so downstream UI continues to consume shared `Session` and `SessionsResponse` models regardless of source.

## Main Components
- `App/Sources/AppState/AppStore.swift`
  - owns `sessionDetailsRetrievalMode`
  - switches source behavior on/off
  - drops stale process refreshes after leaving `processBased`
- `App/Sources/Services/Session/VSmuxSessionBroker.swift`
  - local broker on port `47652`
  - accepts VSmux workspace snapshots
  - sends focus commands to workspaces
- `App/Sources/Views/MainDashboardView.swift`
  - unified dashboard
  - segmented picker bound to `store.sessionDetailsRetrievalMode`
  - picker labels: `Process based`, `VSmux sessions`
  - picker width: `260`
- `App/Sources/Services/MiniViewer/MiniViewerController.swift`
  - source-aware open/focus behavior
  - VSmux flow opens project first, then focuses session
  - preserved constraints: diff cache TTL `60 seconds`, diff project cap `6`

## Shared Model Decisions
From `session_models.md`:
- `SessionDetailsSource` includes:
  - `processBased`
  - `vsmuxSessions`
- `Session` adds VSmux metadata:
  - `detailsSource`
  - `vsmuxWorkspaceID`
  - `vsmuxThreadID`
  - `sessionFilePath`
- `AgentType.t3` was added
- `renderID` was redesigned to avoid collisions across sources/workspaces using:
  - `detailsSource`
  - workspace ID fallback
  - agent type
  - PID
  - ID

This preserves one shared response/render pipeline while isolating source-specific ingestion.

## Live VSmux Session Flow
From `vsmux_live_session_mode.md`:
1. User selects `vsmuxSessions`
2. `AppStore` enables broker-driven updates
3. VSmux publishers connect on `47652`
4. Broker accepts only `workspaceSnapshot` envelopes
5. Snapshots are stored by `workspaceId`
6. Snapshot data is mapped into shared `Session` models
7. Dashboard and mini viewer render from the shared pipeline
8. Opening a VSmux session performs project open, then `focusSession`

Transport implementation uses:
- `NWListener`
- `NWConnection`
- `NWProtocolWebSocket`

## Command Routing and State Rules
From `vsmux_live_session_mode.md` and `session_management/_index.md`:
- inbound envelope: `workspaceSnapshot`
- outbound command: `focusSession`
- pending focus waits until:
  - workspace exists
  - requested session appears in latest snapshot
  - workspace client connection exists

### Mapping rules
- `id = session.sessionId`
- `projectName = workspace.workspaceName`
- `projectPath = workspace.workspacePath`
- `lastMessage = session.displayName`
- `detailsSource = .vsmuxSessions`
- `vsmuxWorkspaceID = workspace.workspaceId`
- `vsmuxThreadID = session.threadId`

### Status mapping
- `working` → `processing`
- `attention` → `waiting`
- otherwise → `idle`

### Agent mapping
- explicit: `claude`, `codex`, `gemini`, `t3`
- unknown defaults to `opencode`

### Source-switching behavior
- process refresh pauses in VSmux mode
- stale process results are discarded after source switch
- kill actions only apply to process-based sessions

## UI Source Behavior
From `dashboard_session_source.md`:
- shared dashboard renders both sources via `Session.detailsSource`
- process mode exposes:
  - background
  - kill idle
  - kill stale
  - per-agent kill actions
  - PID / CPU / memory / active subagent metrics
- VSmux mode changes card behavior:
  - preview uses mapped `displayName` / `lastMessage`
  - `isNewSession` always false
  - full-message popovers disabled (`nil`)
  - metrics show `formatTimeAgo(lastActivityAt)` and optional `Thread <first 8 chars>`

## Entry Relationships
- `architecture/_index.md` frames the domain and points to `session_management/_index.md`
- `session_management/_index.md` is the integration layer across models, broker, store, dashboard, and mini viewer
- `session_models.md` defines schema and identity rules
- `vsmux_live_session_mode.md` defines transport, snapshot ingestion, focus routing, and switching semantics
- `dashboard_session_source.md` defines source-aware dashboard rendering and action gating

## Preserved Key Facts
- VSmux broker port: `47652`
- process polling interval: `5.0 seconds`
- mini viewer diff cache TTL: `60 seconds`
- mini viewer diff project cap: `6`