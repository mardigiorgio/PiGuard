#!/usr/bin/env bash
set -euo pipefail

# PiGuard installer for Raspberry Pi OS/Ubuntu arm64
# - Installs runtime deps
# - Creates piguard user and directories
# - Sets up venv and installs Python deps
# - Builds UI if Node is present
# - Installs systemd units and enables services

APP_DIR=/opt/piguard
CFG_DIR=/etc/piguard
DATA_DIR=/var/lib/piguard
VENV="$APP_DIR/.venv"
PY=""

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This installer must run as root (sudo)." >&2
    exit 1
  fi
}

pkg_install() {
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-pip python3-setuptools python3-dev \
    git rsync iproute2 iw libcap2-bin curl ca-certificates gnupg \
    pkg-config libpcap0.8
}

# Ensure a usable Node.js/npm is available (tries apt first, then NodeSource)
ensure_node() {
  if command -v npm >/dev/null 2>&1; then
    return 0
  fi
  echo "Installing Node.js/npm via apt..."
  if DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs npm >/dev/null 2>&1; then
    if command -v npm >/dev/null 2>&1; then
      return 0
    fi
  fi
  echo "Apt nodejs/npm not available or not sufficient; using NodeSource (Node 20.x)"
  # Install NodeSource repo for Node.js 20.x
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs || true
  fi
}

create_user() {
  if ! id piguard >/dev/null 2>&1; then
    useradd --system --create-home --home-dir /var/lib/piguard --shell /usr/sbin/nologin piguard
  fi
}

sync_code() {
  mkdir -p "$APP_DIR"
  local src
  src="${SRC_DIR:-.}"
  rsync -a --delete --exclude .git --exclude ui/node_modules --exclude ui/dist "$src/" "$APP_DIR/"
}

setup_dirs() {
  mkdir -p "$CFG_DIR" "$DATA_DIR"
  chown -R piguard:piguard "$DATA_DIR"
}

setup_config() {
  if [[ ! -f "$CFG_DIR/wids.yaml" ]]; then
    cp "$APP_DIR/configs/wids.example.yaml" "$CFG_DIR/wids.yaml"
    # Point DB to /var/lib/piguard/db.sqlite
    sed -i -E "s|^\s*path:\s*.*$|  path: $DATA_DIR/db.sqlite|" "$CFG_DIR/wids.yaml"
  fi
}

setup_venv() {
  if [[ ! -d "$VENV" ]]; then
    # Create venv with copies to avoid symlinked python -> /usr/bin/python3 (prevents exec EPERM issues)
    python3 -m venv --copies "$VENV"
  fi
  # shellcheck disable=SC1090
  source "$VENV/bin/activate"
  pip install --upgrade pip wheel
  # Install dependencies (editable install keeps source path and serves UI from repo)
  pip install -e "$APP_DIR"
  PY="$VENV/bin/python"

  # Ensure venv python is a real binary and executable
  if [[ -L "$VENV/bin/python3" ]]; then
    echo "Recreating venv with --copies to avoid symlinked python"
    deactivate || true
    rm -rf "$VENV"
    python3 -m venv --copies "$VENV"
    # shellcheck disable=SC1090
    source "$VENV/bin/activate"
    pip install --upgrade pip wheel
    pip install -e "$APP_DIR"
    PY="$VENV/bin/python"
  fi
  chmod 755 "$VENV/bin/python3" || true
}

set_caps() {
  # Default: do NOT set file capabilities to avoid EPERM with systemd's NoNewPrivileges.
  # If you really want file caps instead of service AmbientCapabilities, set USE_SETCAP=1.
  if [[ "${USE_SETCAP:-0}" -eq 1 ]]; then
    local pybin
    pybin=$(readlink -f "$VENV/bin/python3" || true)
    if [[ -n "$pybin" ]]; then
      setcap cap_net_raw,cap_net_admin+eip "$pybin" || true
    fi
  fi
  # Always clear capabilities on system python to avoid surprises when venv uses a symlink
  setcap -r /usr/bin/python3 2>/dev/null || true
  setcap -r /usr/bin/python 2>/dev/null || true
}

