#!/bin/bash
set -e

# Dev script - builds and runs the app with current code
# Kills any existing instances first

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Stopping existing instances ==="
pkill -f "Agent Manager X" 2>/dev/null || true
pkill -f "agent-manager-x" 2>/dev/null || true
sleep 1

echo "=== Building and running ==="
cd "$PROJECT_ROOT"
npm run tauri dev
