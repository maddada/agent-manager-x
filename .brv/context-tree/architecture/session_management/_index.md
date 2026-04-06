---
children_hash: 7749adb5fbbc6da0be2c96dc0164731517603e383b973f5f71bb00258764093e
compression_ratio: 0.6574500768049155
condensation_order: 1
covers: [context.md, dashboard_session_source.md, session_models.md, vsmux_live_session_mode.md]
covers_token_total: 2604
summary_level: d1
token_count: 1712
type: summary
---
# session_management

## Overview
`context.md` defines `session_management` as the architecture topic for dual-mode session retrieval in Agent Manager X: traditional process polling and the new VSmux-backed live session path. The topic centers on a shared `Session` normalization layer, an AppStore-controlled source switch, a local WebSocket broker, and UI behavior that changes based on session source.

## Entry Map
- `vsmux_live_session_mode.md` — end-to-end architecture for VSmux live sessions
- `session_models.md` — shared model and enum changes enabling both retrieval modes
- `dashboard_session_source.md` — dashboard/session-card UI behavior for source-specific rendering

## Core Architecture
- Session retrieval is now dual-mode:
  - `processBased` continues using async polling
  - `vsmuxSessions` uses a local WebSocket broker
- The normalization boundary is the shared `Session` / `SessionsResponse` model described in `session_models.md`.
- `App/Sources/AppState/AppStore.swift` is the orchestration point:
  - tracks `sessionDetailsRetrievalMode`
  - switches between polling and broker-driven updates
  - discards stale process refresh results if the source changed away from `processBased`
- `App/Sources/Services/Session/VSmuxSessionBroker.swift` provides push-based VSmux ingestion over local WebSocket port `47652`.
- `App/Sources/Views/MainDashboardView.swift` renders a unified dashboard while conditionally hiding process-only controls in VSmux mode.
- `App/Sources/Services/MiniViewer/MiniViewerController.swift` integrates VSmux-aware open/focus behavior.

## Data Flow
From `vsmux_live_session_mode.md` and `session_models.md`:

1. User switches source to `vsmuxSessions`
2. `AppStore` starts the broker and refreshes source state
3. VSmux publishers connect on port `47652`
4. Broker accepts only `workspaceSnapshot` envelopes
5. Snapshots are stored by `workspaceId`
6. `AppStore` maps workspace/session snapshots into shared `Session` models
7. Dashboard and mini viewer render through the same `SessionsResponse` pipeline
8. Opening a VSmux session first opens the project, then sends `focusSession`

This preserves one rendering pipeline while allowing different transport/update mechanisms.

## Model Decisions
From `session_models.md`:

- `App/Sources/Core/Models/SessionModels.swift` was extended rather than replaced.
- `SessionDetailsSource` now has:
  - `processBased`
  - `vsmuxSessions`
- `Session` gained VSmux metadata:
  - `detailsSource`
  - `vsmuxWorkspaceID`
  - `vsmuxThreadID`
  - `sessionFilePath`
- `AgentType.t3` was added.
- `renderID` was updated to avoid collisions across sources/workspaces; it incorporates:
  - `detailsSource`
  - workspace ID fallback
  - agent type
  - PID
  - ID

Architectural implication: source-specific ingestion is isolated before model normalization, minimizing downstream churn because `SessionsResponse` remains unchanged.

## VSmux Broker and Focus Workflow
From `vsmux_live_session_mode.md`:

- Broker stack depends on Apple Network APIs:
  - `NWListener`
  - `NWConnection`
  - `NWProtocolWebSocket`
- Accepted inbound envelope type: `workspaceSnapshot`
- Outbound command type: `focusSession`
- Pending focus requests are queued until all conditions are true:
  - workspace exists
  - requested session exists in latest snapshot
  - a client connection exists for that workspace
- Focus behavior is intentionally two-step:
  1. open the correct project in the editor
  2. request broker focus using `workspaceId` + `sessionId`

This makes VSmux session activation workspace-aware rather than process-control-driven.

## UI and Rendering Behavior
From `dashboard_session_source.md` and `vsmux_live_session_mode.md`:

### Dashboard source selection
- `MainDashboardView` adds a segmented picker bound to `store.sessionDetailsRetrievalMode`
- Picker presents `SessionDetailsRetrievalMode.allCases`
- Fact preserved: picker width is `260`
- Toggle labels referenced in `vsmux_live_session_mode.md`:
  - `Process based`
  - `VSmux sessions`

### Process-only controls
Shown only in process mode:
- background
- kill idle
- kill stale
- per-agent kill actions

### VSmux card behavior
- visible preview uses mapped `displayName` / `lastMessage`
- `isNewSession` is always false
- full-message popovers are disabled / return `nil`
- metrics line shows:
  - `formatTimeAgo(lastActivityAt)`
  - optional `Thread <first 8 chars>` when thread metadata exists

### Process card behavior
- continues to show process-centric metrics:
  - PID
  - CPU
  - memory
  - active subagent counts

## State and Mapping Rules
From `vsmux_live_session_mode.md`:

- In VSmux mode, process-based refresh is paused.
- Kill actions only work for process-based sessions.
- If a process refresh finishes after source switched away from `processBased`, results are discarded and refresh flags are cleared.
- VSmux session mapping includes:
  - `id = session.sessionId`
  - `projectName = workspace.workspaceName`
  - `projectPath = workspace.workspacePath`
  - `lastMessage = session.displayName`
  - `detailsSource = .vsmuxSessions`
  - `vsmuxWorkspaceID = workspace.workspaceId`
  - `vsmuxThreadID = session.threadId`

### Status / agent mapping
- status:
  - `working` → `processing`
  - `attention` → `waiting`
  - all others → `idle`
- agents:
  - explicit mappings for `claude`, `codex`, `gemini`, `t3`
  - unknown values default to `opencode`

## Shared Relationships
- `context.md` explicitly positions:
  - `session_models.md` as the shared model foundation
  - `dashboard_session_source.md` as the UI layer for source-specific behavior
- `dashboard_session_source.md` depends on:
  - `AppStore` exposure of `sessionDetailsRetrievalMode`, `updateSessionDetailsRetrievalMode`, `agentCounts`, and refresh behavior
  - `Session.detailsSource` and `vsmuxThreadID`
- `vsmux_live_session_mode.md` ties together:
  - broker transport
  - AppStore switching logic
  - session normalization
  - mini viewer action routing
  - dashboard constraints

## Preserved Key Facts
- VSmux broker port: `47652`
- Process polling interval remains `5.0 seconds`
- Mini viewer diff cache TTL: `60 seconds`
- Mini viewer diff project cap: `6`
- Main files:
  - `App/Sources/Services/Session/VSmuxSessionBroker.swift`
  - `App/Sources/AppState/AppStore.swift`
  - `App/Sources/Views/MainDashboardView.swift`
  - `App/Sources/Services/MiniViewer/MiniViewerController.swift`
  - `App/Sources/Core/Models/SessionModels.swift`

## Drill-down Guidance
- Read `vsmux_live_session_mode.md` for transport, broker lifecycle, focus-session sequencing, and source-switching rules.
- Read `session_models.md` for enum/field additions and `renderID` uniqueness strategy.
- Read `dashboard_session_source.md` for exact dashboard picker behavior, process-only action gating, and VSmux session-card rendering differences.