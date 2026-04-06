---
children_hash: 3cbb020c8eabe0b39915073c5a5148fda685c97e4821a13a4eea80555cefe56a
compression_ratio: 0.8211508553654744
condensation_order: 2
covers: [context.md, session_management/_index.md]
covers_token_total: 1929
summary_level: d2
token_count: 1584
type: summary
---
# architecture

## Scope
Architecture covers how Agent Manager X discovers, normalizes, updates, and acts on agent sessions across the app. The domain centers on session sourcing, broker/polling behavior, shared models, and UI/open flows, with `session_management` as the main detailed topic.

## Main Topic: `session_management`
`session_management/_index.md` defines a dual-source session architecture with a single UI/model boundary:

- Retrieval modes:
  - `processBased`
  - `vsmuxSessions`
- Source selection and orchestration live in `App/Sources/AppState/AppStore.swift`
- Core architectural decision: keep downstream rendering stable by normalizing both sources into the same `Session` / `SessionsResponse` pipeline

### Key child entries
- `dashboard_session_source.md`
- `session_models.md`
- `vsmux_live_session_mode.md`

## Structural Architecture

### 1. Shared model boundary
From `session_models.md`:

- `App/Sources/Core/Models/SessionModels.swift` is the normalization layer
- `SessionDetailsSource` distinguishes:
  - `processBased`
  - `vsmuxSessions`
- `Session` includes both traditional and VSmux metadata:
  - `detailsSource`
  - `vsmuxWorkspaceID`
  - `vsmuxThreadID`
  - `sessionFilePath`

Important decision:
- `SessionsResponse` remains unchanged
- Source-specific ingestion is converted before UI rendering, minimizing downstream churn

Additional model facts:
- `AgentType.t3` was added
- `renderID` was redesigned to prevent collisions across sources/workspaces by incorporating:
  - `detailsSource`
  - workspace ID fallback
  - agent type
  - pid
  - id

### 2. Source-specific transport modes
From `vsmux_live_session_mode.md` and `dashboard_session_source.md`:

#### Process mode
- Default persisted mode
- Uses polling
- Poll interval remains `5.0 seconds`
- Supports process-derived controls, telemetry, and management actions

#### VSmux mode
- Uses push updates from a local broker
- Bypasses normal process refresh behavior
- If an old process refresh returns after switching away from `processBased`, `AppStore` discards the stale result and clears refresh flags

## VSmux Broker Design
From `vsmux_live_session_mode.md`:

`App/Sources/Services/Session/VSmuxSessionBroker.swift` introduces a local WebSocket broker:

- Port: `47652`
- Incoming envelope type: `workspaceSnapshot`
- Outgoing command type: `focusSession`

Platform/network dependencies:
- `NWListener`
- `NWConnection`
- `NWProtocolWebSocket`

Broker responsibilities:
- Store snapshots keyed by `workspaceId`
- Emit sorted workspace updates
- Queue pending focus requests until:
  - workspace exists
  - session exists
  - client connection exists

## End-to-End Flows

### Process flow
- `AppStore` polls for process-backed sessions
- Sessions carry telemetry such as PID, CPU, memory, conversation preview, and active subagent count
- Dashboard exposes management controls only in this mode

### VSmux flow
From `vsmux_live_session_mode.md`:

1. User selects `vsmuxSessions`
2. `AppStore` switches to broker-backed updates
3. VSmux publishers connect on port `47652`
4. `workspaceSnapshot` payloads update broker state
5. Snapshots map into shared `Session` / `SessionsResponse`
6. Dashboard and mini viewer consume the same normalized pipeline
7. Opening a session:
   - opens the project in the editor first
   - then sends `focusSession` with `workspaceId` + `sessionId`

## UI and Behavior Partitioning

### Source selector
From `dashboard_session_source.md`:

`App/Sources/Core/Settings/SettingsTypes.swift` and `App/Sources/Views/MainDashboardView.swift` implement a segmented `Picker` with:

- `labelsHidden()`
- segmented style
- fixed width `260`
- hover popover descriptions by mode

Label distinction:
- Persisted/raw labels:
  - `Process based`
  - `VSmux sessions`
- Display labels:
  - `Processes`
  - `VSmux`

The visible label is hidden to avoid header layout breakage.

### Process-only controls
Gated by:
- `store.sessionDetailsRetrievalMode == .processBased`

Only available in process mode:
- Background sessions button/panel
- Kill idle sessions
- Kill stale sessions
- Kill-all-by-agent-type for:
  - `claude`
  - `codex`
  - `opencode`
- Project group kill-all controls

Explicit constraint:
- Kill actions do not work for VSmux sessions

### Session card differences
`dashboard_session_source.md` + `session_models.md` + `vsmux_live_session_mode.md` together define source-aware rendering:

#### Process-based cards
- Show process telemetry
- Can display CPU, memory, PID
- Can show full-message popovers
- Support richer process metrics

#### VSmux cards
- Use live-session metadata
- Show `session.displayName` as visible preview text
- Suppress full-message popovers
- Show relative activity time with optional thread suffix
- Open/focus the exact VS Code session instead of managing a process

Shared layout/UI details:
- Full message popover disabled for VSmux sessions
- Popover timing:
  - show delay `0.65s`
  - hide delay `0.16s`
- Masonry layout:
  - minimum column width `360`
  - spacing `14`

## Data Mapping Rules
From `vsmux_live_session_mode.md`:

### VSmux → shared `Session`
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
- Explicit:
  - `claude`
  - `codex`
  - `gemini`
  - `t3`
- Fallback:
  - `opencode`

## Mini Viewer Relationship
From `vsmux_live_session_mode.md`:

The mini viewer depends on an injected VSmux session open handler so session actions route through `AppStore` rather than process control.

Operational limits:
- diff cache TTL: `60 seconds`
- diff project cap: `6`

## Drill-Down Map
- `session_management/_index.md`: overall architecture and mode relationships
- `session_models.md`: shared model boundary, `SessionDetailsSource`, VSmux metadata, `renderID`, `AgentType.t3`
- `vsmux_live_session_mode.md`: broker architecture, port `47652`, `workspaceSnapshot`, `focusSession`, mapping and open flow
- `dashboard_session_source.md`: picker behavior, process-only actions, source-specific card rendering, layout and hover behavior