# Commands

pnpm run build:install:run

/publish <version> to push to brew

# Quick Start Guide

## Prerequisites

- **macOS** (Monterey or later)
- **Node.js** (v18+)
- **Rust** (latest stable)
- **Xcode Command Line Tools**

```bash
# Install Xcode CLI tools (if not already installed)
xcode-select --install

# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## Setup

1. **Clone and install dependencies**

```bash
git clone https://github.com/maddada/agent-manager-x.git
cd agent-manager-x
npm install
```

2. **Run in development mode**

```bash
npm run tauri dev
```

This starts both the Vite dev server (frontend) and the Tauri app (Rust backend).

## Build for Production

```bash
npm run tauri build
```

The built app will be in `src-tauri/target/release/bundle/`.

## Available Scripts

| Command | Description |
|---------|-------------|
| `npm run tauri dev` | Start development server with hot reload |
| `npm run tauri build` | Build production app |
| `npm run build` | Build frontend only |
| `npm run dev` | Run Vite dev server only (no Tauri) |
| `npm run test` | Run frontend tests |
| `npm run test:rust` | Run Rust tests |
| `npm run test:all` | Run all tests |

## Project Structure

```
agent-manager-x/
├── src/                    # React frontend
│   ├── components/         # UI components
│   ├── hooks/              # React hooks
│   ├── lib/                # Utilities
│   └── types/              # TypeScript types
├── src-tauri/              # Rust backend
│   └── src/
│       ├── agent/          # Agent detectors (Claude, Codex, OpenCode)
│       ├── commands/       # Tauri commands
│       ├── process/        # Process detection
│       ├── session/        # Session models
│       └── terminal/       # Terminal focus utilities
└── package.json
```

## Usage

Once running, the app will:
- Automatically detect running Claude, Codex, and OpenCode sessions
- Show real-time status (Thinking, Processing, Waiting, Idle)
- Allow you to click a session card to focus its terminal
- Use `Ctrl+Space` (configurable) to toggle the window

### Header Buttons

- **Claude / Codex / OpenCode** buttons show session counts and kill all sessions of that type when clicked
- **Settings** (gear icon) to configure the global hotkey
- **Refresh** (circular arrow) to manually refresh sessions

## Troubleshooting

**App doesn't detect sessions:**
- Ensure you have active Claude/Codex/OpenCode sessions running in terminal
- Check that the agent CLI is in your PATH

**Build fails:**
- Run `rustup update` to ensure Rust is up to date
- Run `npm install` to ensure all dependencies are installed

**Terminal focus doesn't work:**
- Grant accessibility permissions to the app in System Preferences > Privacy & Security > Accessibility
