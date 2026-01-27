# OpenCode Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add OpenCode session detection alongside Claude Code, showing both in a unified "Agent Manager X" view with agent-type badges.

**Architecture:** Trait-based `AgentDetector` abstraction with separate implementations for Claude and OpenCode. OpenCode uses SQLite (via rusqlite) while Claude uses JSONL. Combined results sorted by status priority.

**Tech Stack:** Rust (Tauri backend), rusqlite for SQLite, React/TypeScript frontend, existing sysinfo for process detection.

---

## Task 1: Add rusqlite Dependency

**Files:**
- Modify: `src-tauri/Cargo.toml`

**Step 1: Add dependency**

Add to `[dependencies]` section in `src-tauri/Cargo.toml`:

```toml
rusqlite = { version = "0.31", features = ["bundled"] }
```

**Step 2: Verify it compiles**

Run: `cd src-tauri && cargo check`
Expected: Compiles without errors (may take time to download/build SQLite)

**Step 3: Commit**

```bash
git add src-tauri/Cargo.toml
git commit -m "Add rusqlite dependency for OpenCode SQLite support"
```

---

## Task 2: Add AgentType Enum to Data Model

**Files:**
- Modify: `src-tauri/src/session/model.rs`
- Modify: `src/types/session.ts`

**Step 1: Add AgentType enum to Rust model**

In `src-tauri/src/session/model.rs`, add after the imports:

```rust
/// Type of AI coding agent
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum AgentType {
    Claude,
    OpenCode,
}
```

**Step 2: Add agent_type field to Session struct**

In the `Session` struct, add after `id`:

```rust
pub struct Session {
    pub id: String,
    pub agent_type: AgentType,  // ADD THIS LINE
    pub project_name: String,
    // ... rest unchanged
}
```

**Step 3: Update TypeScript types**

In `src/types/session.ts`, add:

```typescript
export type AgentType = 'claude' | 'opencode';

export interface Session {
  id: string;
  agentType: AgentType;  // ADD THIS LINE
  projectName: string;
  // ... rest unchanged
}
```

**Step 4: Verify it compiles**

