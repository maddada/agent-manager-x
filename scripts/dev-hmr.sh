#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PORT=1533
VITE_PID=""

cleanup() {
  if [[ -n "$VITE_PID" ]] && kill -0 "$VITE_PID" >/dev/null 2>&1; then
    kill "$VITE_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

bun run link:electrobun
bun run build

if lsof -iTCP:"$PORT" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
  echo "Using existing Vite server on port $PORT"
else
  echo "Starting Vite server on port $PORT"
  bun run hmr >/dev/null 2>&1 &
  VITE_PID=$!

  for _ in {1..100}; do
    if lsof -iTCP:"$PORT" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

ELECTROBUN_DEV_URL="http://localhost:$PORT" bash ./scripts/run-electrobun-dev.sh
