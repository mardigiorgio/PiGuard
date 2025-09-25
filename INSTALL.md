# PiGuard Installation Guide

This guide will help you install PiGuard on your Raspberry Pi to monitor your home Wi-Fi network for attacks and suspicious activity.

## Quick Installation

For most people, this one command is all you need:

```bash
curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash
```

This will check that your Pi will work with PiGuard, install everything needed, and start monitoring your network automatically.

---

## Installation Options

If you want more control over the installation process, you can use these options:

### Express Mode (Default)
Just install everything automatically with good defaults:
```bash
curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash --express
```

### Guided Mode
Walk through the installation step-by-step with explanations:
```bash
curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash --guided
```

### Advanced Mode
Full control over all settings (for experienced users):
```bash
curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash --advanced
```

### Headless Mode
Install without any prompts (good for remote Pis):
```bash
curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash --headless
```

---

## What You Need

### Hardware
- **Raspberry Pi 3, 4, or 5** (Pi 4 or 5 work best, but Pi 3 is fine for home use)
- **Wi-Fi adapter that supports monitor mode** (the built-in Wi-Fi on most Pi models works great)
- **SD card**: 16GB minimum, but 32GB+ is better if you want to keep logs longer
- **Decent power supply**: Use the official Pi power adapter if possible

