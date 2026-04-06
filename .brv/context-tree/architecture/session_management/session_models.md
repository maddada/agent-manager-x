---
title: Session Models
tags: []
related: [architecture/session_management/vsmux_live_session_mode.md]
keywords: []
importance: 50
recency: 1
maturity: draft
createdAt: '2026-04-06T12:29:45.770Z'
updatedAt: '2026-04-06T12:29:45.770Z'
---
## Raw Concept
**Task:**
Document SessionModels changes required for dual-mode session retrieval.

**Changes:**
- Added AgentType.t3
- Added SessionDetailsSource.vsmuxSessions
- Extended Session with VSmux source metadata
- Updated renderID to remain unique across session sources and workspaces

**Files:**
- App/Sources/Core/Models/SessionModels.swift

**Flow:**
VSmux or process source data -> Session model -> renderID generation for UI lists -> shared SessionsResponse rendering

**Timestamp:** 2026-04-06

## Narrative
### Structure
SessionModels.swift defines the shared enums and structs used by both retrieval modes. SessionDetailsSource now differentiates processBased from vsmuxSessions, while the Session struct carries optional VSmux metadata fields without breaking the existing process-oriented fields such as pid, cpuUsage, and memoryBytes.

### Dependencies
These model updates are consumed by AppStore mapping logic, dashboard rendering, and the mini viewer payload/action protocol. renderID depends on detailsSource and vsmuxWorkspaceID so repeated logical IDs from separate workspaces or transport layers do not collide in SwiftUI list rendering.

### Highlights
The Session model remains the normalization boundary between source-specific ingestion and UI rendering. The added sessionFilePath field leaves room for a persisted session artifact path, while vsmuxThreadID enables thread-aware labels in the UI. SessionsResponse shape itself is unchanged, which minimizes downstream churn.

## Facts
- **session_details_source_cases**: SessionDetailsSource has processBased and vsmuxSessions cases. [project]
- **session_vsmux_fields**: Session now includes detailsSource, vsmuxWorkspaceID, vsmuxThreadID, and sessionFilePath. [project]
- **session_render_id_components**: Session renderID includes detailsSource, workspace ID fallback, agent type, pid, and id. [project]
