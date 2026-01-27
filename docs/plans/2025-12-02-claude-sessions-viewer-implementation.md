# Claude Sessions Viewer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Tauri menubar app that monitors Claude Code sessions and allows one-click terminal focus.

**Architecture:** Rust backend uses sysinfo for process monitoring and parses ~/.claude JSONL files for session data. React frontend displays sessions as cards in a menubar dropdown. AppleScript handles terminal window focusing.

**Tech Stack:** Tauri 2.x, React 18, TypeScript, Tailwind CSS, sysinfo crate, serde_json

---

## Task 1: Initialize Tauri Project

**Files:**
- Create: `package.json`
- Create: `src-tauri/Cargo.toml`
- Create: `src-tauri/tauri.conf.json`
- Create: `src-tauri/src/main.rs`
- Create: `src/main.tsx`
- Create: `src/App.tsx`
- Create: `index.html`
- Create: `vite.config.ts`
- Create: `tsconfig.json`
- Create: `tailwind.config.js`
- Create: `postcss.config.js`
- Create: `src/index.css`

**Step 1: Create the project using Tauri CLI**

Run:
```bash
cd /Users/ozan/Projects/claude-sessions-viewer
npm create tauri-app@latest . -- --template react-ts --manager npm
```

Select options when prompted:
- Package manager: npm
- UI template: React
- TypeScript: Yes

**Step 2: Install additional dependencies**

Run:
```bash
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p
```

**Step 3: Configure Tailwind**

Replace `tailwind.config.js`:
```js
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

**Step 4: Set up Tailwind CSS**

Replace `src/index.css`:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  background-color: #0a0a0a;
  color: #fafafa;
}

body {
  margin: 0;
  min-height: 100vh;
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
}
```

**Step 5: Add Rust dependencies**

Edit `src-tauri/Cargo.toml`, add to `[dependencies]`:
```toml
sysinfo = "0.31"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
dirs = "5.0"
```

**Step 6: Verify project builds**

Run:
```bash
npm run tauri dev
```

