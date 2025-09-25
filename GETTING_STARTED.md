# PiGuard Quick Start Guide

Get your home Wi-Fi monitoring up and running in just a few minutes!

## Installation

Run this one command on your Raspberry Pi:

```bash
curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash
```

## What Happens During Installation?

The installer will automatically:

1. **Hardware Check** - Make sure your Pi and Wi-Fi adapter will work with PiGuard
2. **Download Software** - Get Python, Node.js, and other needed components
3. **Setup Security** - Create a secure API key and configure monitoring
4. **Build Web Interface** - Set up the dashboard you'll use to monitor your network
5. **Start Services** - Launch the background processes that watch for attacks

## First Login

1. **Find your Pi's IP address:**
   ```bash
   hostname -I
   ```

2. **Open your web browser to:** `http://YOUR_PI_IP:8080`

3. **Enter the API key** that was shown during installation. You can also find it with:
   ```bash
   sudo cat /etc/piguard/wids.yaml | grep api_key
   ```

## Quick Setup

### Step 1: Configure Device (Device Tab)
- Check that your Wi-Fi interface is detected
- Create a monitor interface if prompted (this is safer for your main Wi-Fi connection)
- Turn on channel hopping to monitor all Wi-Fi channels

### Step 2: Set Your Network to Protect (Defense Tab)
- Enter your home Wi-Fi network name (SSID) to focus protection on it
- Or leave blank to just monitor everything without focusing on one network

### Step 3: Make Sure It's Working (Overview Tab)
- Check that packet capture is active
- Make sure the database is receiving events
- Confirm all services are running properly

### Step 4: Watch for Attacks (Alerts Tab)
- Look for deauthentication attacks (someone trying to kick devices off your Wi-Fi)
- Check for rogue access points (fake networks pretending to be yours)
- Review any suspicious activity PiGuard finds

## What PiGuard Watches For

- **Deauth Attacks** - Someone trying to disconnect devices from your Wi-Fi
- **Rogue Access Points** - Fake networks with names similar to yours trying to trick people
- **Power Anomalies** - Unusual signal strength patterns that might indicate attacks
- **Network Scanning** - People probing your network to find weaknesses

## Need Help?

- **Full Guide**: [INSTALL.md](INSTALL.md) - Complete installation and setup instructions
- **Hardware Info**: [HARDWARE.md](HARDWARE.md) - Which Raspberry Pi and Wi-Fi adapters work best
- **Troubleshooting**: Check logs with `journalctl -u piguard-api -f` if something's not working
- **Get Support**: [GitHub Issues](https://github.com/mardigiorgio/PiGuard/issues) - Ask questions or report problems

---

**Your home network is now being monitored by PiGuard**