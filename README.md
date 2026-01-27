# Agent Manager X

A macOS desktop app to monitor your AI coding agents in real-time.

Features:

- Better reliability when it comes to showing current progress
- Improved UX in a bunch of areas
- Default Editor and Default Terminal Support
- Themes and background image support

## Supported Agents

- **Claude Code** - Anthropic's official CLI for Claude
- **OpenCode** - Open-source AI coding assistant

## Features

- View all active coding agent sessions in one place
- Real-time status detection (Thinking, Processing, Waiting, Idle)
- Global hotkey to toggle visibility (default: `Ctrl+Space`, configurable)
- Click to focus on a specific session's terminal
- Custom session names (rename via kebab menu)
- Quick access URL for each session (e.g., dev server links)

### DMG

Download the latest DMG from [Releases](https://github.com/maddada/agent-manager-x/releases).

## Tech Stack

- Tauri 2.x
- React + TypeScript
- Tailwind CSS + shadcn/ui
