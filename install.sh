#!/usr/bin/env bash
set -euo pipefail

# Fail-friendly logging
log() { echo "[install] $*"; }
die() { echo "[install][error] $*" >&2; exit 1; }

# Wrapper installer for PiGuard
# - Optional: --repo <git-url> [--branch <name>] [--ref <sha|tag>] to clone first
# - Optional: --source <path> to use a local checkout explicitly
# - Optional: --skip-ui to skip building the UI (passes SKIP_UI=1)
# - Optional: --interactive | --no-interactive to control TTY prompts
# Then calls scripts/install_pi.sh inside the repo

usage() {
  cat <<EOF
Usage: sudo ./install.sh [options]

Options:
  --repo <url>           Clone this repo first into a temp dir
  --branch <name>        Branch to clone (default: main)
  --ref <sha|tag>        Checkout a specific commit or tag after clone
  --source <path>        Use local checkout at <path> (alt to --repo)
  --skip-ui              Skip building the UI
  --interactive          Force interactive config prompts
  --no-interactive       Disable interactive prompts
  -h, --help             Show help

Examples:
  sudo ./install.sh --interactive
  sudo ./install.sh --repo https://github.com/mardigiorgio/PiGuard.git --branch main
  sudo ./install.sh --source /path/to/PiGuard --skip-ui --no-interactive
EOF
}

REPO=""
BRANCH="main"
REF=""
SOURCE=""
SKIP_UI=0
INTERACTIVE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"; shift 2;;
    --branch)
      BRANCH="$2"; shift 2;;
    --ref)
      REF="$2"; shift 2;;
    --source)
      SOURCE="$2"; shift 2;;
    --skip-ui)
      SKIP_UI=1; shift;;
    --interactive)
      INTERACTIVE=1; shift;;
    --no-interactive)
      INTERACTIVE=0; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

# Elevate to root if needed
if [[ $EUID -ne 0 ]]; then
  log "Re-running with sudo..."
  exec sudo -E "$0" "$@"
fi

# Preflight: need apt-get for auto git install when cloning
if [[ -n "$REPO" ]] && ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    log "git not found; installing via apt..."
    apt-get update -y || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y git || die "failed to install git"
  else
    die "git not found and apt-get unavailable; install git or pass --source <path>"
  fi
fi

WORKDIR=""
TMPDIR=""
cleanup() {
  if [[ -n "${TMPDIR}" && -d "${TMPDIR}" ]]; then
    rm -rf "${TMPDIR}" || true
  fi
}
trap cleanup EXIT

if [[ -n "$REPO" ]]; then
  TMPDIR="/tmp/piguard-src-$$"
  mkdir -p "$TMPDIR"
  log "Cloning $REPO (branch=$BRANCH) to $TMPDIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO" "$TMPDIR" || die "git clone failed"
  if [[ -n "$REF" ]]; then
    log "Checking out ref: $REF"
    (cd "$TMPDIR" && git fetch --depth 1 origin "$REF" || true && git checkout "$REF") || die "failed to checkout $REF"
  fi
  WORKDIR="$TMPDIR"
elif [[ -n "$SOURCE" ]]; then
  [[ -d "$SOURCE" ]] || die "--source path does not exist: $SOURCE"
  WORKDIR="$(cd "$SOURCE" && pwd)"
else
  WORKDIR="$(pwd)"
fi

cd "$WORKDIR"
if [[ ! -x "scripts/install_pi.sh" ]]; then
  die "local installer not found: scripts/install_pi.sh (run from a project checkout)"
fi

# Always use local, hardened installer; pass SRC_DIR pointing to cloned repo or chosen dir
# Backward-compat: some older installers call choose_prefix; provide a no-op fallback and export it
choose_prefix() { :; }
export -f choose_prefix || true

if [[ $SKIP_UI -eq 1 ]]; then
  log "Running installer with SKIP_UI=1 from SRC_DIR=$WORKDIR"
  SRC_DIR="$WORKDIR" SKIP_UI=1 INTERACTIVE="${INTERACTIVE}" bash "scripts/install_pi.sh" || die "installer failed"
else
  log "Running installer from SRC_DIR=$WORKDIR"
  SRC_DIR="$WORKDIR" INTERACTIVE="${INTERACTIVE}" bash "scripts/install_pi.sh" || die "installer failed"
fi

log "Install complete. Services: piguard-api piguard-sensor piguard-sniffer"
