#!/usr/bin/env bash
# PiGuard Unified Installer for Raspberry Pi
#
# Usage:
#   From repository: sudo ./install.sh
#   One-line remote: curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation directories
APP_DIR=/opt/piguard
CFG_DIR=/etc/piguard
DATA_DIR=/var/lib/piguard
VENV="$APP_DIR/.venv"

# Installation state variables
REPO="https://github.com/mardigiorgio/PiGuard.git"
BRANCH="main"
INSTALL_MODE="express"
LOCAL_INSTALL=0
PI5_OPTIMIZED=0

# =============================================================================
# SECTION 1: CORE FUNCTIONS
# =============================================================================

# Unified logging functions
log() { echo -e "${GREEN}[PiGuard]${NC} $*"; }
warn() { echo -e "${YELLOW}[PiGuard]${NC} $*"; }
error() { echo -e "${RED}[PiGuard ERROR]${NC} $*" >&2; }
info() { echo -e "${BLUE}[PiGuard]${NC} $*"; }

banner() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║                                                   ║"
    echo "║              🛡️  PiGuard Installer                ║"
    echo "║         Wi-Fi Intrusion Detection System         ║"
    echo "║              for Raspberry Pi                     ║"
    echo "║                                                   ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Enhanced error handling with recovery suggestions
handle_error() {
    local exit_code=$1
    local command="$2"

    error "Command failed: $command (exit code: $exit_code)"

    case $exit_code in
        100)
            error "Network error: Check your internet connection"
            ;;
        130)
            error "Installation cancelled by user"
            ;;
        *)
            error "An error occurred during installation"
            ;;
    esac

    error "Installation failed. Check the log above for details."
    error "For support, visit: https://github.com/mardigiorgio/PiGuard/issues"
    exit $exit_code
}

# Trap errors and provide helpful messages
trap 'handle_error $? "$BASH_COMMAND"' ERR

# Check if running as root
need_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This installer must be run as root. Please use 'sudo bash install.sh'"
        exit 1
    fi
}

