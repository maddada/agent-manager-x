# OpenCode Integration Design

## Overview

Add OpenCode session detection alongside Claude Code, showing both in a unified "Agent Manager X" view. Sessions from each agent will be visually distinguished by a small icon/badge on each card.

## Background

**OpenCode** is an open-source AI coding agent for the terminal, similar to Claude Code. Key differences:

| Aspect | Claude Code | OpenCode |
|--------|-------------|----------|
| Data storage | `~/.claude/projects/*.jsonl` | `~/.local/share/opencode/project/<slug>/storage/` (SQLite) |
| Process name | `claude` | `opencode` |
| Session format | JSONL (one line per message) | SQLite database |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Agent Detection                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   trait AgentDetector {                                         │
│       fn name() -> &str                                         │
│       fn find_processes() -> Vec<AgentProcess>                  │
│       fn find_sessions(processes) -> Vec<Session>               │
│   }                                                             │
│                                                                 │
│   ┌─────────────────────┐    ┌─────────────────────┐           │
│   │  ClaudeDetector     │    │  OpenCodeDetector   │           │
│   │                     │    │                     │           │
│   │  • ~/.claude/       │    │  • ~/.local/share/  │           │
│   │    projects/*.jsonl │    │    opencode/...     │           │
│   │  • process: claude  │    │  • process: opencode│           │
│   │  • JSONL parsing    │    │  • SQLite parsing   │           │
│   └─────────────────────┘    └─────────────────────┘           │
│              │                         │                        │
│              └────────────┬────────────┘                        │
│                           ▼                                     │
│                   ┌───────────────┐                             │
│                   │  get_sessions │  → Vec<Session>             │
│                   │  (combined)   │    with agent_type field    │
│                   └───────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

## Data Model Changes

### Rust

```rust
// New enum to identify the agent type
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum AgentType {
    Claude,
    OpenCode,
}

// Updated Session struct
pub struct Session {
    pub id: String,
    pub agent_type: AgentType,           // NEW
    pub project_name: String,
    pub project_path: String,
    pub git_branch: Option<String>,
    pub github_url: Option<String>,
    pub status: SessionStatus,
    pub last_message: Option<String>,
    pub last_message_role: Option<String>,
    pub last_activity_at: String,
    pub pid: u32,
    pub cpu_usage: f32,
    pub active_subagent_count: usize,
}
```

### TypeScript

```typescript
type AgentType = 'claude' | 'opencode';

interface Session {
  // ... existing fields ...
  agentType: AgentType;
}
```

## OpenCode SQLite Schema

OpenCode uses SQLite with the following relevant tables:

**sessions table:**
- `id` (string, primary key)
- `parent_session_id` (nullable, for nested sessions)
- `title` (string)
- `message_count` (int)
- `prompt_tokens`, `completion_tokens` (int)
- `cost` (float)
- `updated_at`, `created_at` (int, unix timestamp)

**messages table:**
- `id` (string, primary key)
- `session_id` (foreign key)
- `role` (string: "user" or "assistant")
- `parts` (string, message content)
- `model` (nullable string)
- `created_at`, `updated_at`, `finished_at` (int timestamps)

**Data location:** `~/.local/share/opencode/project/<project-slug>/storage/`

Each project folder contains its own SQLite database.

## OpenCode Detector Implementation

### Process Detection

```rust
fn find_opencode_processes() -> Vec<AgentProcess> {
    // Use sysinfo to find processes named "opencode"
    // Extract PID, CPU usage, working directory
}
```

### Session Discovery

```rust
fn find_sessions(processes: &[AgentProcess]) -> Vec<Session> {
    let base_path = dirs::data_local_dir()  // ~/.local/share
        .join("opencode/project");

    // For each project folder:
    //   1. Open SQLite db in <project>/storage/
    //   2. Query latest session + messages
    //   3. Match to running process via working directory
    //   4. Determine status from message state + CPU
}
```

### SQLite Queries

```sql
-- Get most recent session
SELECT * FROM sessions
ORDER BY updated_at DESC LIMIT 1;

-- Get last message for status detection
SELECT role, parts, finished_at FROM messages
WHERE session_id = ?
ORDER BY created_at DESC LIMIT 1;
```

### Status Mapping

| OpenCode State | Maps To |
|----------------|---------|
| Last message role = "user", no finished_at | Processing/Thinking |
| Last message role = "assistant", has finished_at | Waiting |
| No recent activity (updated_at > 5 min ago) | Idle |
| High CPU (>5%) | Processing |

## Module Structure

```
src-tauri/src/
├── agent/                    # NEW: Agent detection abstraction
│   ├── mod.rs               # AgentDetector trait + get_all_sessions()
│   ├── claude.rs            # ClaudeDetector (refactored from existing)
│   └── opencode.rs          # OpenCodeDetector (new)
├── process/
│   ├── mod.rs
│   └── claude.rs            # Keep as-is (process utils)
├── session/
│   ├── mod.rs
│   ├── model.rs             # Add AgentType enum
│   ├── parser.rs            # Refactor: extract Claude-specific to agent/
│   └── status.rs            # Keep as-is (status logic is shared)
└── ...
```

### Trait Definition

```rust
// agent/mod.rs
pub trait AgentDetector {
    /// Human-readable name ("Claude Code", "OpenCode")
    fn name(&self) -> &'static str;

    /// Find running processes for this agent
    fn find_processes(&self) -> Vec<AgentProcess>;

    /// Parse sessions from data files, matched to processes
    fn find_sessions(&self, processes: &[AgentProcess]) -> Vec<Session>;
}

/// Combined entry point
pub fn get_all_sessions() -> SessionsResponse {
    let detectors: Vec<Box<dyn AgentDetector>> = vec![
        Box::new(ClaudeDetector),
        Box::new(OpenCodeDetector),
    ];

    let mut all_sessions = Vec::new();
    for detector in detectors {
        let processes = detector.find_processes();
        let sessions = detector.find_sessions(&processes);
        all_sessions.extend(sessions);
    }

    // Sort by status priority, then by activity
    all_sessions.sort_by(...);

    SessionsResponse { sessions: all_sessions, ... }
}
```

## Frontend UI Changes

### Agent Badge Component

```tsx
const AgentBadge = ({ type }: { type: AgentType }) => {
  if (type === 'claude') {
    return <ClaudeIcon className="w-4 h-4" />;  // Orange/coral
  }
  return <OpenCodeIcon className="w-4 h-4" />;  // Blue/teal
};
```

Small icon in top-left corner of each card. No other UI changes needed:
- Same card layout
- Same status colors (Waiting/Processing/Idle)
- Same sorting logic (waiting first)
- Same click-to-focus behavior

### Terminal Focus

OpenCode runs in the same terminals as Claude Code (iTerm2, Terminal.app), so existing AppleScript focus logic works unchanged.

## Dependencies

```toml
# src-tauri/Cargo.toml
[dependencies]
rusqlite = { version = "0.31", features = ["bundled"] }
```

The `bundled` feature includes SQLite itself, so no system dependency needed.

## Error Handling

OpenCode detection fails gracefully:
- If `~/.local/share/opencode` doesn't exist → return empty vec
- If SQLite file is locked/corrupt → log warning, skip that project
- If schema doesn't match expected → log warning, skip
- Never crash the whole app due to OpenCode issues

Claude detection continues to work even if OpenCode detection fails.

## Files to Create/Modify

| File | Change |
|------|--------|
| `src-tauri/Cargo.toml` | Add rusqlite dependency |
| `src-tauri/src/agent/mod.rs` | New trait + combined detector |
| `src-tauri/src/agent/claude.rs` | Refactor existing logic |
| `src-tauri/src/agent/opencode.rs` | New OpenCode detector |
| `src-tauri/src/session/model.rs` | Add AgentType enum |
| `src/types/session.ts` | Add agentType field |
| `src/components/SessionCard.tsx` | Add agent badge |

## Summary

| Aspect | Decision |
|--------|----------|
| **Architecture** | Trait-based `AgentDetector` with Claude and OpenCode implementations |
| **Data model** | Add `AgentType` enum to `Session` struct |
| **OpenCode data** | SQLite at `~/.local/share/opencode/project/<slug>/storage/` |
| **Process detection** | Find processes named `opencode` via sysinfo |
| **SQLite library** | `rusqlite` with bundled feature |
| **Status mapping** | Same logic as Claude (role + CPU + recency) |
| **UI changes** | Small badge/icon on each card to show agent type |
| **Terminal focus** | Existing AppleScript works unchanged |
| **Error handling** | Graceful degradation, never crash app |