build_ui() {
  if [[ "${SKIP_UI:-0}" -eq 1 ]]; then
    echo "Skipping UI build (SKIP_UI=1)"
    return
  fi

  # Try to ensure Node/npm exists before building
  ensure_node || true

  # Try root PATH first
  if command -v npm >/dev/null 2>&1; then
    echo "Building UI with root npm..."
    pushd "$APP_DIR/ui" >/dev/null
    npm ci
    npm run build
    popd >/dev/null
    return
  fi

  # If root can't find npm, try the invoking user (helps with nvm installs)
  if [[ -n "${SUDO_USER:-}" ]]; then
    # Check npm in the user's login shell so nvm is loaded
    if su -l "$SUDO_USER" -c "bash -lc 'command -v npm'" >/dev/null 2>&1; then
      echo "Building UI with $SUDO_USER's npm (nvm) ..."
      # Ensure the user can write to the UI directory during build
      chown -R "$SUDO_USER":"$SUDO_USER" "$APP_DIR/ui" || true
      su -l "$SUDO_USER" -c "bash -lc 'cd \"$APP_DIR/ui\" && npm ci && npm run build'"
      # Restore ownership to root (optional; keeps deployment consistent)
      chown -R root:root "$APP_DIR/ui" || true
      return
    fi
  fi

  echo "npm not found; skipping UI build. The API will still run without static UI."
}

install_units() {
  install -m 0644 "$APP_DIR/deploy/systemd/piguard-api.service" /etc/systemd/system/
  install -m 0644 "$APP_DIR/deploy/systemd/piguard-sensor.service" /etc/systemd/system/
  install -m 0644 "$APP_DIR/deploy/systemd/piguard-sniffer.service" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now piguard-api piguard-sensor piguard-sniffer || true
  # Show brief status summary
  systemctl --no-pager --full status piguard-api | sed -n '1,12p' || true
  systemctl --no-pager --full status piguard-sensor | sed -n '1,12p' || true
  systemctl --no-pager --full status piguard-sniffer | sed -n '1,12p' || true
}

sudoers_snippet() {
  cat >/etc/sudoers.d/piguard-iw-ip <<EOF
Cmnd_Alias PIGUARD_NET = /sbin/ip, /usr/sbin/ip, /usr/sbin/iw, /sbin/iw
piguard ALL=(root) NOPASSWD: PIGUARD_NET
Defaults!PIGUARD_NET !requiretty
EOF
  chmod 0440 /etc/sudoers.d/piguard-iw-ip
}

post_notes() {
  cat <<EOF
PiGuard installed.

Config:    $CFG_DIR/wids.yaml
Database:  $DATA_DIR/db.sqlite
Code:      $APP_DIR
Venv:      $VENV

Services:
  systemctl start piguard-sniffer piguard-api piguard-sensor
  systemctl status piguard-api

Next steps:
  1) Create a monitor interface (safer) and set capture.iface in config or via UI:
     iw dev wlan0 interface add wlan0mon type monitor && ip link set wlan0mon up
  2) Edit $CFG_DIR/wids.yaml: set api.api_key and defense.ssid
  3) Restart services: systemctl restart piguard-*

UI:
  If you built the UI, browse to http://<pi-ip>:8080/ and set X-Api-Key in the UI dev env if needed.
EOF
}

choose_prefix() {
  # If /opt is mounted noexec, fall back to /srv
  local opts
  opts=$(findmnt -no OPTIONS /opt 2>/dev/null || true)
  if echo "$opts" | grep -q '\bnoexec\b'; then
    echo "/opt is mounted noexec; using /srv/piguard instead"
    APP_DIR=/srv/piguard
  fi
}

interactive_config() {
  # Only run if interactive terminal, unless INTERACTIVE=1 explicitly.
  if [[ "${INTERACTIVE:-}" != "1" ]]; then
    if [[ ! -t 0 ]]; then
      return
    fi
  fi

  echo
  echo "=== Interactive configuration ==="
  echo "You can set capture.iface, API key, and defended SSID now."

  # Helper to read current YAML values
  local cur_iface cur_apikey cur_ssid
  cur_iface=""
  cur_apikey=""
  cur_ssid=""
  if [[ -x "$VENV/bin/python" ]]; then
    cur_iface="$($VENV/bin/python - "$CFG_DIR/wids.yaml" <<'PY'
import yaml, sys
doc=yaml.safe_load(open(sys.argv[1],'r').read()) or {}
print(((doc.get('capture') or {}).get('iface') or ''))
PY
)"
    cur_apikey="$($VENV/bin/python - "$CFG_DIR/wids.yaml" <<'PY'