### Software
- **Raspberry Pi OS** (the standard OS that comes with Pi, 64-bit version preferred)
- **Internet connection** during installation to download packages
- **Ability to run sudo** (you'll need to run the installer with sudo)

### Which Pi Models Work
| Pi Model | Works? | How Well? | Good For |
|----------|--------|-----------|----------|
| Raspberry Pi 5 | ✓ Yes | Excellent | Best performance, handles everything |
| Raspberry Pi 4 | ✓ Yes | Very Good | Great for most home setups |
| Raspberry Pi 3B+ | ✓ Yes | Good | Perfect for typical home networks |
| Raspberry Pi 3B | ✓ Yes | Decent | Works fine, might be a bit slower |
| Raspberry Pi Zero 2 W | ⚠ Maybe | Limited | Basic monitoring only |

---

## Installation Steps

### Step 1: Prepare Your Pi

1. **Install Raspberry Pi OS** using the [Raspberry Pi Imager](https://rpi.org/imager)
2. **Enable SSH** if you want to install remotely (optional):
   ```bash
   sudo systemctl enable ssh
   sudo systemctl start ssh
   ```
3. **Update your Pi** (good idea but not required):
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

### Step 2: Run the Installer

Choose one of the installation modes from above and run it. The installer will:

1. **Check your hardware** - Make sure your Pi and Wi-Fi will work
2. **Download software** - Get Python, Node.js, and other needed parts
3. **Set everything up** - Create accounts, folders, and configure services
4. **Build the web interface** - Compile the dashboard you'll use
5. **Start services** - Launch the monitoring processes
6. **Configure Wi-Fi monitoring** - Set up your Wi-Fi interface for packet capture

### Step 3: Interactive Configuration

During installation, you will configure:

#### Network Interface Selection
- Automatic detection of Wi-Fi interfaces
- Monitor mode capability verification
- Option to create dedicated monitoring interface
- Interface state management

#### Security Configuration
- Automatic generation of cryptographically secure API keys
- Service permission configuration
- Network access controls

#### Network Defense Setup
- Nearby network discovery and selection
- Defended network configuration
- Monitoring scope definition

---

## Post-Installation Setup

### Access Web Interface

1. **Determine your Pi's IP address:**
   ```bash
   hostname -I
   ```

2. **Navigate to the web interface:**
   ```
   http://YOUR_PI_IP:8080
   ```

3. **Authenticate using the API key** displayed during installation or found in:
   ```bash
   sudo cat /etc/piguard/wids.yaml | grep api_key
   ```

### Configure System

Use the web interface to complete setup:

- **Overview Tab** - Monitor system status and recent activity
- **Alerts Tab** - Configure alert thresholds and notifications
- **Defense Tab** - Define protected networks and policies
- **Device Tab** - Manage Wi-Fi interfaces and channel settings
- **Settings Tab** - Adjust detection parameters and system behavior
- **Logs Tab** - Review system events and diagnostic information

### Verify Operation

1. **Check service status:**
   ```bash
   sudo systemctl status piguard-api piguard-sensor piguard-sniffer
   ```

2. **Monitor packet capture:**
   ```bash
   journalctl -u piguard-sniffer -f
   ```

3. **Verify web interface accessibility and functionality**

---

## Manual Installation

For custom deployments or development environments:

```bash
# Clone repository
git clone https://github.com/mardigiorgio/PiGuard.git
cd PiGuard

# Execute installer from source
sudo ./install.sh --guided
```

---

## Service Management

PiGuard operates as three systemd services:

```bash
# Service status monitoring
sudo systemctl status piguard-api
sudo systemctl status piguard-sensor
sudo systemctl status piguard-sniffer

# Service lifecycle management
sudo systemctl start piguard-*
sudo systemctl stop piguard-*
sudo systemctl restart piguard-*

# Log monitoring
journalctl -u piguard-api -f
journalctl -u piguard-sensor -f
journalctl -u piguard-sniffer -f
```

**Service Descriptions:**
- **piguard-api** - Web interface and REST API server
- **piguard-sensor** - Intrusion detection and alerting engine
- **piguard-sniffer** - Wi-Fi packet capture and processing

---

## Troubleshooting

### Common Installation Issues

#### No Wi-Fi Interfaces Detected
**Symptoms:** Installation fails with "No Wi-Fi interfaces found"
**Resolution:**
```bash
# Verify interface detection
lsusb | grep -i wireless
iwconfig
iw dev

# Install additional firmware if needed
sudo apt update
sudo apt install firmware-realtek firmware-atheros
sudo reboot
```

#### Monitor Mode Not Supported
**Symptoms:** Wi-Fi adapter cannot enter monitor mode
**Resolution:**
- Verify adapter compatibility using [HARDWARE.md](HARDWARE.md)
- Consider using a different Wi-Fi adapter
- Check driver support and kernel modules

#### Web Interface Inaccessible
**Symptoms:** Cannot connect to port 8080
**Resolution:**
```bash
# Verify service status
sudo systemctl status piguard-api

# Check port binding
sudo netstat -tulpn | grep 8080

# Restart API service
sudo systemctl restart piguard-api

# Review firewall configuration
sudo ufw status
```

#### Service Startup Failures
**Symptoms:** Services fail to start or repeatedly restart
**Resolution:**
```bash
# Review detailed service logs
journalctl -u piguard-api -n 50
journalctl -u piguard-sensor -n 50
journalctl -u piguard-sniffer -n 50

# Verify configuration file
sudo cat /etc/piguard/wids.yaml

# Check interface availability
sudo iw dev
```

#### Performance Issues
**Symptoms:** High CPU usage or slow response
**Resolution:**
- Reduce channel hopping frequency in Device settings
- Limit monitoring to essential channels (1, 6, 11 for 2.4GHz)
- Consider upgrading to Raspberry Pi 4 or 5
- Use Class 10+ SD cards for improved I/O

### Getting Support

If issues persist after troubleshooting:

1. **Review system logs** using `journalctl` commands
2. **Search existing issues** at [GitHub Issues](https://github.com/mardigiorgio/PiGuard/issues)
3. **Create a detailed issue report** including:
   - Raspberry Pi model and OS version
   - Installation method and mode used
   - Complete error logs and symptoms
   - Steps taken to reproduce the problem

---

## Security Best Practices

### Installation Security
- **Verify installer integrity** before execution
- **Use dedicated Raspberry Pi** for PiGuard when possible
- **Keep system packages updated** regularly
- **Use strong passwords** for system accounts

### Network Security
- **Change default API keys** after installation
- **Deploy on isolated network** segments when feasible
- **Monitor access logs** for unauthorized attempts
- **Configure firewall rules** appropriately

### Operational Security
- **Regular backup** of configuration and data
- **Monitor system resources** and performance
- **Review alert configurations** periodically
- **Update PiGuard** when new versions are available

---

## Performance Optimization

### Raspberry Pi 5 Optimizations
The installer automatically applies performance optimizations for Pi 5:
- Enhanced memory configuration
- Optimized Python virtual environment
- Improved I/O scheduling
- Database performance tuning

### General Performance Tips
1. **Use high-quality SD cards** (Class 10, A2 rating preferred)
2. **Configure GPU memory split:**
   ```bash
   sudo raspi-config
   # Advanced Options → Memory Split → 16
   ```
3. **Disable unnecessary services:**
   ```bash
   sudo systemctl disable bluetooth
   sudo systemctl disable cups
   ```
4. **Use wired network connection** for Pi management when possible

---

## Next Steps

After successful installation:

1. **Review the [User Guide](README.md)** for advanced configuration options
2. **Configure detection thresholds** based on your network environment
3. **Set up alerting mechanisms** (Discord, email) as needed
4. **Monitor system performance** and adjust settings accordingly
5. **Consider multiple deployment points** for comprehensive coverage

For additional information, consult:
- **Hardware compatibility:** [HARDWARE.md](HARDWARE.md)
- **Quick start guide:** [GETTING_STARTED.md](GETTING_STARTED.md)
- **Community support:** [GitHub Discussions](https://github.com/mardigiorgio/PiGuard/discussions)