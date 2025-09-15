#!/usr/bin/env bash
set -euo pipefail

# Fail-friendly logging
log() { echo "[install] $*"; }
die() { echo "[install][error] $*" >&2; exit 1; }

# Wrapper installer for PiGuard
# - Optional: --repo <git-url> [--branch <name>] to clone first
# - Optional: --skip-ui to skip building the UI
# Then calls scripts/install_pi.sh inside the repo

usage() {
  cat <<EOF
Usage: sudo ./install.sh [--repo <url>] [--branch <name>] [--skip-ui]

Examples:
  sudo ./install.sh
  sudo ./install.sh --repo https://github.com/mardigiorgio/WiPi-Guardian.git
  sudo ./install.sh --repo git@github.com:mardigiorgio/WiPi-Guardian.git --branch main --skip-ui
EOF
}

REPO=""
BRANCH="main"
SKIP_UI=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"; shift 2;;
    --branch)
      BRANCH="$2"; shift 2;;
    --skip-ui)
      SKIP_UI=1; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  log "Re-running with sudo..."
  exec sudo -E "$0" "$@"
fi

WORKDIR="$(pwd)"
if [[ -n "$REPO" ]]; then
  # Clone into a temp working dir
  TMPDIR="/tmp/piguard-src-$$"
  mkdir -p "$TMPDIR"
  if ! command -v git >/dev/null 2>&1; then
    log "git not found; installing via apt..."
    apt-get update -y || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y git || die "failed to install git"
  fi
  log "Cloning $REPO (branch=$BRANCH) to $TMPDIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO" "$TMPDIR" || die "git clone failed"
  WORKDIR="$TMPDIR"
fi

if [[ ! -x "scripts/install_pi.sh" ]]; then
  die "local installer not found: scripts/install_pi.sh (run from a project checkout)"
fi

# Always use local, hardened installer; pass SRC_DIR pointing to cloned repo or current dir
# Backward-compat: some older installers call choose_prefix; provide a no-op fallback and export it
choose_prefix() { :; }
export -f choose_prefix || true
if [[ $SKIP_UI -eq 1 ]]; then
  log "Running installer with SKIP_UI=1 from SRC_DIR=$WORKDIR"
  SRC_DIR="$WORKDIR" SKIP_UI=1 bash "scripts/install_pi.sh" || die "installer failed"
else
  log "Running installer from SRC_DIR=$WORKDIR"
  SRC_DIR="$WORKDIR" bash "scripts/install_pi.sh" || die "installer failed"
fi

log "Install complete. Services: piguard-api piguard-sensor piguard-sniffer"
