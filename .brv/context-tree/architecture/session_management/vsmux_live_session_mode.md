---
title: VSmux Live Session Mode
tags: []
related: [architecture/session_management/session_models.md, architecture/session_management/dashboard_session_source.md]
keywords: []
importance: 50
recency: 1
maturity: draft
createdAt: '2026-04-06T12:29:45.768Z'
updatedAt: '2026-04-06T12:29:45.768Z'
---
## Raw Concept
**Task:**
Document the VSmux live session mode added to Agent Manager X and its end-to-end architecture.

**Changes:**
- Added a local WebSocket-based VSmux session broker
- Added a user-selectable session retrieval mode between processBased and vsmuxSessions
- Added AppStore logic to switch between polling and broker-driven updates
- Added VSmux-specific focus workflow that opens a project before sending focusSession back to the broker
- Added VSmux metadata to Session models and mini viewer payloads
- Disabled or hid process-only actions when VSmux sessions are active

**Files:**
- App/Sources/Services/Session/VSmuxSessionBroker.swift
- App/Sources/AppState/AppStore.swift
- App/Sources/Views/MainDashboardView.swift
- App/Sources/Services/MiniViewer/MiniViewerController.swift
- App/Sources/Core/Models/SessionModels.swift

**Flow:**
user switches source to vsmuxSessions -> AppStore starts broker and refreshes -> VSmux publishers connect on port 47652 -> workspaceSnapshot messages update broker state -> AppStore maps snapshots into Session models -> dashboard and mini viewer render sessions -> user opens a VSmux session -> app opens the project in the editor -> broker sends focusSession when workspace and session are available

**Timestamp:** 2026-04-06

**Patterns:**
- `workspaceSnapshot` - Accepted incoming VSmux WebSocket envelope type
- `focusSession` - Outgoing broker command type used to focus a session in VSmux
- `47652` - Local WebSocket port used by the VSmux broker

## Narrative
### Structure
Session retrieval is now dual-mode. Process-based sessions continue to use asynchronous polling through AppStore refresh logic, while VSmux sessions are supplied by a new local WebSocket broker that accepts workspace snapshots and emits sorted workspace updates back to the UI layer. The AppStore converts each VSmuxWorkspaceSnapshot into the shared SessionsResponse and Session model so the rest of the interface can keep rendering through the same response pipeline.

### Dependencies
The broker depends on the Apple Network framework, specifically NWListener, NWConnection, and NWProtocolWebSocket. AppStore depends on VSmuxSessionBroker for push updates, CoreActionsService for opening projects in the editor before focus, and SessionParsingSupport for ISO date parsing used in VSmux session sorting. Mini viewer behavior depends on an injected VSmux session open handler so it can route focus actions through the AppStore instead of process control.

### Highlights
The broker only accepts decoded envelopes whose type is exactly workspaceSnapshot, stores snapshots by workspaceId, and queues pending focus requests until a matching workspace, session, and client connection all exist. In VSmux mode, process refresh is effectively bypassed, process kill actions are disabled, session cards show session.displayName as visible preview text, full message popovers are suppressed, and metrics switch from PID/CPU/memory to relative activity time with an optional thread ID suffix. VSmux status values map working to processing, attention to waiting, and all other states to idle; agent values map claude, codex, gemini, and t3 explicitly with other values defaulting to opencode.

### Rules
In VSmux mode, process-based refresh is paused.
Kill actions only work for process-based sessions.
The broker only sends focusSession after the requested workspace exists, the requested session is present in the latest snapshot, and a client connection exists for that workspace.
Clicking a VSmux session must open the correct project first, then request broker focus for the workspaceId and sessionId pair.
If a process-based refresh completes after the session source changed away from processBased, AppStore discards the results and clears refresh flags.

### Examples
Example source toggle labels: Process based and VSmux sessions. Example VSmux Session mapping sets id to session.sessionId, projectName to workspace.workspaceName, projectPath to workspace.workspacePath, lastMessage to session.displayName, detailsSource to .vsmuxSessions, vsmuxWorkspaceID to workspace.workspaceId, and vsmuxThreadID to session.threadId. Example VSmux metrics line appends Thread <first 8 chars> when a thread ID is present.

## Facts
- **vsmux_live_session_mode**: Agent Manager X supports a VSmux live session mode. [project]
- **vsmux_broker_port**: The VSmux broker listens on local WebSocket port 47652. [project]
- **process_polling_interval**: Process mode polling interval remains 5.0 seconds. [project]
- **session_source_modes**: The dashboard picker toggles between Process based and VSmux sessions. [project]
- **mini_viewer_diff_cache_ttl**: Mini viewer diff cache TTL is 60 seconds. [project]
- **mini_viewer_diff_project_cap**: Mini viewer diff project cap is 6. [project]
