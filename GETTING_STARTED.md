# PiGuard Quick Start Guide

This guide provides essential steps to deploy PiGuard Wi-Fi Intrusion Detection System and begin monitoring your network within minutes.

## Installation

Execute the automated installer:

```bash
curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash
```

## Installation Process Overview

The installer performs the following operations automatically:

1. **Hardware Compatibility Check** - Verifies Raspberry Pi model and Wi-Fi adapter support
2. **Dependency Installation** - Downloads Python, Node.js, and required system packages
3. **System Configuration** - Establishes secure API credentials and monitoring interface
4. **Web Interface Deployment** - Builds and configures the management dashboard
5. **Service Initialization** - Starts monitoring and detection services

## Initial Access

### Locate Your Device
```bash
hostname -I
```

### Access Web Interface
Navigate to: `http://YOUR_PI_IP:8080`

### Authentication
Use the API key displayed during installation or retrieve it from:
```bash
sudo cat /etc/piguard/wids.yaml | grep api_key
```

## Basic Configuration

### Device Configuration
1. **Navigate to Device tab**
2. **Verify Wi-Fi interface detection**
3. **Create monitor interface if prompted**
4. **Enable channel hopping for comprehensive monitoring**

### Defense Configuration
1. **Navigate to Defense tab**
2. **Enter your Wi-Fi network name (SSID)** to enable protection
3. **Alternative**: Leave blank for monitoring-only mode

### System Verification
1. **Navigate to Overview tab**
2. **Confirm packet capture is active**
3. **Verify database connectivity**
4. **Check service health status**

### Alert Monitoring
1. **Navigate to Alerts tab**
2. **Monitor for deauthentication attacks**
3. **Review rogue access point detections**
4. **Analyze suspicious network activity**

## Detection Capabilities

PiGuard monitors and alerts on the following threats:

- **Deauthentication Attacks** - Malicious attempts to disconnect devices from Wi-Fi networks
- **Rogue Access Points** - Unauthorized networks impersonating legitimate SSIDs
- **Power Anomalies** - Unusual signal strength variations indicating potential threats
- **Network Reconnaissance** - Scanning and probing activities targeting your network

## Support Resources

- **Complete Documentation**: [INSTALL.md](INSTALL.md)
- **Hardware Compatibility**: [HARDWARE.md](HARDWARE.md)
- **Troubleshooting**: Check service logs with `journalctl -u piguard-api -f`
- **Community Support**: [GitHub Issues](https://github.com/mardigiorgio/PiGuard/issues)

---

**Your network is now under PiGuard protection**