# Quick Start Guide

## Prerequisites

- **macOS** (Monterey or later)
- **Bun** (latest)
- **Xcode Command Line Tools**

```bash
# Install Xcode CLI tools (if not already installed)
xcode-select --install

# Install Bun (if not already installed)
curl -fsSL https://bun.sh/install | bash
```

## Setup

1. **Clone and install dependencies**

```bash
git clone https://github.com/maddada/agent-manager-x.git
cd agent-manager-x
bun install
```

This project expects Electrobun source to be available at `../electrobun` (sibling folder), matching the scripts in `package.json`.

2. **Run in development mode**

```bash
bun run dev:hmr
```

This starts the Vite dev server and the Electrobun desktop runtime.

## Build for Production

```bash
bun run build
```

The built app bundle is produced by Electrobun.

## Available Scripts

| Command | Description |
|---------|-------------|
| `bun run dev` | Build frontend and run Electrobun app |
| `bun run dev:hmr` | Run Electrobun app with Vite HMR server |
| `bun run build:frontend` | Type-check and build frontend only |
| `bun run build` | Build frontend + Electrobun app |
| `bun run build:prod` | Build production channel bundle |
| `bun run test` | Run frontend tests |

## Project Structure

```
agent-manager-x/
├── src/                    # React frontend
│   ├── components/         # UI components
│   ├── hooks/              # React hooks
│   ├── lib/                # Utilities
│   └── types/              # TypeScript types
├── src/bun/                # Electrobun backend/runtime
│   └── backend/
│       ├── session*.ts     # Agent session parsing
│       ├── process*.ts     # Process detection
│       ├── commands.ts     # Native command handlers
│       └── notifications.ts
├── src/platform/           # Frontend native bridge
├── electrobun.config.ts    # Electrobun build config
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
- Run `bun install` to ensure dependencies are installed
- Ensure Electrobun and Bun are available in your environment

**Terminal focus doesn't work:**
- Grant accessibility permissions to the app in System Preferences > Privacy & Security > Accessibility