# Pre-flight hardware and compatibility checks
preflight_checks() {
    log "Running pre-flight compatibility checks..."

    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]]; then
        warn "Detected architecture: $ARCH. This installer is optimized for Raspberry Pi (ARM64/ARMv7)."
        read -p "Continue anyway? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log "✓ Compatible ARM architecture detected: $ARCH"
    fi

    # Check for Raspberry Pi
    if [[ -f /proc/device-tree/model ]]; then
        PI_MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "Unknown")
        log "✓ Raspberry Pi detected: $PI_MODEL"

        # Specific Pi 5 optimizations
        if echo "$PI_MODEL" | grep -q "Raspberry Pi 5"; then
            log "✓ Raspberry Pi 5 detected - enabling optimized settings"
            export PI5_OPTIMIZED=1
        fi
    fi

    # Check available disk space (need at least 500MB)
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=500000  # 500MB in KB
    if [[ $AVAILABLE_SPACE -lt $REQUIRED_SPACE ]]; then
        error "Insufficient disk space. Need at least 500MB, available: $((AVAILABLE_SPACE/1024))MB"
        exit 1
    else
        log "✓ Sufficient disk space available: $((AVAILABLE_SPACE/1024))MB"
    fi

    # Check memory
    TOTAL_MEM=$(free -m | awk 'NR==2{print $2}')
    if [[ $TOTAL_MEM -lt 512 ]]; then
        warn "Low memory detected (${TOTAL_MEM}MB). PiGuard may run slower."
    else
        log "✓ Adequate memory available: ${TOTAL_MEM}MB"
    fi

    # Check for WiFi interfaces
    WIFI_INTERFACES=($(iw dev 2>/dev/null | awk '/Interface/{print $2}' || true))
    if [[ ${#WIFI_INTERFACES[@]} -eq 0 ]]; then
        error "No Wi-Fi interfaces found. PiGuard requires a Wi-Fi adapter."
        error "Please ensure your Wi-Fi adapter is connected and recognized by the system."
        exit 1
    else
        log "✓ Wi-Fi interfaces found: ${WIFI_INTERFACES[*]}"
    fi

    # Check for monitor mode support
    MONITOR_CAPABLE=0
    for iface in "${WIFI_INTERFACES[@]}"; do
        if iw dev "$iface" interface add "${iface}_test" type monitor 2>/dev/null; then
            iw dev "${iface}_test" del 2>/dev/null || true
            MONITOR_CAPABLE=1
            log "✓ Monitor mode supported on interface: $iface"
            break
        fi
    done

    if [[ $MONITOR_CAPABLE -eq 0 ]]; then
        error "No Wi-Fi interfaces support monitor mode."
        error "PiGuard requires monitor mode capability for Wi-Fi intrusion detection."
        error "Please check that your Wi-Fi adapter supports monitor mode."
        exit 1
    fi

    # Check internet connectivity
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        error "No internet connectivity detected."
        error "Internet access is required to download packages and dependencies."
        exit 1
    else
        log "✓ Internet connectivity confirmed"
    fi

    log "✓ All pre-flight checks passed!"
}

# =============================================================================
# SECTION 2: INSTALLATION LOGIC
# =============================================================================

# Install system packages
install_packages() {
    log "Installing system packages..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        python3 python3-venv python3-pip python3-setuptools python3-dev \
        git rsync iproute2 iw libcap2-bin curl ca-certificates gnupg \
        pkg-config libpcap0.8
}

# Ensure a usable Node.js/npm is available
ensure_node() {
    if command -v npm >/dev/null 2>&1; then
        return 0
    fi
    log "Installing Node.js/npm via apt..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs npm >/dev/null 2>&1; then
        if command -v npm >/dev/null 2>&1; then
            return 0
        fi
    fi
    log "Apt nodejs/npm not available; using NodeSource (Node 20.x)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs || true
    fi
}

# Create piguard user
create_user() {
    if ! id piguard >/dev/null 2>&1; then
        useradd --system --create-home --home-dir /var/lib/piguard --shell /usr/sbin/nologin piguard
        log "✓ Created piguard user"
    fi
}

# Setup installation directories
setup_directories() {
    # Choose prefix (check if /opt is noexec)
    local opts
    opts=$(findmnt -no OPTIONS /opt 2>/dev/null || true)
    if echo "$opts" | grep -q '\bnoexec\b'; then
        log "/opt is mounted noexec; using /srv/piguard instead"
        APP_DIR=/srv/piguard
        VENV="$APP_DIR/.venv"
    fi

    mkdir -p "$APP_DIR" "$CFG_DIR" "$DATA_DIR"
    chown -R piguard:piguard "$DATA_DIR"
    log "✓ Created directories: $APP_DIR, $CFG_DIR, $DATA_DIR"
}

# Sync code from source
sync_code() {
    local src
    src="${SRC_DIR:-.}"
    rsync -a --delete --exclude .git --exclude ui/node_modules --exclude ui/dist "$src/" "$APP_DIR/"
    log "✓ Synced code to $APP_DIR"
}

# Setup Python virtual environment
setup_python_env() {
    log "Setting up Python virtual environment..."

    if [[ ! -d "$VENV" ]]; then
        # Create venv with copies to avoid symlinked python
        python3 -m venv --copies "$VENV"
    fi

    # shellcheck disable=SC1090
    source "$VENV/bin/activate"
    pip install --upgrade pip wheel
    pip install -e "$APP_DIR"

    # Ensure venv python is a real binary and executable
    if [[ -L "$VENV/bin/python3" ]]; then
        log "Recreating venv with --copies to avoid symlinked python"
        deactivate || true
        rm -rf "$VENV"
        python3 -m venv --copies "$VENV"
        # shellcheck disable=SC1090
        source "$VENV/bin/activate"
        pip install --upgrade pip wheel
        pip install -e "$APP_DIR"
    fi
    chmod 755 "$VENV/bin/python3" || true

    log "✓ Python environment configured"
}

# Set capabilities for network access
set_capabilities() {
    # Default: do NOT set file capabilities to avoid EPERM with systemd's NoNewPrivileges
    if [[ "${USE_SETCAP:-0}" -eq 1 ]]; then
        local pybin
        pybin=$(readlink -f "$VENV/bin/python3" || true)
        if [[ -n "$pybin" ]]; then
            setcap cap_net_raw,cap_net_admin+eip "$pybin" || true
            log "✓ Set network capabilities on Python binary"
        fi
    fi
    # Always clear capabilities on system python to avoid surprises
    setcap -r /usr/bin/python3 2>/dev/null || true
    setcap -r /usr/bin/python 2>/dev/null || true
}

# Build UI components
build_ui() {
    if [[ "${SKIP_UI:-0}" -eq 1 ]]; then
        log "Skipping UI build (SKIP_UI=1)"
        return
    fi

    log "Building web UI..."
    ensure_node || true

    # Try root PATH first
    if command -v npm >/dev/null 2>&1; then
        log "Building UI with npm..."
        pushd "$APP_DIR/ui" >/dev/null
        npm ci
        npm run build
        popd >/dev/null
        log "✓ UI built successfully"
        return
    fi

    # If root can't find npm, try the invoking user
    if [[ -n "${SUDO_USER:-}" ]]; then
        if su -l "$SUDO_USER" -c "bash -lc 'command -v npm'" >/dev/null 2>&1; then
            log "Building UI with $SUDO_USER's npm..."
            chown -R "$SUDO_USER":"$SUDO_USER" "$APP_DIR/ui" || true
            su -l "$SUDO_USER" -c "bash -lc 'cd \"$APP_DIR/ui\" && npm ci && npm run build'"
            chown -R root:root "$APP_DIR/ui" || true
            log "✓ UI built successfully"
            return
        fi
    fi

    warn "npm not found; skipping UI build. The API will still run without static UI."
}

# Install systemd services
install_services() {
    log "Installing systemd services..."
    install -m 0644 "$APP_DIR/deploy/systemd/piguard-api.service" /etc/systemd/system/
    install -m 0644 "$APP_DIR/deploy/systemd/piguard-sensor.service" /etc/systemd/system/
    install -m 0644 "$APP_DIR/deploy/systemd/piguard-sniffer.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now piguard-api piguard-sensor piguard-sniffer || true
    log "✓ Services installed and enabled"
}

# Setup sudoers for network commands
setup_sudoers() {
    cat >/etc/sudoers.d/piguard-iw-ip <<EOF
Cmnd_Alias PIGUARD_NET = /sbin/ip, /usr/sbin/ip, /usr/sbin/iw, /sbin/iw
piguard ALL=(root) NOPASSWD: PIGUARD_NET
Defaults!PIGUARD_NET !requiretty
EOF
    chmod 0440 /etc/sudoers.d/piguard-iw-ip
    log "✓ Sudoers configuration installed"
}

# Setup initial configuration
setup_config() {
    if [[ ! -f "$CFG_DIR/wids.yaml" ]]; then
        cp "$APP_DIR/configs/wids.example.yaml" "$CFG_DIR/wids.yaml"
        # Point DB to /var/lib/piguard/db.sqlite
        sed -i -E "s|^\s*path:\s*.*$|  path: $DATA_DIR/db.sqlite|" "$CFG_DIR/wids.yaml"
        log "✓ Configuration file created: $CFG_DIR/wids.yaml"
    fi
}

# =============================================================================
# SECTION 3: INTERACTIVE CONFIGURATION
# =============================================================================

# Enhanced Wi-Fi interface detection and setup
setup_wifi_interface() {
    local current_iface="$1"

    if [[ "${INTERACTIVE:-0}" -eq 0 && "${GUIDED_MODE:-0}" -eq 0 ]]; then
        return 0
    fi

    echo
    echo "═══ Wi-Fi Interface Setup ═══"

    if [[ "${GUIDED_MODE:-}" == "1" ]]; then
        info "PiGuard needs a Wi-Fi interface in monitor mode to detect intrusions."
        info "Monitor mode allows capturing all Wi-Fi packets, not just your own traffic."
        echo
    fi

    # Discover all Wi-Fi interfaces with enhanced info
    local interfaces=()
    local interface_info=()

    while IFS= read -r line; do
        if [[ $line =~ Interface[[:space:]]+([^[:space:]]+) ]]; then
            local iface="${BASH_REMATCH[1]}"
            interfaces+=("$iface")

            # Get additional info about interface
            local driver=$(ethtool -i "$iface" 2>/dev/null | grep driver | awk '{print $2}' || echo "unknown")
            local state=$(ip link show "$iface" 2>/dev/null | grep -o "state [A-Z]*" | awk '{print $2}' || echo "unknown")
            interface_info+=("$iface ($driver, $state)")
        fi
    done < <(iw dev 2>/dev/null || true)

    if [[ ${#interfaces[@]} -eq 0 ]]; then
        error "No Wi-Fi interfaces found!"
        return 1
    fi

    echo "Detected Wi-Fi interfaces:"
    for i in "${!interfaces[@]}"; do
        local iface="${interfaces[$i]}"
        local info="${interface_info[$i]}"

        # Check if interface supports monitor mode
        if iw dev "$iface" interface add "${iface}_test" type monitor 2>/dev/null; then
            iw dev "${iface}_test" del 2>/dev/null || true
            echo "  [$i] $info ✓ (monitor mode supported)"
        else
            echo "  [$i] $info ✗ (monitor mode not supported)"
        fi
    done
    echo

    # Smart default selection
    local recommended_iface=""
    for iface in "${interfaces[@]}"; do
        if iw dev "$iface" interface add "${iface}_test" type monitor 2>/dev/null; then
            iw dev "${iface}_test" del 2>/dev/null || true
            recommended_iface="$iface"
            break
        fi
    done

    local choice
    if [[ -n "$recommended_iface" ]]; then
        info "Recommended interface: $recommended_iface (supports monitor mode)"
        read -p "Select interface by number, or press Enter for recommended [$recommended_iface]: " choice

        if [[ -z "$choice" ]]; then
            final_iface="$recommended_iface"
        elif [[ "$choice" =~ ^[0-9]+$ && $choice -ge 0 && $choice -lt ${#interfaces[@]} ]]; then
            final_iface="${interfaces[$choice]}"
        else
            warn "Invalid selection, using recommended: $recommended_iface"
            final_iface="$recommended_iface"
        fi
    else
        error "No interfaces support monitor mode. PiGuard requires monitor mode capability."
        return 1
    fi

    # Offer to create monitor interface
    local monitor_name="${final_iface}mon"
    if ip link show "$monitor_name" >/dev/null 2>&1; then
        monitor_name="${final_iface}mon0"
    fi

    echo
    log "Selected interface: $final_iface"

    if [[ "${GUIDED_MODE:-}" == "1" ]]; then
        info "Creating a dedicated monitor interface is safer than using your main Wi-Fi interface."
        info "This allows you to maintain internet connectivity while monitoring."
    fi

    read -p "Create dedicated monitor interface '$monitor_name'? [Y/n]: " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log "Using existing interface: $final_iface"
    else
        log "Creating monitor interface: $monitor_name"
        if iw dev "$final_iface" interface add "$monitor_name" type monitor 2>/dev/null; then
            if ip link set "$monitor_name" up 2>/dev/null; then
                log "✓ Monitor interface '$monitor_name' created and activated"
                final_iface="$monitor_name"
            else
                warn "Monitor interface created but failed to activate. Using: $final_iface"
            fi
        else
            warn "Failed to create monitor interface. Using: $final_iface"
        fi
    fi
}

# Setup API security key
setup_api_key() {
    local current_key="$1"

    if [[ "${INTERACTIVE:-0}" -eq 0 && "${GUIDED_MODE:-0}" -eq 0 ]]; then
        # Generate secure key for non-interactive mode
        if command -v openssl >/dev/null 2>&1; then
            final_apikey=$(openssl rand -hex 32)
        elif command -v python3 >/dev/null 2>&1; then
            final_apikey=$(python3 -c "import secrets; print(secrets.token_hex(32))")
        else
            final_apikey=$(head -c 32 /dev/urandom | base64 | tr -d '=+/' | cut -c1-32)
        fi
        return 0
    fi

    echo
    echo "═══ API Security Setup ═══"

    if [[ "${GUIDED_MODE:-}" == "1" ]]; then
        info "PiGuard includes a web interface for monitoring and configuration."
        info "An API key protects access to your security data and controls."
        echo
    fi

    if [[ -n "$current_key" && "$current_key" != "change-me" ]]; then
        info "Current API key: ${current_key:0:8}... (hidden for security)"
        read -p "Generate new secure API key? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            final_apikey="$current_key"
            return
        fi
    fi

    # Generate secure API key
    if command -v openssl >/dev/null 2>&1; then
        final_apikey=$(openssl rand -hex 32)
        log "✓ Generated secure API key using OpenSSL"
    elif command -v python3 >/dev/null 2>&1; then
        final_apikey=$(python3 -c "import secrets; print(secrets.token_hex(32))")
        log "✓ Generated secure API key using Python"
    else
        final_apikey=$(head -c 32 /dev/urandom | base64 | tr -d '=+/' | cut -c1-32)
        log "✓ Generated API key using system entropy"
    fi

    info "New API key generated (save this for web interface access):"
    echo "   ${final_apikey}"
    echo

    if [[ "${GUIDED_MODE:-}" == "1" ]]; then
        info "You'll need this key to access the PiGuard web interface."
        info "Store it securely - you can change it later if needed."
        echo
        read -p "Press Enter to continue..." -r
    fi
}

# Setup network defense configuration
setup_defense_config() {
    local current_ssid="$1"

    if [[ "${INTERACTIVE:-0}" -eq 0 && "${GUIDED_MODE:-0}" -eq 0 ]]; then
        final_ssid=""
        return 0
    fi

    echo
    echo "═══ Network Defense Configuration ═══"

    if [[ "${GUIDED_MODE:-}" == "1" ]]; then
        info "PiGuard can actively defend a specific Wi-Fi network (SSID)."
        info "When defending a network, it will:"
        info "• Alert on deauthentication attacks against that network"
        info "• Detect rogue access points impersonating your network"
        info "• Monitor for suspicious power variance patterns"
        echo
        info "You can also run in monitoring-only mode to observe all networks."
        echo
    fi

    # Scan for nearby networks
    log "Scanning for nearby Wi-Fi networks..."
    local nearby_ssids=()

    # Use timeout to prevent hanging
    if timeout 10 iw dev "${final_iface:-wlan0}" scan 2>/dev/null | grep -o 'SSID: .*' | cut -d' ' -f2- | sort -u > /tmp/piguard_ssids 2>/dev/null; then
        while IFS= read -r ssid; do
            if [[ -n "$ssid" && "$ssid" != "--" ]]; then
                nearby_ssids+=("$ssid")
            fi
        done < /tmp/piguard_ssids
        rm -f /tmp/piguard_ssids
    fi

    if [[ ${#nearby_ssids[@]} -gt 0 ]]; then
        echo "Nearby Wi-Fi networks detected:"
        for i in "${!nearby_ssids[@]}"; do
            if [[ $i -lt 10 ]]; then
                echo "  [$i] ${nearby_ssids[$i]}"
            fi
        done
        if [[ ${#nearby_ssids[@]} -gt 10 ]]; then
            echo "  ... and $((${#nearby_ssids[@]} - 10)) more"
        fi
        echo
    fi

    local selection
    if [[ -n "$current_ssid" ]]; then
        info "Currently defending: $current_ssid"
        read -p "Enter new SSID to defend, select by number, or press Enter to keep current: " selection

        if [[ -z "$selection" ]]; then
            final_ssid="$current_ssid"
            return
        fi
    else
        read -p "Enter SSID to defend (or number from list above), or leave empty for monitoring-only: " selection
    fi

    if [[ -z "$selection" ]]; then
        final_ssid=""
        info "Configured for monitoring-only mode (no active defense)"
    elif [[ "$selection" =~ ^[0-9]+$ && $selection -ge 0 && $selection -lt ${#nearby_ssids[@]} ]]; then
        final_ssid="${nearby_ssids[$selection]}"
        log "✓ Selected network to defend: $final_ssid"
    else
        final_ssid="$selection"
        log "✓ Will defend network: $final_ssid"
    fi
}

# Save configuration to YAML file
save_configuration() {
    local cfg_path="$1"
    local iface="$2"
    local api_key="$3"
    local ssid="$4"

    if [[ -x "$VENV/bin/python" ]]; then
        "$VENV/bin/python" - "$cfg_path" "$iface" "$api_key" "$ssid" <<'PY'
import sys, yaml
try:
    cfg_path = sys.argv[1]
    iface = sys.argv[2]
    api_key = sys.argv[3]
    ssid = sys.argv[4]

    # Load existing config
    try:
        with open(cfg_path, 'r') as f:
            doc = yaml.safe_load(f.read()) or {}
    except:
        doc = {}

    # Update configuration
    doc.setdefault('capture', {})
    if iface:
        doc['capture']['iface'] = iface

    doc.setdefault('api', {})
    if api_key:
        doc['api']['api_key'] = api_key

    doc.setdefault('defense', {})
    if ssid is not None:
        if ssid == '':
            doc['defense']['ssid'] = ''
        else:
            doc['defense']['ssid'] = ssid

    # Save configuration
    with open(cfg_path, 'w') as f:
        f.write(yaml.safe_dump(doc, sort_keys=False, default_flow_style=False))

    print(f'Configuration saved to {cfg_path}')

except Exception as e:
    print(f'Error saving configuration: {e}', file=sys.stderr)
    sys.exit(1)
PY
    else
        error "Python environment not available for configuration saving"
        return 1
    fi
}

# Get current configuration values
get_current_config() {
    local cfg_path="$CFG_DIR/wids.yaml"

    if [[ ! -f "$cfg_path" || ! -x "$VENV/bin/python" ]]; then
        cur_iface=""
        cur_apikey=""
        cur_ssid=""
        return
    fi

    cur_iface="$($VENV/bin/python - "$cfg_path" <<'PY'
import yaml, sys
try:
    doc=yaml.safe_load(open(sys.argv[1],'r').read()) or {}
    print(((doc.get('capture') or {}).get('iface') or ''))
except: pass
PY
)"
    cur_apikey="$($VENV/bin/python - "$cfg_path" <<'PY'
import yaml, sys
try:
    doc=yaml.safe_load(open(sys.argv[1],'r').read()) or {}
    print(((doc.get('api') or {}).get('api_key') or ''))
except: pass
PY
)"
    cur_ssid="$($VENV/bin/python - "$cfg_path" <<'PY'
import yaml, sys
try:
    doc=yaml.safe_load(open(sys.argv[1],'r').read()) or {}
    print(((doc.get('defense') or {}).get('ssid') or ''))
except: pass
PY
)"
}

# Run interactive configuration
run_interactive_config() {
    # Only run if interactive terminal or explicitly enabled
    if [[ "${INTERACTIVE:-}" != "1" && "${GUIDED_MODE:-}" != "1" ]]; then
        if [[ ! -t 0 ]]; then
            return
        fi
    fi

    echo
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║                 PiGuard Setup                     ║"
    echo "║            Interactive Configuration              ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo

    if [[ "${GUIDED_MODE:-}" == "1" ]]; then
        info "Welcome to PiGuard guided setup!"
        info "This will walk you through configuring your Wi-Fi intrusion detection system."
        info "You can change these settings later through the web interface."
        echo
        read -p "Press Enter to continue..." -r
    fi

    # Get current configuration values
    get_current_config

    # Configure components
    setup_wifi_interface "$cur_iface"
    setup_api_key "$cur_apikey"
    setup_defense_config "$cur_ssid"

    # Save configuration
    save_configuration "$CFG_DIR/wids.yaml" "${final_iface:-}" "${final_apikey:-}" "${final_ssid:-}"

    echo
    log "✓ Interactive configuration completed successfully!"

    if [[ "${GUIDED_MODE:-}" == "1" ]]; then
        echo
        info "Configuration summary:"
        info "• Wi-Fi Interface: ${final_iface:-Not set}"
        info "• API Access: Protected with secure key"
        info "• Defended Network: ${final_ssid:-Not set (monitoring only)}"
        echo
        local pi_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
        info "You can access the web interface at http://$pi_ip:8080"
        info "Use the API key when prompted for authentication."
    fi
}

# =============================================================================
# SECTION 4: POST-INSTALLATION AND FINALIZATION
# =============================================================================

# Post-installation validation and health checks
post_install_validation() {
    log "Running post-installation validation..."

    # Check if services are installed
    local services=("piguard-api" "piguard-sensor" "piguard-sniffer")
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "$service.service"; then
            log "✓ Service installed: $service"
        else
            error "✗ Service missing: $service"
            return 1
        fi
    done

    # Check if services are running
    sleep 3  # Give services time to start
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log "✓ Service running: $service"
        else
            warn "⚠ Service not running: $service (this may be normal if not configured yet)"
        fi
    done

    # Check configuration file
    if [[ -f /etc/piguard/wids.yaml ]]; then
        log "✓ Configuration file created: /etc/piguard/wids.yaml"
    else
        error "✗ Configuration file missing"
        return 1
    fi

    # Test web UI accessibility (if running)
    if systemctl is-active --quiet piguard-api; then
        sleep 2
        if curl -s --max-time 5 http://localhost:8080/api/health >/dev/null 2>&1; then
            log "✓ Web API accessible at http://localhost:8080"
        else
            warn "⚠ Web API not yet accessible (may need configuration)"
        fi
    fi

    # Check database creation
    if [[ -f /var/lib/piguard/db.sqlite ]]; then
        log "✓ Database file created"
    else
        warn "⚠ Database file not found (will be created on first use)"
    fi

    log "✓ Post-installation validation completed"
}

# Show completion message
show_completion_message() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║                                                   ║"
    echo "║            🎉 Installation Complete! 🎉           ║"
    echo "║                                                   ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    log "PiGuard has been successfully installed!"
    echo
    info "Next steps:"
    local pi_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    info "1. Open your web browser and go to: http://$pi_ip:8080"
    info "2. Configure your Wi-Fi interface in the Device tab"
    info "3. Set up your defended network in the Defense tab"
    info "4. Monitor alerts in the Alerts tab"
    echo
    info "Configuration file: /etc/piguard/wids.yaml"
    info "Log files: Use 'journalctl -u piguard-api' to view service logs"
    echo
    info "For troubleshooting and documentation:"
    info "https://github.com/mardigiorgio/PiGuard"
    echo
    log "PiGuard is now protecting your network! 🛡️"
}

# Show usage information
show_usage() {
    echo "PiGuard Unified Installer"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Installation Modes:"
    echo "  --express     Fully automated installation (default)"
    echo "  --guided      Interactive installation with explanations"
    echo "  --advanced    Full control over installation options"
    echo "  --headless    Silent installation for remote deployment"
    echo
    echo "Options:"
    echo "  --repo URL    Clone from custom repository URL"
    echo "  --branch NAME Use specific branch (default: main)"
    echo "  --help, -h    Show this help message"
    echo
    echo "Examples:"
    echo "  $0                    # Express installation"
    echo "  $0 --guided          # Guided interactive installation"
    echo "  $0 --headless        # Silent installation"
}

# =============================================================================
# MAIN INSTALLATION FUNCTION
# =============================================================================

install_piguard() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --express)
                INSTALL_MODE="express"
                shift
                ;;
            --guided)
                INSTALL_MODE="guided"
                shift
                ;;
            --advanced)
                INSTALL_MODE="advanced"
                shift
                ;;
            --headless)
                INSTALL_MODE="headless"
                shift
                ;;
            --repo)
                REPO="$2"
                shift 2
                ;;
            --branch)
                BRANCH="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    log "Starting PiGuard installation in $INSTALL_MODE mode..."

    # Set installation environment based on mode
    case $INSTALL_MODE in
        express)
            log "🚀 Express installation - using optimal defaults"
            export INTERACTIVE=1
            ;;
        guided)
            log "📋 Guided installation - interactive setup with explanations"
            export INTERACTIVE=1
            export GUIDED_MODE=1
            ;;
        advanced)
            log "⚙️ Advanced installation - full control"
            export INTERACTIVE=1
            export ADVANCED_MODE=1
            ;;
        headless)
            log "🤖 Headless installation - no prompts"
            export INTERACTIVE=0
            ;;
    esac

    # Check if we're running from a local repository
    if [[ -f "pyproject.toml" && -f "src/wids/__init__.py" ]]; then
        log "Running from local repository checkout"
        WORK_DIR="$(pwd)"
        LOCAL_INSTALL=1
    else
        # Create temporary directory and clone
        TEMP_DIR=$(mktemp -d)
        trap "rm -rf $TEMP_DIR" EXIT

        log "Downloading PiGuard from $REPO..."
        git clone --depth 1 --branch "$BRANCH" "$REPO" "$TEMP_DIR" || {
            error "Failed to clone repository"
            exit 100
        }

        cd "$TEMP_DIR"
        WORK_DIR="$TEMP_DIR"
        LOCAL_INSTALL=0
    fi

    # Pi 5 specific optimizations
    if [[ "${PI5_OPTIMIZED:-0}" -eq 1 ]]; then
        export PI5_OPTIMIZATIONS=1
        log "Applying Raspberry Pi 5 optimizations"
    fi

    # Set source directory for installation
    export SRC_DIR="$WORK_DIR"

    # Run installation steps
    install_packages
    create_user
    setup_directories
    sync_code
    setup_config
    setup_python_env
    set_capabilities
    build_ui
    install_services
    setup_sudoers

    # Run interactive configuration
    run_interactive_config

    # Post-install validation
    post_install_validation

    # Show completion message
    show_completion_message
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    banner

    # Show installation mode selection if no arguments
    if [[ $# -eq 0 ]]; then
        echo "Select installation mode:"
        echo "1) Express - Quick setup with optimal defaults (recommended)"
        echo "2) Guided - Step-by-step with explanations"
        echo "3) Advanced - Full control over options"
        echo "4) Headless - Silent installation"
        echo
        read -p "Choose installation mode [1-4]: " -n 1 -r
        echo

        case $REPLY in
            1|"") set -- --express ;;
            2) set -- --guided ;;
            3) set -- --advanced ;;
            4) set -- --headless ;;
            *)
                error "Invalid selection"
                exit 1
                ;;
        esac
    fi

    need_root
    preflight_checks
    install_piguard "$@"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi