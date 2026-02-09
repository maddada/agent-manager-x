#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p node_modules

if [[ -L node_modules/electrobun ]]; then
  rm -f node_modules/electrobun
fi

if [[ ! -d node_modules/electrobun ]]; then
  cp -R ../electrobun/package node_modules/electrobun
fi

PLATFORM=""
ARCH=""

case "$(uname -s)" in
  Darwin) PLATFORM="macos" ;;
  Linux) PLATFORM="linux" ;;
  *) PLATFORM="" ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64) ARCH="x64" ;;
  *) ARCH="" ;;
esac

if [[ -n "$PLATFORM" && -n "$ARCH" ]]; then
  PLATFORM_API="node_modules/electrobun/dist-${PLATFORM}-${ARCH}/api"
  if [[ -d "$PLATFORM_API" ]]; then
    mkdir -p node_modules/electrobun/dist
    rm -rf node_modules/electrobun/dist/api
    ln -sfn ../dist-"${PLATFORM}"-"${ARCH}"/api node_modules/electrobun/dist/api
  fi
fi

if [[ ! -e node_modules/electrobun/dist/api ]]; then
  mkdir -p node_modules/electrobun/dist
  if [[ -d node_modules/electrobun/src ]]; then
    rm -rf node_modules/electrobun/dist/api
    ln -sfn ../src node_modules/electrobun/dist/api
  fi
fi