Expected: App window opens (we'll convert to menubar next)

**Step 7: Commit**

```bash
git init
git add .
git commit -m "feat: initialize Tauri project with React and Tailwind"
```

---

## Task 2: Configure Menubar App

**Files:**
- Modify: `src-tauri/tauri.conf.json`
- Modify: `src-tauri/Cargo.toml`
- Modify: `src-tauri/src/main.rs`

**Step 1: Add tray plugin to Cargo.toml**

Edit `src-tauri/Cargo.toml`, add to `[dependencies]`:
```toml
tauri-plugin-positioner = "2"
```

**Step 2: Update tauri.conf.json for menubar**

Edit `src-tauri/tauri.conf.json`, update the entire file:
```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "Claude Sessions",
  "version": "0.1.0",
  "identifier": "com.claude-sessions-viewer",
  "build": {
    "beforeBuildCommand": "npm run build",
    "beforeDevCommand": "npm run dev",
    "devUrl": "http://localhost:1420",
    "frontendDist": "../dist"
  },
  "app": {
    "withGlobalTauri": true,
    "trayIcon": {
      "iconPath": "icons/icon.png",
      "iconAsTemplate": true
    },
    "windows": [
      {
        "title": "Claude Sessions",
        "width": 400,
        "height": 500,
        "resizable": false,
        "fullscreen": false,
        "visible": false,
        "decorations": false,
        "skipTaskbar": true,
        "alwaysOnTop": true
      }
    ],
    "security": {
      "csp": null
    }
  },
  "bundle": {
    "active": true,
    "targets": "all",
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ]
  }
}
```

**Step 3: Update main.rs for tray functionality**

Replace `src-tauri/src/main.rs`:
```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{
    Manager,
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
};
use tauri_plugin_positioner::{Position, WindowExt};

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_positioner::init())
        .setup(|app| {
            // Create tray icon
            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .icon_as_template(true)
                .on_tray_icon_event(|tray, event| {
                    tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);

                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                let _ = window.move_window(Position::TrayCenter);
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            // Hide window when it loses focus
            let window = app.get_webview_window("main").unwrap();
            let window_clone = window.clone();
            window.on_window_event(move |event| {
                if let tauri::WindowEvent::Focused(false) = event {
                    let _ = window_clone.hide();
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

**Step 4: Verify menubar behavior**

Run:
```bash
npm run tauri dev
```

Expected: App icon appears in menubar, clicking shows/hides the window

**Step 5: Commit**

```bash
git add .
git commit -m "feat: configure menubar app with tray icon"
```

---

## Task 3: Create TypeScript Types

**Files:**
- Create: `src/types/session.ts`

**Step 1: Create session types**

Create `src/types/session.ts`:
```typescript
export type SessionStatus = 'waiting' | 'processing' | 'idle';

export interface Session {
  id: string;
  projectName: string;
  projectPath: string;
  gitBranch: string | null;
  status: SessionStatus;
  lastMessage: string | null;
  lastMessageRole: 'user' | 'assistant' | null;
  lastActivityAt: string;
  pid: number;
  cpuUsage: number;
}

export interface SessionsResponse {
  sessions: Session[];
  totalCount: number;
  waitingCount: number;
}
```

**Step 2: Commit**

```bash
git add src/types/session.ts
git commit -m "feat: add TypeScript types for sessions"
```

---

## Task 4: Implement Rust Session Detection

**Files:**
- Create: `src-tauri/src/session.rs`
- Create: `src-tauri/src/process.rs`
- Modify: `src-tauri/src/main.rs`

**Step 1: Create process monitoring module**

Create `src-tauri/src/process.rs`:
```rust
use serde::{Deserialize, Serialize};
use sysinfo::{Process, System};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaudeProcess {
    pub pid: u32,
    pub cwd: Option<PathBuf>,
    pub cpu_usage: f32,
    pub memory: u64,
}

pub fn find_claude_processes() -> Vec<ClaudeProcess> {
    let mut system = System::new_all();
    system.refresh_all();

    let mut processes = Vec::new();

    for (pid, process) in system.processes() {
        let name = process.name().to_string_lossy().to_lowercase();

        if name.contains("claude") && !name.contains("claude-sessions") {
            let cwd = process.cwd().map(|p| p.to_path_buf());

            processes.push(ClaudeProcess {
                pid: pid.as_u32(),
                cwd,
                cpu_usage: process.cpu_usage(),
                memory: process.memory(),
            });
        }
    }

    processes
}

pub fn get_process_cpu_usage(pid: u32) -> Option<f32> {
    let mut system = System::new_all();
    system.refresh_all();

    let pid = sysinfo::Pid::from_u32(pid);
    system.process(pid).map(|p| p.cpu_usage())
}
```

**Step 2: Create session detection module**

Create `src-tauri/src/session.rs`:
```rust
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::path::PathBuf;

use crate::process::{find_claude_processes, ClaudeProcess};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub id: String,
    pub project_name: String,
    pub project_path: String,
    pub git_branch: Option<String>,
    pub status: SessionStatus,
    pub last_message: Option<String>,
    pub last_message_role: Option<String>,
    pub last_activity_at: String,
    pub pid: u32,
    pub cpu_usage: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionStatus {
    Waiting,
    Processing,
    Idle,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionsResponse {
    pub sessions: Vec<Session>,
    pub total_count: usize,
    pub waiting_count: usize,
}

#[derive(Debug, Deserialize)]
struct JsonlMessage {
    #[serde(rename = "type")]
    msg_type: Option<String>,
    #[serde(rename = "sessionId")]
    session_id: Option<String>,
    cwd: Option<String>,
    #[serde(rename = "gitBranch")]
    git_branch: Option<String>,
    timestamp: Option<String>,
    message: Option<MessageContent>,
}

#[derive(Debug, Deserialize)]
struct MessageContent {
    role: Option<String>,
    content: Option<serde_json::Value>,
}

pub fn get_sessions() -> SessionsResponse {
    let claude_processes = find_claude_processes();
    let mut sessions = Vec::new();

    // Build a map of cwd -> process for matching
    let mut cwd_to_process: HashMap<String, &ClaudeProcess> = HashMap::new();
    for process in &claude_processes {
        if let Some(cwd) = &process.cwd {
            let cwd_str = cwd.to_string_lossy().to_string();
            cwd_to_process.insert(cwd_str, process);
        }
    }

    // Scan ~/.claude/projects for session files
    let claude_dir = dirs::home_dir()
        .map(|h| h.join(".claude").join("projects"))
        .unwrap_or_default();

    if !claude_dir.exists() {
        return SessionsResponse {
            sessions: vec![],
            total_count: 0,
            waiting_count: 0,
        };
    }

    // For each project directory
    if let Ok(entries) = fs::read_dir(&claude_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }

            // Convert directory name back to path
            let dir_name = path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");

            let project_path = dir_name.replace("-", "/");
            let project_path = if project_path.starts_with("/") {
                project_path
            } else {
                format!("/{}", project_path)
            };

            // Check if this project has an active Claude process
            let process = cwd_to_process.get(&project_path);
            if process.is_none() {
                continue; // Skip projects without active processes
            }
            let process = process.unwrap();

            // Find the most recent JSONL file
            if let Some(session) = find_active_session(&path, &project_path, process) {
                sessions.push(session);
            }
        }
    }

    // Sort: waiting first, then processing, then idle
    sessions.sort_by(|a, b| {
        let status_order = |s: &SessionStatus| match s {
            SessionStatus::Waiting => 0,
            SessionStatus::Processing => 1,
            SessionStatus::Idle => 2,
        };
        status_order(&a.status).cmp(&status_order(&b.status))
    });

    let waiting_count = sessions.iter()
        .filter(|s| matches!(s.status, SessionStatus::Waiting))
        .count();
    let total_count = sessions.len();

    SessionsResponse {
        sessions,
        total_count,
        waiting_count,
    }
}

