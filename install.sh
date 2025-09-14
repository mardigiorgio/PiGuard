#!/usr/bin/env bash
set -euo pipefail

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
  echo "This installer must run as root (sudo)." >&2
  exit 1
fi

WORKDIR="$(pwd)"
if [[ -n "$REPO" ]]; then
  # Clone into a temp working dir
  TMPDIR="/tmp/piguard-src-$$"
  mkdir -p "$TMPDIR"
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 --branch "$BRANCH" "$REPO" "$TMPDIR"
  else
    echo "git is required to clone --repo URL" >&2
    exit 1
  fi
  WORKDIR="$TMPDIR"
fi

if [[ ! -x "$WORKDIR/scripts/install_pi.sh" ]]; then
  echo "installer not found: $WORKDIR/scripts/install_pi.sh" >&2
  echo "Make sure you are running this from a PiGuard checkout or pass --repo <url>." >&2
  exit 1
fi

# Pass SKIP_UI to the real installer
if [[ $SKIP_UI -eq 1 ]]; then
  SKIP_UI=1 bash "$WORKDIR/scripts/install_pi.sh"
else
  bash "$WORKDIR/scripts/install_pi.sh"
fi

echo "Install complete."

