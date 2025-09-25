#!/usr/bin/env bash
# Enhanced interactive setup for PiGuard
# This extends the existing installer with improved user experience

# Colors for better UX
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[Setup]${NC} $*"; }
info() { echo -e "${BLUE}[Info]${NC} $*"; }
warn() { echo -e "${YELLOW}[Warning]${NC} $*"; }
error() { echo -e "${RED}[Error]${NC} $*"; }

# Enhanced interactive configuration with auto-detection and explanations
enhanced_interactive_config() {
    local CFG_DIR="${1:-/etc/piguard}"
    local VENV="${2:-/opt/piguard/.venv}"

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
    local cur_iface cur_apikey cur_ssid
    cur_iface=""
    cur_apikey=""
    cur_ssid=""

    if [[ -x "$VENV/bin/python" ]]; then
        cur_iface="$($VENV/bin/python - "$CFG_DIR/wids.yaml" <<'PY'
import yaml, sys
try:
    doc=yaml.safe_load(open(sys.argv[1],'r').read()) or {}
    print(((doc.get('capture') or {}).get('iface') or ''))
except: pass
PY
)"
        cur_apikey="$($VENV/bin/python - "$CFG_DIR/wids.yaml" <<'PY'
import yaml, sys
try:
    doc=yaml.safe_load(open(sys.argv[1],'r').read()) or {}
    print(((doc.get('api') or {}).get('api_key') or ''))
except: pass
PY
)"
        cur_ssid="$($VENV/bin/python - "$CFG_DIR/wids.yaml" <<'PY'
import yaml, sys
try:
    doc=yaml.safe_load(open(sys.argv[1],'r').read()) or {}
    print(((doc.get('defense') or {}).get('ssid') or ''))
except: pass
PY
)"
    fi

    # Step 1: Wi-Fi Interface Selection with smart detection
    setup_wifi_interface "$cur_iface"

    # Step 2: API Key generation/setup
    setup_api_key "$cur_apikey"

    # Step 3: Network Defense Configuration
    setup_defense_config "$cur_ssid"

    # Step 4: Additional Security Settings (if guided mode)
    if [[ "${GUIDED_MODE:-}" == "1" ]]; then
        setup_advanced_options
    fi

    # Save all configuration
    save_configuration "$CFG_DIR/wids.yaml" "$final_iface" "$final_apikey" "$final_ssid"

    echo
    log "✓ Interactive configuration completed successfully!"

    if [[ "${GUIDED_MODE:-}" == "1" ]]; then
        echo
        info "Configuration summary:"
        info "• Wi-Fi Interface: $final_iface"
        info "• API Access: Protected with secure key"
        info "• Defended Network: ${final_ssid:-Not set (monitoring only)}"
        echo
        info "You can access the web interface at http://$(get_pi_ip):8080"
        info "Use the API key when prompted for authentication."
    fi
}

setup_wifi_interface() {
    local current_iface="$1"

    echo "═══ Step 1: Wi-Fi Interface Setup ═══"

    if [[ "${GUIDED_MODE:-}" == "1" ]]; then
        info "PiGuard needs a Wi-Fi interface in monitor mode to detect intrusions."
        info "Monitor mode allows capturing all Wi-Fi packets, not just your own traffic."
        echo
    fi

    # Discover all Wi-Fi interfaces
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
        error "Please ensure your Wi-Fi adapter is properly connected and recognized."
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

setup_api_key() {
    local current_key="$1"

    echo
    echo "═══ Step 2: API Security Setup ═══"

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
        # Fallback to urandom
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

setup_defense_config() {
    local current_ssid="$1"

    echo
    echo "═══ Step 3: Network Defense Configuration ═══"

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
    if timeout 10 iw dev "${final_iface}" scan 2>/dev/null | grep -o 'SSID: .*' | cut -d' ' -f2- | sort -u > /tmp/piguard_ssids 2>/dev/null; then
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
            if [[ $i -lt 10 ]]; then  # Show only first 10
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

setup_advanced_options() {
    echo
    echo "═══ Step 4: Advanced Configuration (Optional) ═══"

    info "Would you like to configure advanced detection settings?"
    read -p "Configure advanced settings? [y/N]: " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Advanced settings can be configured through the web interface at:"
        info "http://$(get_pi_ip):8080/settings"
        echo
        info "Advanced options include:"
        info "• Detection sensitivity thresholds"
        info "• Channel hopping configuration"
        info "• Alert notification settings (Discord, email)"
        info "• Allowed device lists for your network"
    fi
}

save_configuration() {
    local cfg_path="$1"
    local iface="$2"
    local api_key="$3"
    local ssid="$4"

    if [[ -x "/opt/piguard/.venv/bin/python" ]]; then
        "/opt/piguard/.venv/bin/python" - "$cfg_path" "$iface" "$api_key" "$ssid" <<'PY'
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

get_pi_ip() {
    # Get the primary IP address
    hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost"
}

# Function to be called from main installer
run_enhanced_setup() {
    local cfg_dir="${1:-/etc/piguard}"
    local venv="${2:-/opt/piguard/.venv}"

    enhanced_interactive_config "$cfg_dir" "$venv"
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    enhanced_interactive_config "$@"
fi