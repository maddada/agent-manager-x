# DEV

## Prereqs
- Bun installed
- Electrobun source checked out at `../electrobun` (sibling folder)

## Setup
```bash
bun install
```

## Main Commands
```bash
# Run app with HMR (recommended for development)
bun run dev:hmr

# Run app without HMR
bun run dev

# Typecheck + build frontend only
bun run build:frontend

# Full Electrobun build
bun run build

# Production channel build
bun run build:prod

# Tests
bun run test
```
