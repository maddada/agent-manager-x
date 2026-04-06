---
children_hash: a5a72de6fd9370d262583deb8bab49662d4f2854c46f39026c73aabca64d4024
compression_ratio: 0.8585291113381001
condensation_order: 2
covers: [context.md, session_management/_index.md]
covers_token_total: 1958
summary_level: d2
token_count: 1681
type: summary
---
# architecture

## Domain Focus
Architecture knowledge for how Agent Manager X sources, normalizes, updates, and acts on agent sessions across the app. The main architectural theme is a dual-source session system that preserves a single UI/rendering pipeline while supporting both process polling and live VSmux session feeds.

## Topic Structure
- `session_management/_index.md` — compressed topic overview spanning model, broker, AppStore, dashboard, and mini viewer behavior
- Referenced drill-down entries within that topic:
  - `session_models.md`
  - `vsmux_live_session_mode.md`
  - `dashboard_session_source.md`

## Core Architectural Pattern
`session_management/_index.md` defines a two-mode retrieval architecture:

- `processBased`
  - existing async polling path
  - process metrics and kill controls remain available
  - polling interval remains `5.0 seconds`
- `vsmuxSessions`
  - live push path via local WebSocket broker
  - workspace/session snapshots are normalized into shared session models
  - UI hides process-only controls and uses workspace-aware focus behavior

The key decision is to keep `App/Sources/Core/Models/SessionModels.swift` as the normalization boundary so downstream rendering continues to consume shared `Session` and `SessionsResponse` types instead of splitting the app into source-specific UI pipelines.

## Main Components and Responsibilities
From `session_management/_index.md`:

- `App/Sources/AppState/AppStore.swift`
  - orchestration point for session source switching
  - tracks `sessionDetailsRetrievalMode`
  - starts/stops source-specific behavior
  - discards stale process refresh results after switching away from `processBased`
- `App/Sources/Services/Session/VSmuxSessionBroker.swift`
  - local WebSocket broker on port `47652`
  - receives VSmux workspace snapshots
  - issues focus commands back to connected workspaces
- `App/Sources/Views/MainDashboardView.swift`
  - unified dashboard with source-aware rendering
  - segmented source picker bound to `store.sessionDetailsRetrievalMode`
  - picker labels: `Process based`, `VSmux sessions`
  - picker width: `260`
- `App/Sources/Services/MiniViewer/MiniViewerController.swift`
  - source-aware session open/focus behavior
  - VSmux sessions open project first, then focus session
  - preserved mini viewer facts: diff cache TTL `60 seconds`, diff project cap `6`

## Shared Model Decisions
Highlighted in `session_models.md` and summarized by `session_management/_index.md`:

- `SessionDetailsSource` includes:
  - `processBased`
  - `vsmuxSessions`
- `Session` gained VSmux-specific metadata:
  - `detailsSource`
  - `vsmuxWorkspaceID`
  - `vsmuxThreadID`
  - `sessionFilePath`
- `AgentType.t3` was added
- `renderID` was revised to prevent collisions across sources/workspaces by incorporating:
  - `detailsSource`
  - workspace ID fallback
  - agent type
  - PID
  - ID

This isolates source-specific ingestion before normalization and avoids changing the shared `SessionsResponse` pipeline.

## VSmux Live Session Flow
Detailed by `vsmux_live_session_mode.md`:

1. User switches source to `vsmuxSessions`
2. `AppStore` activates broker-driven updates
3. VSmux publishers connect to local port `47652`
4. Broker accepts only `workspaceSnapshot` envelopes
5. Snapshots are stored by `workspaceId`
6. App state maps workspace/session snapshot data into shared `Session` models
7. Dashboard and mini viewer render through the same shared response pipeline
8. Opening a VSmux session performs:
   - project open
   - `focusSession` command

Broker implementation uses Apple networking APIs:
- `NWListener`
- `NWConnection`
- `NWProtocolWebSocket`

## Focus and Command Routing
From `vsmux_live_session_mode.md`:

- accepted inbound envelope: `workspaceSnapshot`
- outbound command: `focusSession`
- pending focus requests are queued until:
  - workspace exists
  - requested session exists in latest snapshot
  - a client connection exists for that workspace

This makes VSmux activation workspace-aware instead of process-control-driven.

## Mapping and State Rules
Summarized in `session_management/_index.md`:

### VSmux-to-Session mapping
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
- all others → `idle`

### Agent mapping
- explicit mappings for `claude`, `codex`, `gemini`, `t3`
- unknown values default to `opencode`

### Source-switching behavior
- process refresh is paused in VSmux mode
- stale process refresh results are discarded if source changed away from `processBased`
- kill actions apply only to process-based sessions

## UI Behavior by Source
From `dashboard_session_source.md` as summarized in `session_management/_index.md`:

### Shared dashboard pattern
A unified dashboard renders both session types while gating controls and metrics based on `Session.detailsSource`.

### Process mode
Shows process-centric controls and metrics:
- background
- kill idle
- kill stale
- per-agent kill actions
- PID / CPU / memory / active subagent counts

### VSmux mode
Changes card behavior:
- visible preview uses mapped `displayName` / `lastMessage`
- `isNewSession` is always false
- full-message popovers are disabled and return `nil`
- metrics line shows:
  - `formatTimeAgo(lastActivityAt)`
  - optional `Thread <first 8 chars>` when thread metadata exists

## Key Relationships
The entries form a layered architecture:

- `context.md` defines the `architecture` domain and positions session sourcing/rendering as in-scope
- `session_management/_index.md` is the structural bridge across model, broker, store, dashboard, and mini viewer
- `session_models.md` provides the shared schema and identity strategy
- `vsmux_live_session_mode.md` describes transport, workspace snapshot ingestion, focus routing, and AppStore switching logic
- `dashboard_session_source.md` captures source-aware UI rendering and action gating

## Preserved Key Facts
- local VSmux broker port: `47652`
- process polling interval: `5.0 seconds`
- mini viewer diff cache TTL: `60 seconds`
- mini viewer diff project cap: `6`

## Drill-Down Guide
- Read `session_models.md` for enum additions, VSmux metadata fields, and `renderID` uniqueness rules
- Read `vsmux_live_session_mode.md` for broker lifecycle, `workspaceSnapshot` / `focusSession` flow, and source-switching semantics
- Read `dashboard_session_source.md` for exact dashboard picker behavior, process-only action gating, and VSmux session-card rendering differences