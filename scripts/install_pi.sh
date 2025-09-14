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
    git rsync iproute2 iw libcap2-bin \
    pkg-config libpcap0.8
}

create_user() {
  if ! id piguard >/dev/null 2>&1; then
    useradd --system --create-home --home-dir /var/lib/piguard --shell /usr/sbin/nologin piguard
  fi
}

sync_code() {
  mkdir -p "$APP_DIR"
  rsync -a --delete --exclude .git --exclude ui/node_modules --exclude ui/dist ./ "$APP_DIR/"
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
    python3 -m venv "$VENV"
  fi
  # shellcheck disable=SC1090
  source "$VENV/bin/activate"
  pip install --upgrade pip wheel
  # Install dependencies (editable install keeps source path and serves UI from repo)
  pip install -e "$APP_DIR"
  PY="$VENV/bin/python"
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
}

build_ui() {
  if [[ "${SKIP_UI:-0}" -eq 1 ]]; then
    echo "Skipping UI build (SKIP_UI=1)"
    return
  fi
  if command -v npm >/dev/null 2>&1; then
    echo "Building UI..."
    pushd "$APP_DIR/ui" >/dev/null
    npm ci
    npm run build
    popd >/dev/null
  else
    echo "npm not found; skipping UI build. The API will still run without static UI."
  fi
}

install_units() {
  install -m 0644 "$APP_DIR/deploy/systemd/piguard-api.service" /etc/systemd/system/
  install -m 0644 "$APP_DIR/deploy/systemd/piguard-sensor.service" /etc/systemd/system/
  install -m 0644 "$APP_DIR/deploy/systemd/piguard-sniffer.service" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable piguard-api piguard-sensor piguard-sniffer
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

main() {
  need_root
  pkg_install
  create_user
  sync_code
  setup_dirs
  setup_config
  setup_venv
  set_caps
  build_ui
  install_units
  sudoers_snippet
  post_notes
}

main "$@"
