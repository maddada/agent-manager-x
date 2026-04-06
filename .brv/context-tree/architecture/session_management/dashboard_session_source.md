---
title: Dashboard Session Source
tags: []
related: [architecture/session_management/vsmux_live_session_mode.md, architecture/session_management/session_models.md]
keywords: []
importance: 50
recency: 1
maturity: draft
createdAt: '2026-04-06T12:29:45.770Z'
updatedAt: '2026-04-06T12:29:45.770Z'
---
## Raw Concept
**Task:**
Document dashboard and session-card UI changes introduced by the VSmux session source.

**Changes:**
- Added segmented picker for selecting session source
- Restricted destructive and process-specific controls to process mode
- Changed VSmux cards to show session titles via lastMessage/displayName mapping
- Changed VSmux metrics line to show recency and optional thread ID

**Files:**
- App/Sources/Views/MainDashboardView.swift

**Flow:**
user changes dashboard picker -> AppStore updates session source -> dashboard conditionally shows process controls -> session cards render source-specific preview, popover, and metrics behavior

**Timestamp:** 2026-04-06

## Narrative
### Structure
MainDashboardView adds a top-bar segmented Picker bound to store.sessionDetailsRetrievalMode and iterates over SessionDetailsRetrievalMode.allCases to present the available sources. The view uses helper flags named showsProcessActions in both the header and session-card scopes so the same rendering tree can selectively hide controls that only make sense for process-based sessions.

### Dependencies
This UI depends on AppStore exposing sessionDetailsRetrievalMode, updateSessionDetailsRetrievalMode, agentCounts, and refresh behavior. Session-card rendering also depends on session.detailsSource and vsmuxThreadID from the shared Session model.

### Highlights
The header title remains Agent Manager X and the refresh button still calls store.refresh(showInitialLoading: true). In VSmux mode, preview text comes from the mapped displayName value, isNewSession is forced false, fullMessage returns nil, and the metrics line displays formatTimeAgo(lastActivityAt) plus Thread <first 8 chars> when thread metadata exists. Process sessions continue to use PID, CPU, memory, and active subagent counts.

## Facts
- **dashboard_session_source_picker**: The dashboard uses a segmented picker with width 260 for session source selection. [project]
- **dashboard_process_only_actions**: Background, kill idle, kill stale, and per-agent kill actions are shown only in process mode. [project]
- **vsmux_new_session_behavior**: VSmux session cards never count as new sessions. [project]
- **vsmux_full_message_popover**: VSmux full message popovers are disabled. [project]
