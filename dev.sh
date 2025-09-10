#!/usr/bin/env bash
set -euo pipefail

# Dev helper: start API + sensor (+sniffer) and the UI dev server.
# Usage:
#   ./dev.sh                 # uses configs/wids.yaml
#   WIDS_CONFIG=path/to.yml ./dev.sh --no-sniffer

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine config path: first arg if it's a file, else WIDS_CONFIG or default
CONFIG="${WIDS_CONFIG:-configs/wids.yaml}"
ARGS=("$@")
if [[ ${#ARGS[@]} -gt 0 && -f "${ARGS[0]}" ]]; then
  CONFIG="${ARGS[0]}"
  ARGS=("${ARGS[@]:1}")
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "Config not found: $CONFIG" >&2
  exit 1
fi

# Optional sudo pre-auth so sniffer can start with sudo and prompt once.
# Skip by setting NO_SUDO_PROMPT=1
if [[ "${NO_SUDO_PROMPT:-0}" != "1" && $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "[dev] Pre-authenticating sudo (for sniffer)…"
    if sudo -v; then
      # Keep sudo timestamp fresh while this script runs
      sudo -n true 2>/dev/null
      ( while true; do sleep 60; sudo -n true 2>/dev/null || true; done ) &
      SUDO_KEEPALIVE_PID=$!
      cleanup() { kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; sudo -k >/dev/null 2>&1 || true; }
      trap cleanup EXIT INT TERM
    else
      echo "[dev] Sudo auth failed or cancelled. You can start sniffer manually:"
      echo "      sudo python -m wids sniffer --config $CONFIG" >&2
    fi
  fi
fi

python3 -m wids dev --config "$CONFIG" --ui "${ARGS[@]}"
rc=$?
exit $rc
