# Claude Sessions Viewer - Design Document

## Overview

A Tauri menubar app for macOS that monitors all running Claude Code sessions and displays them as cards. Allows quick identification of which sessions need attention (waiting for input, processing, or idle) and one-click focus to the relevant terminal window.

## Problem Statement

When running multiple Claude Code sessions across different terminals, it's difficult to:
- Track which session is waiting for user input
- Know which session is actively processing
- Identify which sessions have completed their tasks
- Quickly switch to the session that needs attention

## Solution

A lightweight menubar app that:
1. Detects all running Claude Code sessions
2. Shows their status in a grid of cards
3. Allows one-click navigation to any session's terminal

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Architecture                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────┐      ┌─────────────┐      ┌───────────┐  │
│   │   Frontend  │ ◄──► │ Tauri Bridge│ ◄──► │  Rust     │  │
│   │   (React)   │      │  (Commands) │      │  Backend  │  │
│   └─────────────┘      └─────────────┘      └───────────┘  │
│         │                                         │         │
│         ▼                                         ▼         │
│   ┌─────────────┐                         ┌───────────────┐ │
│   │  Session    │                         │ Data Sources  │ │
│   │  Cards UI   │                         │               │ │
│   └─────────────┘                         │ • ~/.claude/  │ │
│                                           │   projects/   │ │
│                                           │   *.jsonl     │ │
│                                           │               │ │
│                                           │ • Process list│ │
│                                           │   (sysinfo)   │ │
│                                           │               │ │
│                                           │ • AppleScript │ │
│                                           │   (terminal)  │ │
│                                           └───────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Components

1. **Rust Backend** - Handles all system interaction:
   - Scans `~/.claude/projects/` for session JSONL files
   - Uses `sysinfo` crate to get Claude process CPU/memory
   - Matches processes to sessions via PID or working directory
   - Executes AppleScript to focus terminal windows

2. **Tauri Bridge** - Exposes Rust functions to frontend:
   - `get_sessions()` - Returns list of active sessions with status
   - `focus_session(session_id)` - Activates the terminal for that session
   - Auto-refresh via polling (every 2-3 seconds)

3. **React Frontend** - The menubar dropdown UI:
   - Grid of session cards
   - Dark theme
   - Sorted by status (waiting first, then processing, then idle)

---

## Session State Detection

### Process Discovery

1. Find all running `claude` processes via `sysinfo` crate
2. Extract PID and working directory for each process
3. Match to JSONL session files in `~/.claude/projects/`

### Status Determination (Hybrid Approach)

```
CPU > 5%  ──────────────────────►  🟢 PROCESSING
    │
    ▼
Last message = "assistant"  ────►  🟡 WAITING (needs your input)
    │
    ▼
Last message = "user"  ──────────►  🟢 PROCESSING (Claude thinking)
    │
    ▼
No activity > 5min  ─────────────►  ⚫ IDLE
```

### Status Definitions

| Status | Color | Meaning |
|--------|-------|---------|
| 🟡 **Waiting** | Yellow | Claude responded, waiting for your input |
| 🟢 **Processing** | Green | Claude is actively thinking/working |
| ⚫ **Idle** | Gray | Session open but no recent activity |

### Data from JSONL Files

- `sessionId` - Unique identifier
- `cwd` - Working directory (becomes project name)
- `gitBranch` - Current branch
- `timestamp` - When last message occurred
- `message.role` - "user" or "assistant"
- `message.content` - For the preview text

---

## UI Design

### Menubar Dropdown

```
┌──────────────────────────────────────────────────────────────┐
│  Menu Bar                                          🤖 ▼     │
└──────────────────────────────────────────────────────────────┘
                                                      │
                    ┌─────────────────────────────────┴────────┐
                    │  Claude Sessions                    ⟳   │
                    ├─────────────────────────────────────────┤
                    │                                         │
                    │  ┌─────────────┐  ┌─────────────┐      │
                    │  │ 🟡 ai-image │  │ 🟢 backend  │      │
                    │  │    main     │  │    main     │      │
                    │  │ ~/Projects/ │  │ ~/Projects/ │      │
                    │  │ ai-image-.. │  │ backend-... │      │
                    │  │             │  │             │      │
                    │  │ "I'll add   │  │ "Running    │      │
                    │  │ the violet.."│  │ npm test..."│      │
                    │  │             │  │             │      │
                    │  │ Waiting 2m  │  │ Processing  │      │
                    │  └─────────────┘  └─────────────┘      │
                    │                                         │
                    ├─────────────────────────────────────────┤
                    │  4 sessions · 2 waiting                 │
                    └─────────────────────────────────────────┘
```