Run: `cd src-tauri && cargo check`
Expected: Errors about missing `agent_type` field in Session construction (expected, we'll fix in next tasks)

**Step 5: Commit**

```bash
git add src-tauri/src/session/model.rs src/types/session.ts
git commit -m "Add AgentType enum to Session model"
```

---

## Task 3: Create Agent Module Structure

**Files:**
- Create: `src-tauri/src/agent/mod.rs`
- Modify: `src-tauri/src/lib.rs`

**Step 1: Create agent module directory**

```bash
mkdir -p src-tauri/src/agent
```

**Step 2: Create agent/mod.rs with trait definition**

Create `src-tauri/src/agent/mod.rs`:

```rust
pub mod claude;
pub mod opencode;

use crate::session::model::{Session, SessionsResponse, AgentType};

/// Common process info shared across agent types
#[derive(Debug, Clone)]
pub struct AgentProcess {
    pub pid: u32,
    pub cpu_usage: f32,
    pub cwd: Option<std::path::PathBuf>,
}

/// Trait for detecting and parsing agent sessions
pub trait AgentDetector: Send + Sync {
    /// Human-readable name of the agent
    fn name(&self) -> &'static str;

    /// The agent type for tagging sessions
    fn agent_type(&self) -> AgentType;

    /// Find running processes for this agent
    fn find_processes(&self) -> Vec<AgentProcess>;

    /// Parse sessions from data files, matched to running processes
    fn find_sessions(&self, processes: &[AgentProcess]) -> Vec<Session>;
}

/// Get all sessions from all registered agent detectors
pub fn get_all_sessions() -> SessionsResponse {
    use crate::session::status::status_sort_priority;

    let detectors: Vec<Box<dyn AgentDetector>> = vec![
        Box::new(claude::ClaudeDetector),
        Box::new(opencode::OpenCodeDetector),
    ];

    let mut all_sessions = Vec::new();

    for detector in &detectors {
        let processes = detector.find_processes();
        let sessions = detector.find_sessions(&processes);
        log::info!("{}: found {} processes, {} sessions",
            detector.name(), processes.len(), sessions.len());
        all_sessions.extend(sessions);
    }

    // Sort by status priority first, then by most recent activity
    all_sessions.sort_by(|a, b| {
        let priority_a = status_sort_priority(&a.status);
        let priority_b = status_sort_priority(&b.status);

        if priority_a != priority_b {
            priority_a.cmp(&priority_b)
        } else {
            b.last_activity_at.cmp(&a.last_activity_at)
        }
    });

    let waiting_count = all_sessions.iter()
        .filter(|s| matches!(s.status, crate::session::model::SessionStatus::Waiting))
        .count();
    let total_count = all_sessions.len();

    SessionsResponse {
        sessions: all_sessions,
        total_count,
        waiting_count,
    }
}
```

**Step 3: Add agent module to lib.rs**

In `src-tauri/src/lib.rs`, add:

```rust
pub mod agent;
```

**Step 4: Verify structure (will have errors, expected)**

Run: `cd src-tauri && cargo check 2>&1 | head -20`
Expected: Errors about missing `claude` and `opencode` submodules

**Step 5: Commit**

```bash
git add src-tauri/src/agent/mod.rs src-tauri/src/lib.rs
git commit -m "Create agent module with AgentDetector trait"
```

---

## Task 4: Implement ClaudeDetector

**Files:**
- Create: `src-tauri/src/agent/claude.rs`
- Modify: `src-tauri/src/session/parser.rs` (add agent_type to Session creation)

**Step 1: Create ClaudeDetector**

Create `src-tauri/src/agent/claude.rs`:

```rust
use super::{AgentDetector, AgentProcess};
use crate::process::find_claude_processes;
use crate::session::model::{AgentType, Session};
use crate::session::parser::get_sessions_internal;

pub struct ClaudeDetector;

impl AgentDetector for ClaudeDetector {
    fn name(&self) -> &'static str {
        "Claude Code"
    }

    fn agent_type(&self) -> AgentType {
        AgentType::Claude
    }

    fn find_processes(&self) -> Vec<AgentProcess> {
        find_claude_processes()
            .into_iter()
            .map(|p| AgentProcess {
                pid: p.pid,
                cpu_usage: p.cpu_usage,
                cwd: p.cwd,
            })
            .collect()
    }

    fn find_sessions(&self, processes: &[AgentProcess]) -> Vec<Session> {
        get_sessions_internal(processes, AgentType::Claude)
    }
}
```

**Step 2: Update parse_session_file to accept AgentType**

In `src-tauri/src/session/parser.rs`, update the `parse_session_file` function signature and Session creation.

Find the function signature:
```rust
pub fn parse_session_file(jsonl_path: &PathBuf, project_path: &str, process: &ClaudeProcess) -> Option<Session> {
```

Change to accept `agent_type` and use `AgentProcess`:
```rust
use crate::session::model::AgentType;
use crate::agent::AgentProcess;

pub fn parse_session_file(
    jsonl_path: &PathBuf,
    project_path: &str,
    pid: u32,
    cpu_usage: f32,
    agent_type: AgentType,
) -> Option<Session> {
```

**Step 3: Update Session construction in parse_session_file**

Find the `Some(Session {` block at the end of `parse_session_file` and add `agent_type`:

```rust
    Some(Session {
        id: session_id,
        agent_type,  // ADD THIS LINE
        project_name,
        project_path: project_path.to_string(),
        git_branch,
        github_url,
        status,
        last_message,
        last_message_role: last_role,
        last_activity_at: last_timestamp.unwrap_or_else(|| "Unknown".to_string()),
        pid,
        cpu_usage,
        active_subagent_count: 0,
    })
```

**Step 4: Create get_sessions_internal function**

Add a new function in `src-tauri/src/session/parser.rs` that can be called by ClaudeDetector:

```rust
use crate::agent::AgentProcess;

/// Internal function for getting Claude sessions, used by ClaudeDetector
pub fn get_sessions_internal(processes: &[AgentProcess], agent_type: AgentType) -> Vec<Session> {
    use std::collections::HashMap;

    log::info!("=== Getting Claude sessions ===");

    let mut sessions = Vec::new();

    // Build a map of cwd -> list of processes
    let mut cwd_to_processes: HashMap<String, Vec<&AgentProcess>> = HashMap::new();
    for process in processes {
        if let Some(cwd) = &process.cwd {
            let cwd_str = cwd.to_string_lossy().to_string();
            log::debug!("Mapping process pid={} to cwd={}", process.pid, cwd_str);
            cwd_to_processes.entry(cwd_str).or_default().push(process);
        }
    }

    // Scan ~/.claude/projects for session files
    let claude_dir = dirs::home_dir()
        .map(|h| h.join(".claude").join("projects"))
        .unwrap_or_default();

    if !claude_dir.exists() {
        log::warn!("Claude projects directory does not exist: {:?}", claude_dir);
        return sessions;
    }

    // For each project directory
    if let Ok(entries) = std::fs::read_dir(&claude_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }

            let dir_name = path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");

            let project_path = convert_dir_name_to_path(dir_name);

            // Check if this project has active processes
            let processes_for_project = if let Some(p) = cwd_to_processes.get(&project_path) {
                p
            } else {
                // Try reverse lookup
                let matching_cwd = cwd_to_processes.keys().find(|cwd| {
                    convert_path_to_dir_name(cwd) == dir_name
                });

                match matching_cwd {
                    Some(cwd) => cwd_to_processes.get(cwd).unwrap(),
                    None => continue,
                }
            };

            let jsonl_files = get_recently_active_jsonl_files(&path, processes_for_project.len());

            for (index, process) in processes_for_project.iter().enumerate() {
                if let Some(jsonl_path) = jsonl_files.get(index) {
                    if let Some(session) = parse_session_file(
                        jsonl_path,
                        &project_path,
                        process.pid,
                        process.cpu_usage,
                        agent_type.clone(),
                    ) {
                        sessions.push(session);
                    }
                }
            }
        }
    }

    sessions
}
```

**Step 5: Update the old get_sessions to use new architecture**

Update the existing `get_sessions()` function in `parser.rs` to call the new agent module:

```rust
/// Get all active sessions (delegates to agent module)
pub fn get_sessions() -> SessionsResponse {
    crate::agent::get_all_sessions()
}
```

**Step 6: Verify it compiles**

Run: `cd src-tauri && cargo check`
Expected: May have errors about OpenCodeDetector not existing yet

**Step 7: Commit**

```bash
git add src-tauri/src/agent/claude.rs src-tauri/src/session/parser.rs
git commit -m "Implement ClaudeDetector using AgentDetector trait"
```

---

## Task 5: Implement OpenCodeDetector (Stub)

**Files:**
- Create: `src-tauri/src/agent/opencode.rs`

**Step 1: Create OpenCodeDetector stub**

Create `src-tauri/src/agent/opencode.rs`:

```rust
use super::{AgentDetector, AgentProcess};
use crate::session::model::{AgentType, Session};

pub struct OpenCodeDetector;

impl AgentDetector for OpenCodeDetector {
    fn name(&self) -> &'static str {
        "OpenCode"
    }

    fn agent_type(&self) -> AgentType {
        AgentType::OpenCode
    }

    fn find_processes(&self) -> Vec<AgentProcess> {
        // TODO: Implement process detection
        find_opencode_processes()
    }

    fn find_sessions(&self, processes: &[AgentProcess]) -> Vec<Session> {
        // TODO: Implement SQLite parsing
        if processes.is_empty() {
            return Vec::new();
        }

        get_opencode_sessions(processes)
    }
}

/// Find running opencode processes
fn find_opencode_processes() -> Vec<AgentProcess> {
    use sysinfo::{System, ProcessRefreshKind, UpdateKind};

    let mut system = System::new();
    system.refresh_processes_specifics(
        sysinfo::ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::new()
            .with_cpu()
            .with_cwd(UpdateKind::OnlyIfNotSet),
    );

    let mut processes = Vec::new();

    for (pid, process) in system.processes() {
        let name = process.name().to_string_lossy().to_lowercase();

        if name == "opencode" {
            processes.push(AgentProcess {
                pid: pid.as_u32(),
                cpu_usage: process.cpu_usage(),
                cwd: process.cwd().map(|p| p.to_path_buf()),
            });
        }
    }

    log::debug!("Found {} opencode processes", processes.len());
    processes
}

/// Get OpenCode sessions from SQLite databases
fn get_opencode_sessions(processes: &[AgentProcess]) -> Vec<Session> {
    use std::collections::HashMap;

    let mut sessions = Vec::new();

    // OpenCode data directory
    let base_path = match dirs::data_local_dir() {
        Some(p) => p.join("opencode").join("project"),
        None => return sessions,
    };

    if !base_path.exists() {
        log::debug!("OpenCode data directory does not exist: {:?}", base_path);
        return sessions;
    }

    // Build cwd -> process map
    let mut cwd_to_process: HashMap<String, &AgentProcess> = HashMap::new();
    for process in processes {
        if let Some(cwd) = &process.cwd {
            cwd_to_process.insert(cwd.to_string_lossy().to_string(), process);
        }
    }

    // Scan project directories
    if let Ok(entries) = std::fs::read_dir(&base_path) {
        for entry in entries.flatten() {
            let project_dir = entry.path();
            if !project_dir.is_dir() {
                continue;
            }

            let db_path = project_dir.join("storage").join("db.sqlite");
            if !db_path.exists() {
                continue;
            }

            // Try to match this project to a running process
            let project_slug = project_dir.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");

            // Find matching process by checking if cwd contains project slug
            let matching_process = cwd_to_process.iter()
                .find(|(cwd, _)| cwd.contains(project_slug))
                .map(|(_, p)| *p);

            if let Some(process) = matching_process {
                if let Some(session) = parse_opencode_session(&db_path, project_slug, process) {
                    sessions.push(session);
                }
            }
        }
    }

    sessions
}

/// Parse a single OpenCode session from SQLite
fn parse_opencode_session(
    db_path: &std::path::Path,
    project_slug: &str,
    process: &AgentProcess,
) -> Option<Session> {
    use rusqlite::Connection;
    use crate::session::model::SessionStatus;

    let conn = match Connection::open(db_path) {
        Ok(c) => c,
        Err(e) => {
            log::warn!("Failed to open OpenCode database {:?}: {}", db_path, e);
            return None;
        }
    };

    // Get most recent session
    let session_row: Result<(String, String, i64), _> = conn.query_row(
        "SELECT id, title, updated_at FROM sessions ORDER BY updated_at DESC LIMIT 1",
        [],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    );

    let (session_id, title, updated_at) = match session_row {
        Ok(r) => r,
        Err(_) => return None,
    };

    // Get last message for status detection
    let last_msg: Result<(String, Option<i64>), _> = conn.query_row(
        "SELECT role, finished_at FROM messages WHERE session_id = ? ORDER BY created_at DESC LIMIT 1",
        [&session_id],
        |row| Ok((row.get(0)?, row.get(1)?)),
    );

    let status = match last_msg {
        Ok((role, finished_at)) => {
            if process.cpu_usage > 5.0 {
                SessionStatus::Processing
            } else if role == "assistant" && finished_at.is_some() {
                SessionStatus::Waiting
            } else if role == "user" {
                SessionStatus::Processing
            } else {
                SessionStatus::Idle
            }
        }
        Err(_) => SessionStatus::Idle,
    };

    // Get last message content for preview
    let last_message: Option<String> = conn.query_row(
        "SELECT parts FROM messages WHERE session_id = ? ORDER BY created_at DESC LIMIT 1",
        [&session_id],
        |row| row.get(0),
    ).ok();

    // Convert timestamp to ISO string
    let last_activity_at = chrono::DateTime::from_timestamp(updated_at, 0)
        .map(|dt| dt.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string())
        .unwrap_or_else(|| "Unknown".to_string());

    // Extract project name from slug (replace dashes with spaces, capitalize)
    let project_name = project_slug
        .split('-')
        .filter(|s| !s.is_empty())
        .last()
        .unwrap_or(project_slug)
        .to_string();

    Some(Session {
        id: session_id,
        agent_type: AgentType::OpenCode,
        project_name,
        project_path: format!("~/.local/share/opencode/project/{}", project_slug),
        git_branch: None, // OpenCode doesn't store git branch in DB
        github_url: None,
        status,
        last_message,
        last_message_role: None,
        last_activity_at,
        pid: process.pid,
        cpu_usage: process.cpu_usage,
        active_subagent_count: 0,
    })
}
```

**Step 2: Add chrono dependency for timestamp conversion**

In `src-tauri/Cargo.toml`, add:

```toml
chrono = "0.4"
```

**Step 3: Verify it compiles**

Run: `cd src-tauri && cargo check`
Expected: Compiles without errors

**Step 4: Run tests**

Run: `cd src-tauri && cargo test`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add src-tauri/src/agent/opencode.rs src-tauri/Cargo.toml
git commit -m "Implement OpenCodeDetector with SQLite parsing"
```

---

## Task 6: Update Frontend SessionCard with Agent Badge

**Files:**
- Modify: `src/components/SessionCard.tsx`

**Step 1: Add AgentBadge component**

In `src/components/SessionCard.tsx`, add after imports:

```tsx
// Agent type icons
const ClaudeIcon = () => (
  <svg viewBox="0 0 24 24" className="w-4 h-4 fill-orange-400">
    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 15h-2v-6h2v6zm4 0h-2v-6h2v6zm-2-8c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z"/>
  </svg>
);

const OpenCodeIcon = () => (
  <svg viewBox="0 0 24 24" className="w-4 h-4 fill-cyan-400">
    <path d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z"/>
  </svg>
);

const AgentBadge = ({ type }: { type: 'claude' | 'opencode' }) => {
  return (
    <div className="absolute top-[-10] right-[-10] opacity-60">
      {type === 'claude' ? <ClaudeIcon /> : <OpenCodeIcon />}
    </div>
  );
};
```

**Step 2: Add badge to card**

Find the card's outer div and add `relative` class and the badge:

```tsx
<Card
  className={cn(
    "relative cursor-pointer transition-all duration-200 hover:scale-[1.02]",
    // ... rest of classes
  )}
>
  <AgentBadge type={session.agentType} />
  {/* rest of card content */}
</Card>
```

**Step 3: Verify frontend compiles**

Run: `npm run build`
Expected: Builds without errors

**Step 4: Commit**

```bash
git add src/components/SessionCard.tsx
git commit -m "Add agent type badge to SessionCard"
```

---

## Task 7: Integration Testing

**Step 1: Run full test suite**

```bash
npm test && cd src-tauri && cargo test
```

Expected: All tests pass

**Step 2: Build the app**

```bash
npm run tauri build -- --debug
```

Expected: Builds successfully

**Step 3: Manual test (if OpenCode installed)**

1. Start an OpenCode session in a terminal
2. Launch the app
3. Verify OpenCode session appears with cyan icon
4. Verify Claude sessions still work with orange icon

**Step 4: Final commit**

```bash
git add -A
git commit -m "Complete OpenCode integration"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Add rusqlite dependency | Cargo.toml |
| 2 | Add AgentType enum | model.rs, session.ts |
| 3 | Create agent module structure | agent/mod.rs, lib.rs |
| 4 | Implement ClaudeDetector | agent/claude.rs, parser.rs |
| 5 | Implement OpenCodeDetector | agent/opencode.rs |
| 6 | Add agent badge to UI | SessionCard.tsx |
| 7 | Integration testing | - |