fn find_active_session(project_dir: &PathBuf, project_path: &str, process: &ClaudeProcess) -> Option<Session> {
    // Find the most recently modified JSONL file
    let mut jsonl_files: Vec<_> = fs::read_dir(project_dir)
        .ok()?
        .flatten()
        .filter(|e| {
            e.path().extension()
                .map(|ext| ext == "jsonl")
                .unwrap_or(false)
        })
        .collect();

    jsonl_files.sort_by(|a, b| {
        let time_a = a.metadata().and_then(|m| m.modified()).ok();
        let time_b = b.metadata().and_then(|m| m.modified()).ok();
        time_b.cmp(&time_a)
    });

    let jsonl_path = jsonl_files.first()?.path();

    // Parse the JSONL file to get session info
    let file = File::open(&jsonl_path).ok()?;
    let reader = BufReader::new(file);

    let mut session_id = None;
    let mut git_branch = None;
    let mut last_timestamp = None;
    let mut last_message = None;
    let mut last_role = None;

    // Read last N lines for efficiency
    let lines: Vec<_> = reader.lines().flatten().collect();
    let recent_lines = lines.iter().rev().take(50);

    for line in recent_lines {
        if let Ok(msg) = serde_json::from_str::<JsonlMessage>(line) {
            if session_id.is_none() {
                session_id = msg.session_id;
            }
            if git_branch.is_none() {
                git_branch = msg.git_branch;
            }
            if last_timestamp.is_none() {
                last_timestamp = msg.timestamp;
            }

            if last_message.is_none() {
                if let Some(content) = msg.message {
                    last_role = content.role;
                    last_message = content.content.and_then(|c| {
                        match c {
                            serde_json::Value::String(s) => Some(s),
                            serde_json::Value::Array(arr) => {
                                arr.iter().find_map(|v| {
                                    v.get("text").and_then(|t| t.as_str()).map(String::from)
                                })
                            }
                            _ => None,
                        }
                    });
                }
            }

            if session_id.is_some() && last_message.is_some() {
                break;
            }
        }
    }

    let session_id = session_id?;

    // Determine status
    let status = determine_status(process.cpu_usage, last_role.as_deref(), &last_timestamp);

    // Extract project name from path
    let project_name = project_path
        .split('/')
        .filter(|s| !s.is_empty())
        .last()
        .unwrap_or("Unknown")
        .to_string();

    // Truncate message for preview
    let last_message = last_message.map(|m| {
        if m.len() > 100 {
            format!("{}...", &m[..100])
        } else {
            m
        }
    });

    Some(Session {
        id: session_id,
        project_name,
        project_path: project_path.to_string(),
        git_branch,
        status,
        last_message,
        last_message_role: last_role,
        last_activity_at: last_timestamp.unwrap_or_else(|| "Unknown".to_string()),
        pid: process.pid,
        cpu_usage: process.cpu_usage,
    })
}