### Card Design

```
┌───────────────────────────────────┐
│ 🟡  ai-image-dashboard      main  │  ← Status dot, name (bold), branch (muted)
│     ~/Projects/ai-image-dash...   │  ← Path (truncated, muted)
│                                   │
│     "I'll help you implement      │  ← Last message preview (2 lines max)
│     the dark theme with..."       │
│                                   │
│     Waiting · 2m ago              │  ← Status label + relative time
└───────────────────────────────────┘
```

### Visual Specs

- **Window size:** ~400px wide, height adapts to content (max ~500px, scrollable)
- **Grid:** 2 columns
- **Theme:** Dark background (`#0a0a0a`), subtle card backgrounds (`#1a1a1a`)
- **Cards:** Rounded corners, subtle border, hover highlight
- **Typography:** System font (SF Pro on macOS)
- **Refresh:** Auto every 2-3 seconds, manual refresh button (⟳)
- **Sort order:** Waiting → Processing → Idle

---

## Terminal Focus

### Click Action

When a card is clicked, focus the terminal window/tab running that session.

### Implementation

1. Track parent PID of each Claude process
2. Use AppleScript to find and focus the terminal tab with that shell process
3. Support both Terminal.app and iTerm2

### AppleScript Example (Terminal.app)

```applescript
tell application "Terminal"
  activate
  repeat with w in windows
    repeat with t in tabs of w
      if tty of t contains process info then
        set selected of t to true
        set frontmost of w to true
      end if
    end repeat
  end repeat
end tell
```

---

## Tech Stack

### Frontend
- React 18
- TypeScript
- Tailwind CSS (dark theme)
- Vite (bundler)

### Backend
- Tauri 2.x
- sysinfo (process monitoring)
- serde/serde_json (JSONL parsing)
- tauri-plugin-positioner (menubar positioning)

---

## Project Structure

```
claude-sessions-viewer/
├── src/                      # React frontend
│   ├── App.tsx               # Main app component
│   ├── components/
│   │   ├── SessionCard.tsx   # Individual session card
│   │   ├── SessionGrid.tsx   # Grid layout
│   │   └── Header.tsx        # Title + refresh button
│   ├── hooks/
│   │   └── useSessions.ts    # Polling + state management
│   ├── types/
│   │   └── session.ts        # TypeScript interfaces
│   ├── main.tsx              # Entry point
│   └── index.css             # Tailwind + dark theme
│
├── src-tauri/                # Rust backend
│   ├── src/
│   │   ├── main.rs           # Tauri entry point
│   │   ├── commands.rs       # Tauri commands
│   │   ├── session.rs        # Session detection logic
│   │   ├── process.rs        # Process monitoring
│   │   └── terminal.rs       # AppleScript terminal focus
│   ├── Cargo.toml
│   └── tauri.conf.json
│
├── package.json
└── tailwind.config.js
```

---

## Summary

| Aspect | Decision |
|--------|----------|
| **Purpose** | Monitor Claude Code sessions, see which need attention |
| **App type** | Tauri menubar app |
| **Frontend** | React + TypeScript + Tailwind (dark theme) |
| **Backend** | Rust with sysinfo crate |
| **Session detection** | Hybrid: JSONL parsing + process CPU monitoring |
| **UI layout** | Grid of cards (2 columns) |
| **Card info** | Project name, branch, path, message preview, status, time |
| **Status types** | Waiting (yellow), Processing (green), Idle (gray) |
| **Click action** | Focus terminal window via AppleScript |
| **Terminal support** | Terminal.app + iTerm2 |
| **Refresh** | Auto-poll every 2-3 seconds |
