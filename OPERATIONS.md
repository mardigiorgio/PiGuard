# PiGuard Operations Guide

This guide covers day-to-day management, troubleshooting, and updating of your PiGuard installation.

## Managing PiGuard Services

PiGuard runs as three background services:

```bash
# Check if everything is running
sudo systemctl status piguard-api piguard-sniffer piguard-sensor

# Restart if needed
sudo systemctl restart piguard-sniffer
sudo systemctl restart piguard-sensor
sudo systemctl restart piguard-api

# View logs
journalctl -u piguard-api -f
journalctl -u piguard-sniffer -f
journalctl -u piguard-sensor -f
```

**What each service does:**
- `piguard-api` — Web interface and API
- `piguard-sniffer` — Captures Wi-Fi packets
- `piguard-sensor` — Analyzes packets for attacks

## Updating PiGuard

To update an existing installation to the latest version:

```bash
# Update with automatic backup
sudo ./install.sh --update

# Or via one-line command
curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash -s -- --update
```

The update process will:
- Automatically back up your configuration and database
- Update to the latest code
- Rebuild dependencies and web interface
- Restart services
- Preserve all your settings

Backups are stored in `/var/lib/piguard/backups/`

## Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| Can't access web interface | Check `sudo systemctl status piguard-api` |
| Login fails | Verify username/password in `/etc/piguard/wids.yaml` |
| "HTTP 401 Unauthorized" | Your session may have expired, login again |
| No packets being captured | Make sure Wi-Fi interface supports monitor mode |
| Services keep crashing | Check logs with `journalctl -u piguard-sniffer -f` |

### Checking Logs

View real-time logs for each service:

```bash
# API logs
journalctl -u piguard-api -f

# Sniffer logs
journalctl -u piguard-sniffer -f

# Sensor logs
journalctl -u piguard-sensor -f

# View all PiGuard logs
journalctl -u "piguard-*" -f
```

### Restarting Services

If a service is misbehaving, restart it:

```bash
# Restart all services
sudo systemctl restart piguard-api piguard-sniffer piguard-sensor

# Restart individual services
sudo systemctl restart piguard-api
sudo systemctl restart piguard-sniffer
sudo systemctl restart piguard-sensor
```

### Checking Service Status

```bash
# Check all services
sudo systemctl status piguard-api piguard-sniffer piguard-sensor

# Check individual service
sudo systemctl status piguard-api
```

## For Developers

### Running Locally

```bash
# Start API + sensor (+ sniffer via sudo) using configs/wids.yaml
python -m wids dev --config configs/wids.yaml --ui
```

### CLI Tools

```bash
python -m wids iface-up --dev wlan0mon
python -m wids sniffer --config configs/wids.yaml
python -m wids sensor  --config configs/wids.yaml
```

## Getting Help

**Need help?**
- [Installation Guide](INSTALL.md)
- [Configuration Guide](CONFIGURATION.md)
- [Hardware Guide](HARDWARE.md)
- [GitHub Issues](https://github.com/mardigiorgio/PiGuard/issues)