fn determine_status(cpu_usage: f32, last_role: Option<&str>, last_timestamp: &Option<String>) -> SessionStatus {
    // High CPU means actively processing
    if cpu_usage > 5.0 {
        return SessionStatus::Processing;
    }

    // Check last message role
    match last_role {
        Some("assistant") => SessionStatus::Waiting,
        Some("user") => SessionStatus::Processing,
        _ => SessionStatus::Idle,
    }
}
```

**Step 3: Update main.rs with commands**

Replace `src-tauri/src/main.rs`:
```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod process;
mod session;

use tauri::{
    Manager,
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
};
use tauri_plugin_positioner::{Position, WindowExt};

use session::{get_sessions, SessionsResponse};

#[tauri::command]
fn get_all_sessions() -> SessionsResponse {
    get_sessions()
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_positioner::init())
        .invoke_handler(tauri::generate_handler![get_all_sessions])
        .setup(|app| {
            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .icon_as_template(true)
                .on_tray_icon_event(|tray, event| {
                    tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);

                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                let _ = window.move_window(Position::TrayCenter);
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            let window = app.get_webview_window("main").unwrap();
            let window_clone = window.clone();
            window.on_window_event(move |event| {
                if let tauri::WindowEvent::Focused(false) = event {
                    let _ = window_clone.hide();
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

**Step 4: Verify Rust compiles**

Run:
```bash
cd src-tauri && cargo check
```

Expected: No errors

**Step 5: Commit**

```bash
git add src-tauri/src/
git commit -m "feat: implement session detection in Rust"
```

---

## Task 5: Implement Terminal Focus

**Files:**
- Create: `src-tauri/src/terminal.rs`
- Modify: `src-tauri/src/main.rs`

**Step 1: Create terminal focus module**

Create `src-tauri/src/terminal.rs`:
```rust
use std::process::Command;

pub fn focus_terminal_for_pid(pid: u32) -> Result<(), String> {
    // Try iTerm2 first, then Terminal.app
    if focus_iterm(pid).is_ok() {
        return Ok(());
    }

    focus_terminal_app(pid)
}

fn focus_iterm(pid: u32) -> Result<(), String> {
    let script = format!(r#"
        tell application "System Events"
            if not (exists process "iTerm2") then
                error "iTerm2 not running"
            end if
        end tell

        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s contains "{}" then
                            select t
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
    "#, pid);

    execute_applescript(&script)
}

fn focus_terminal_app(pid: u32) -> Result<(), String> {
    let script = format!(r#"
        tell application "Terminal"
            activate
            set targetFound to false
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set tabProcesses to processes of t
                        repeat with p in tabProcesses
                            if p contains "{}" then
                                set selected of t to true
                                set index of w to 1
                                set targetFound to true
                                exit repeat
                            end if
                        end repeat
                    end try
                    if targetFound then exit repeat
                end repeat
                if targetFound then exit repeat
            end repeat
        end tell
    "#, pid);

    execute_applescript(&script)
}

fn execute_applescript(script: &str) -> Result<(), String> {
    let output = Command::new("osascript")
        .arg("-e")
        .arg(script)
        .output()
        .map_err(|e| format!("Failed to execute AppleScript: {}", e))?;

    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("AppleScript error: {}", stderr))
    }
}

pub fn focus_terminal_by_path(path: &str) -> Result<(), String> {
    // Fallback: focus by working directory path
    let script = format!(r#"
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if (do script "pwd" in t) contains "{}" then
                            set selected of t to true
                            set index of w to 1
                            return
                        end if
                    end try
                end repeat
            end repeat
        end tell
    "#, path);

    execute_applescript(&script)
}
```

**Step 2: Add focus command to main.rs**

Update `src-tauri/src/main.rs`, add module and command:

At the top, add:
```rust
mod terminal;
```

Add new command:
```rust
#[tauri::command]
fn focus_session(pid: u32, project_path: String) -> Result<(), String> {
    terminal::focus_terminal_for_pid(pid)
        .or_else(|_| terminal::focus_terminal_by_path(&project_path))
}
```

Update invoke_handler:
```rust
.invoke_handler(tauri::generate_handler![get_all_sessions, focus_session])
```

**Step 3: Verify compiles**

Run:
```bash
cd src-tauri && cargo check
```

**Step 4: Commit**

```bash
git add src-tauri/src/
git commit -m "feat: implement terminal focus via AppleScript"
```

---

## Task 6: Build React UI Components

**Files:**
- Create: `src/components/SessionCard.tsx`
- Create: `src/components/SessionGrid.tsx`
- Create: `src/components/Header.tsx`
- Modify: `src/App.tsx`

**Step 1: Create SessionCard component**

Create `src/components/SessionCard.tsx`:
```tsx
import { Session } from '../types/session';

interface SessionCardProps {
  session: Session;
  onClick: () => void;
}

const statusConfig = {
  waiting: {
    color: 'bg-yellow-500',
    label: 'Waiting',
  },
  processing: {
    color: 'bg-green-500',
    label: 'Processing',
  },
  idle: {
    color: 'bg-gray-500',
    label: 'Idle',
  },
};

function formatTimeAgo(timestamp: string): string {
  const date = new Date(timestamp);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;

  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `${diffHours}h ago`;

  const diffDays = Math.floor(diffHours / 24);
  return `${diffDays}d ago`;
}

function truncatePath(path: string, maxLength: number = 30): string {
  if (path.length <= maxLength) return path;

  // Replace home dir with ~
  const homePath = path.replace(/^\/Users\/[^/]+/, '~');
  if (homePath.length <= maxLength) return homePath;

  return '...' + homePath.slice(-(maxLength - 3));
}

export function SessionCard({ session, onClick }: SessionCardProps) {
  const config = statusConfig[session.status];

  return (
    <button
      onClick={onClick}
      className="w-full text-left p-3 bg-[#1a1a1a] hover:bg-[#252525] rounded-lg border border-[#2a2a2a] transition-colors cursor-pointer"
    >
      {/* Header: Status + Name + Branch */}
      <div className="flex items-center gap-2 mb-1">
        <span className={`w-2 h-2 rounded-full ${config.color}`} />
        <span className="font-medium text-sm text-white truncate flex-1">
          {session.projectName}
        </span>
        {session.gitBranch && (
          <span className="text-xs text-gray-500 truncate max-w-[80px]">
            {session.gitBranch}
          </span>
        )}
      </div>

      {/* Path */}
      <div className="text-xs text-gray-500 mb-2 truncate">
        {truncatePath(session.projectPath)}
      </div>

      {/* Message Preview */}
      {session.lastMessage && (
        <div className="text-xs text-gray-400 mb-2 line-clamp-2 italic">
          "{session.lastMessage}"
        </div>
      )}

      {/* Status + Time */}
      <div className="flex items-center justify-between text-xs">
        <span className="text-gray-500">
          {config.label}
        </span>
        <span className="text-gray-600">
          {formatTimeAgo(session.lastActivityAt)}
        </span>
      </div>
    </button>
  );
}
```

**Step 2: Create SessionGrid component**

Create `src/components/SessionGrid.tsx`:
```tsx
import { Session } from '../types/session';
import { SessionCard } from './SessionCard';

interface SessionGridProps {
  sessions: Session[];
  onSessionClick: (session: Session) => void;
}

export function SessionGrid({ sessions, onSessionClick }: SessionGridProps) {
  if (sessions.length === 0) {
    return (
      <div className="flex items-center justify-center h-40 text-gray-500 text-sm">
        No active Claude sessions
      </div>
    );
  }

  return (
    <div className="grid grid-cols-2 gap-2 p-2">
      {sessions.map((session) => (
        <SessionCard
          key={session.id}
          session={session}
          onClick={() => onSessionClick(session)}
        />
      ))}
    </div>
  );
}
```

**Step 3: Create Header component**

Create `src/components/Header.tsx`:
```tsx
interface HeaderProps {
  totalCount: number;
  waitingCount: number;
  onRefresh: () => void;
  isLoading: boolean;
}

export function Header({ totalCount, waitingCount, onRefresh, isLoading }: HeaderProps) {
  return (
    <div className="flex items-center justify-between p-3 border-b border-[#2a2a2a]">
      <div>
        <h1 className="text-sm font-semibold text-white">Claude Sessions</h1>
      </div>
      <button
        onClick={onRefresh}
        disabled={isLoading}
        className="p-1.5 hover:bg-[#2a2a2a] rounded transition-colors disabled:opacity-50"
        title="Refresh"
      >
        <svg
          className={`w-4 h-4 text-gray-400 ${isLoading ? 'animate-spin' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
          />
        </svg>
      </button>
    </div>
  );
}
```

**Step 4: Create Footer component**

Create `src/components/Footer.tsx`:
```tsx
interface FooterProps {
  totalCount: number;
  waitingCount: number;
}

export function Footer({ totalCount, waitingCount }: FooterProps) {
  return (
    <div className="p-2 border-t border-[#2a2a2a] text-xs text-gray-500 text-center">
      {totalCount} session{totalCount !== 1 ? 's' : ''}
      {waitingCount > 0 && ` · ${waitingCount} waiting`}
    </div>
  );
}
```

**Step 5: Commit**

```bash
git add src/components/
git commit -m "feat: create React UI components"
```

---

## Task 7: Implement Session Fetching Hook

**Files:**
- Create: `src/hooks/useSessions.ts`

**Step 1: Create the hook**

Create `src/hooks/useSessions.ts`:
```tsx
import { useState, useEffect, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { Session, SessionsResponse } from '../types/session';

const POLL_INTERVAL = 3000; // 3 seconds

export function useSessions() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [waitingCount, setWaitingCount] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchSessions = useCallback(async () => {
    try {
      const response = await invoke<SessionsResponse>('get_all_sessions');
      setSessions(response.sessions);
      setTotalCount(response.totalCount);
      setWaitingCount(response.waitingCount);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch sessions');
    } finally {
      setIsLoading(false);
    }
  }, []);

  const focusSession = useCallback(async (session: Session) => {
    try {
      await invoke('focus_session', {
        pid: session.pid,
        projectPath: session.projectPath,
      });
    } catch (err) {
      console.error('Failed to focus session:', err);
    }
  }, []);

  // Initial fetch
  useEffect(() => {
    fetchSessions();
  }, [fetchSessions]);

  // Polling
  useEffect(() => {
    const interval = setInterval(fetchSessions, POLL_INTERVAL);
    return () => clearInterval(interval);
  }, [fetchSessions]);

  return {
    sessions,
    totalCount,
    waitingCount,
    isLoading,
    error,
    refresh: fetchSessions,
    focusSession,
  };
}
```

**Step 2: Commit**

```bash
git add src/hooks/
git commit -m "feat: implement session fetching hook with polling"
```

---

## Task 8: Wire Up the App

**Files:**
- Modify: `src/App.tsx`

**Step 1: Update App.tsx**

Replace `src/App.tsx`:
```tsx
import { Header } from './components/Header';
import { SessionGrid } from './components/SessionGrid';
import { Footer } from './components/Footer';
import { useSessions } from './hooks/useSessions';

function App() {
  const {
    sessions,
    totalCount,
    waitingCount,
    isLoading,
    error,
    refresh,
    focusSession,
  } = useSessions();

  return (
    <div className="min-h-screen bg-[#0a0a0a] flex flex-col">
      <Header
        totalCount={totalCount}
        waitingCount={waitingCount}
        onRefresh={refresh}
        isLoading={isLoading}
      />

      <div className="flex-1 overflow-y-auto">
        {error ? (
          <div className="p-4 text-red-400 text-sm text-center">
            {error}
          </div>
        ) : (
          <SessionGrid
            sessions={sessions}
            onSessionClick={focusSession}
          />
        )}
      </div>

      <Footer totalCount={totalCount} waitingCount={waitingCount} />
    </div>
  );
}

export default App;
```

**Step 2: Verify the app runs**

Run:
```bash
npm run tauri dev
```

Expected: App shows in menubar, displays session cards when clicked

**Step 3: Commit**

```bash
git add src/App.tsx
git commit -m "feat: wire up App component with session display"
```

---

## Task 9: Polish and Final Touches

**Files:**
- Modify: `src/index.css`
- Modify: `src-tauri/tauri.conf.json`

**Step 1: Add custom scrollbar and polish styles**

Update `src/index.css`:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  background-color: #0a0a0a;
  color: #fafafa;
}

body {
  margin: 0;
  min-height: 100vh;
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
  -webkit-font-smoothing: antialiased;
}

/* Custom scrollbar */
::-webkit-scrollbar {
  width: 6px;
}

::-webkit-scrollbar-track {
  background: transparent;
}

::-webkit-scrollbar-thumb {
  background: #3a3a3a;
  border-radius: 3px;
}

::-webkit-scrollbar-thumb:hover {
  background: #4a4a4a;
}

/* Line clamp utility */
.line-clamp-2 {
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
```

**Step 2: Ensure window sizing is correct**

Verify `src-tauri/tauri.conf.json` has correct window settings (already set in Task 2).

**Step 3: Test the complete app**

Run:
```bash
npm run tauri dev
```

Verify:
- [ ] Menubar icon appears
- [ ] Clicking icon shows/hides window
- [ ] Sessions are displayed in grid
- [ ] Status colors are correct
- [ ] Clicking a card focuses the terminal
- [ ] Auto-refresh works (check after 3 seconds)

**Step 4: Commit**

```bash
git add .
git commit -m "feat: polish UI with custom scrollbar and styles"
```

---

## Task 10: Build for Distribution

**Files:**
- None new

**Step 1: Build the app**

Run:
```bash
npm run tauri build
```

Expected: Creates `.dmg` and `.app` in `src-tauri/target/release/bundle/`

**Step 2: Test the built app**

Open the `.app` bundle and verify it works correctly outside dev mode.

**Step 3: Final commit**

```bash
git add .
git commit -m "chore: ready for distribution"
```

---

## Summary

After completing all tasks, you will have:

1. A Tauri menubar app that lives in the macOS menu bar
2. Automatic detection of all running Claude Code sessions
3. Status indicators (waiting/processing/idle) based on CPU usage and message state
4. Card display showing project name, branch, path, message preview, and timing
5. One-click terminal focus via AppleScript
6. Auto-refresh every 3 seconds
7. Dark theme matching modern macOS aesthetics
