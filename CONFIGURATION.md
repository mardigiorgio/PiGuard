# PiGuard Configuration Guide

This guide covers how to configure and tune PiGuard for your specific needs.

## Configuration File

Main config file: `/etc/piguard/wids.yaml`

Most settings can be changed through the web interface - no need to edit files manually.

## Key Settings

### Web Interface Authentication

```yaml
api:
  username: admin              # Web UI login username
  password: your_password      # Web UI login password
  api_key: your_api_key       # API authentication key (for backward compatibility)
```

### Capture Settings

```yaml
capture:
  iface: wlan0mon             # Which Wi-Fi interface to monitor (e.g., wlan0mon)
```

### Network Defense

```yaml
defense:
  ssid: YourNetworkName       # Your Wi-Fi network name to protect
```

### Detection Thresholds

```yaml
thresholds:
  deauth:
    window_sec: 30            # Time window for detecting attacks
    global_limit: 50          # Maximum deauth frames globally
    per_src_limit: 10         # Maximum deauth frames per source
    cooldown_sec: 60          # Cooldown period after alert
```

### Alert Configuration

```yaml
alerts:
  discord:
    enabled: true
    webhook_url: https://discord.com/api/webhooks/...

  email:
    enabled: false
    smtp_server: smtp.gmail.com
    smtp_port: 587
    from_address: alerts@example.com
    to_address: you@example.com
    username: your_email
    password: your_password
```

## Common Configuration Tasks

### Make Detection More Sensitive

To catch attacks faster and with lower thresholds:

```yaml
thresholds:
  deauth:
    window_sec: 60            # Increase time window
    global_limit: 30          # Lower global limit
    per_src_limit: 5          # Lower per-source limit
    cooldown_sec: 30          # Reduce cooldown
```

### Monitor Specific Channels Only

To focus on specific Wi-Fi channels (faster detection, less resource usage):

```yaml
capture:
  hop:
    mode: hop                  # or 'lock' to stay on one channel
    channels: [1, 6, 11]      # Only monitor these channels
    dwell_ms: 500             # Spend more time per channel
```

To lock to a single channel:

```yaml
capture:
  hop:
    mode: lock
    channels: [6]             # Stay on channel 6
```

### Optimize for Your Raspberry Pi

**Pi 5/4**: Can handle all features with default settings

**Pi 3**: Works great for home networks. Consider limiting channels:
```yaml
capture:
  hop:
    channels: [1, 6, 11]      # Only monitor common channels
    dwell_ms: 300             # Default dwell time
```

**Pi Zero 2**: Basic monitoring only. Limit channels and reduce sensitivity:
```yaml
capture:
  hop:
    channels: [6]             # Single channel
    dwell_ms: 500

thresholds:
  deauth:
    global_limit: 100         # Less sensitive
```

## Web Interface Configuration

After installation, visit `http://YOUR_PI_IP:8080` to access the web interface.

**Login:**
- Default username: `admin`
- Password: Set during installation or found in `/etc/piguard/wids.yaml`
- Sessions last 24 hours

**Main tabs:**
- **Overview** - See what's happening on your network right now
- **Alerts** - Review security alerts and potential attacks
- **Defense** - Configure which network to protect
- **Device** - Manage Wi-Fi interfaces and channel settings
- **Settings** - Adjust detection sensitivity
- **Logs** - View detailed system logs

## Security Notes

- PiGuard only monitors and alerts - it doesn't block attacks
- All data stays on your Raspberry Pi (no cloud services)
- API access is protected with session-based authentication
- Consider using a dedicated Pi for monitoring if you're paranoid
- Keep your Pi updated with security patches

## Advanced Configuration

For advanced users who want full control over the configuration, edit `/etc/piguard/wids.yaml` directly and restart the services:

```bash
sudo nano /etc/piguard/wids.yaml
sudo systemctl restart piguard-api piguard-sniffer piguard-sensor
```

**Note:** Changes made through the web interface will update this file automatically.