import yaml, sys
doc=yaml.safe_load(open(sys.argv[1],'r').read()) or {}
print(((doc.get('api') or {}).get('api_key') or ''))
PY
)"
    cur_ssid="$($VENV/bin/python - "$CFG_DIR/wids.yaml" <<'PY'
import yaml, sys
doc=yaml.safe_load(open(sys.argv[1],'r').read()) or {}
print(((doc.get('defense') or {}).get('ssid') or ''))
PY
)"
  fi

  # List wifi interfaces
  local ifs
  ifs=( $(iw dev 2>/dev/null | awk '/Interface/{print $2}') ) || true
  echo
  if [[ ${#ifs[@]} -gt 0 ]]; then
    echo "Detected Wi‑Fi interfaces:"
    local i=0
    for n in "${ifs[@]}"; do
      echo "  [$i] $n"
      i=$((i+1))
    done
  else
    echo "No interfaces found via 'iw dev'. You can set capture.iface manually."
  fi

  local choice new_iface
  echo
  read -r -p "Select interface index for capture.iface [enter to keep '${cur_iface:-unset}']: " choice || true
  if [[ -n "$choice" && "$choice" =~ ^[0-9]+$ && $choice -ge 0 && $choice -lt ${#ifs[@]} ]]; then
    new_iface="${ifs[$choice]}"
  else
    new_iface="$cur_iface"
  fi

  # Optional: create monitor clone
  if [[ -n "$new_iface" ]]; then
    read -r -p "Create monitor interface from '$new_iface' now (y/N)? " yn || true
    if [[ "$yn" =~ ^[Yy]$ ]]; then
      # Propose name
      local mon
      mon="${new_iface}mon"
      if iw dev 2>/dev/null | awk '/Interface/{print $2}' | grep -qx "$mon"; then
        mon="${new_iface}mon0"
      fi
      echo "Adding monitor vdev: $mon"
      iw dev "$new_iface" interface add "$mon" type monitor 2>/dev/null || true
      ip link set "$mon" up 2>/dev/null || true
      if iw dev 2>/dev/null | awk '/Interface/{print $2}' | grep -qx "$mon"; then
        new_iface="$mon"
        echo "Monitor interface ready: $new_iface"
      else
        echo "Failed to create monitor interface; keeping iface=$new_iface"
      fi
    fi
  fi

  # API key
  local new_key
  read -r -p "Set API key [enter to keep '${cur_apikey:-change-me}']: " new_key || true

  # Defended SSID
  local new_ssid
  read -r -p "Defended SSID (empty = not armed) [enter to keep '${cur_ssid}']: " new_ssid || true

  # Persist via Python (PyYAML in venv)
  if [[ -x "$VENV/bin/python" ]]; then
    "$VENV/bin/python" - "$CFG_DIR/wids.yaml" "$new_iface" "$new_key" "$new_ssid" <<'PY'
import sys, yaml
cfg_path=sys.argv[1]
iface=sys.argv[2]
api_key=sys.argv[3]
ssid=sys.argv[4]
doc=yaml.safe_load(open(cfg_path,'r').read()) or {}
doc.setdefault('capture', {})
if iface:
    doc['capture']['iface']=iface
doc.setdefault('api', {})
if api_key:
    doc['api']['api_key']=api_key
doc.setdefault('defense', {})
if ssid is not None and ssid != '':
    doc['defense']['ssid']=ssid
open(cfg_path,'w').write(yaml.safe_dump(doc, sort_keys=False))
print('Saved config to', cfg_path)
PY
  fi

  echo "Interactive configuration complete."
}

main() {
  need_root
  choose_prefix
  pkg_install
  create_user
  sync_code
  setup_dirs
  setup_config
  setup_venv
  set_caps
  interactive_config
  build_ui
  install_units
  sudoers_snippet
  post_notes
}

main "$@"
