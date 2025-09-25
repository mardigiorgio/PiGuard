#!/usr/bin/env bash
# PiGuard Installer for Raspberry Pi
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

# Logging functions
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

# Pre-flight hardware and compatibility checks
preflight_checks() {
    log "Running pre-flight compatibility checks..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This installer must be run as root. Please use 'sudo bash quick-install.sh'"
        exit 1
    fi

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

# Main installation function
install_piguard() {
    local REPO="https://github.com/mardigiorgio/PiGuard.git"
    local BRANCH="main"
    local INSTALL_MODE="express"

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

    # Check if we're running from a local repository
    if [[ -f "scripts/install_pi.sh" && -f "pyproject.toml" ]]; then
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

    # Pi 5 specific optimizations
    if [[ "${PI5_OPTIMIZED:-0}" -eq 1 ]]; then
        export PI5_OPTIMIZATIONS=1
        log "Applying Raspberry Pi 5 optimizations"
    fi

    # Run the main installer
    log "Running main installation process..."
    export SRC_DIR="$WORK_DIR"

    if [[ ! -x "scripts/install_pi.sh" ]]; then
        error "Installation script not found: scripts/install_pi.sh"
        exit 1
    fi

    bash "scripts/install_pi.sh" || {
        error "Main installation failed"
        exit 1
    }

    # Post-install validation
    post_install_validation

    # Show completion message
    show_completion_message
}

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
    info "1. Open your web browser and go to: http://$(hostname -I | awk '{print $1}'):8080"
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

show_usage() {
    echo "PiGuard Quick Installer"
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

# Main execution
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

    preflight_checks
    install_piguard "$@"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi