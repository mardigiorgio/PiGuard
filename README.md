# PiGuard — Wi‑Fi Intrusion Detection for Raspberry Pi

PiGuard is a lightweight Wi‑Fi intrusion detection system (WIDS) designed for Raspberry Pi devices. It detects deauthentication attacks and rogue access points in real time, provides a clean web interface, and exposes an API for automation.

- **Backend**: FastAPI + SQLite (SQLModel)
- **Sniffer**: Scapy + libpcap filters, channel hopping
- **Sensor**: Stateful detection loop (deauth bursts, rogue AP/RSN mismatch, power variance anomalies)
- **UI**: Svelte + Vite
- **Installer**: One‑command setup with interactive config and systemd services

## Quick Installation

**One-line installation (recommended):**

```bash
curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash
```

**From local repository:**

```bash
git clone https://github.com/mardigiorgio/PiGuard.git
cd PiGuard
sudo ./install.sh
```

**Installation modes:**
- `--express` - Fully automated with optimal defaults (default)
- `--guided` - Step-by-step with explanations
- `--advanced` - Full control over all options
- `--headless` - Silent installation for remote deployment

**For detailed installation guide:** [INSTALL.md](INSTALL.md)
**Quick start guide:** [GETTING_STARTED.md](GETTING_STARTED.md)
**Hardware compatibility:** [HARDWARE.md](HARDWARE.md)

## Features

- **Real‑time deauth detection** with tunable thresholds
- **Rogue AP detection** (SSID allowlists, channel/band constraints, RSN mismatch)
- **Channel hopping** with live config reload; optional fixed channel lock
- **Built‑in web UI** (device controls, defense config, logs, settings)
- **Service management from UI** (restart sniffer/sensor)
- **SSE stream for alerts**; REST API for logs/events/config
- **Hardened installer** ensures Python/Node/npm, builds UI, installs systemd units
- **Optimized ingest** BPF capture filters, bulk DB inserts, SQLite WAL

## Requirements

- **Hardware**: Raspberry Pi 3/4/5 or similar ARM64 device
- **OS**: Raspberry Pi OS or Ubuntu (arm64)
- **Wi‑Fi**: Adapter and driver that support monitor mode (nl80211)
- **Network**: Internet connection for installation
- **Storage**: 16GB+ SD card (32GB+ recommended)

## Detection Capabilities

| Attack Type | Description | Alerting |
|-------------|-------------|----------|
| **Deauth Attacks** | Attempts to disconnect devices from Wi-Fi | Real-time alerts |
| **Rogue Access Points** | Fake networks impersonating your SSID | Instant detection |
| **Power Anomalies** | Unusual signal strength variations | Smart analysis |
| **Network Reconnaissance** | Scanning and probing attempts | Activity logging |

## Web Interface

After installation, access the web interface at:
```
http://YOUR_PI_IP:8080
```

**Interface tabs:**
- **Overview** - System status and activity
- **Alerts** - Security alerts and intrusions
- **Defense** - Configure protected networks
- **Device** - Wi-Fi interface management
- **Settings** - Detection thresholds and tuning
- **Logs** - System and event logs

## Services

PiGuard runs as three systemd services:

```bash
# Service status
sudo systemctl status piguard-api piguard-sniffer piguard-sensor

# Service management
sudo systemctl restart piguard-sniffer
sudo systemctl restart piguard-sensor
sudo systemctl restart piguard-api

# View logs
journalctl -u piguard-api -f
journalctl -u piguard-sniffer -f
journalctl -u piguard-sensor -f
```

**Service roles:**
- `piguard-api` — FastAPI server (serves UI and API)
- `piguard-sniffer` — Capture loop (requires monitor mode)
- `piguard-sensor` — Detection loop (reads DB and emits alerts)

## Configuration

Primary config: `/etc/piguard/wids.yaml`

**Key sections:**
- `database.path`: SQLite file path (e.g., `/var/lib/piguard/db.sqlite`)
- `api.bind_host` / `api.bind_port` / `api.api_key`: API server and key
- `capture.iface`: Monitor‑mode interface (e.g., `wlan0mon`)
- `defense.ssid`: The single SSID to protect (arming the sensor)
- `thresholds.deauth`: Detection sensitivity settings
- `alerts`: Discord webhook and/or email SMTP settings

Most settings can be configured through the web interface.

## API Quick Reference

- **Health/overview**: `GET /api/health`, `GET /api/overview`
- **Alerts**: `GET /api/alerts`, `POST /api/alerts/test`, `GET /api/stream` (SSE)
- **Logs/events**: `GET /api/logs`, `GET /api/events`
- **Settings**: `GET/POST /api/settings/deauth`
- **Defense**: `GET/POST /api/defense`
- **Capture**: `GET/POST /api/capture`
- **Device/iface**: `GET /api/ifaces`, `POST /api/iface/monitor`
- **Admin**: `POST /api/admin/clear`, `POST /api/admin/restart`

All protected endpoints require `X-Api-Key` header.

## Performance Tuning

**Make deauth detection more sensitive:**
- Increase `window_sec`, lower `global_limit` and `per_src_limit`, reduce `cooldown_sec`

**Capture more packets per channel:**
- Increase `hop.dwell_ms`, reduce hopped channel set (e.g., `[1,6,11]`), or switch to `mode=lock`

**Optimize for your Pi model:**
- Pi 5: All features enabled, maximum sensitivity
- Pi 4: Excellent performance, reduce channels for very busy networks
- Pi 3: Basic monitoring, focus on key channels (1,6,11)

## Troubleshooting

**Common issues:**

| Problem | Solution |
|---------|----------|
| `HTTP 401 Unauthorized` | Check API key in `/etc/piguard/wids.yaml` |
| `sniffer: interface DOWN` | Create monitor interface in Device tab |
| UI not accessible | Check `systemctl status piguard-api` |
| No packets captured | Verify monitor mode: `iw dev` |

**Get help:**
- [Installation Guide](INSTALL.md)
- [Hardware Compatibility](HARDWARE.md)
- [GitHub Issues](https://github.com/mardigiorgio/PiGuard/issues)
- [GitHub Discussions](https://github.com/mardigiorgio/PiGuard/discussions)

## Development

**Local development server:**
```bash
# API + sensor (+ sniffer via sudo) using configs/wids.yaml
python -m wids dev --config configs/wids.yaml --ui
```

**CLI helpers:**
```bash
python -m wids iface-up --dev wlan0mon
python -m wids sniffer --config configs/wids.yaml
python -m wids sensor  --config configs/wids.yaml
```

## Security Considerations

- Capture requires raw socket privileges; services run with minimal required permissions
- API access protected by cryptographically secure keys
- Local-only database storage (no external data transmission)
- Prefer deploying on dedicated Pi or isolated VLAN
- Regular security updates recommended

## Roadmap

- **Native sniffer** in Rust or Go for lower CPU usage
- **External time‑series DB** support for long‑term storage
- **Expanded Settings UI** for rogue thresholds and notifications
- **Package distribution** as .deb and Docker image
- **Multi-node deployment** for large network coverage
- **SIEM integration** plugins for enterprise environments

## License

[License information to be added]

## Contributing

We welcome contributions! Please see our contributing guidelines and feel free to:

- Report bugs via [GitHub Issues](https://github.com/mardigiorgio/PiGuard/issues)
- Suggest features via [GitHub Discussions](https://github.com/mardigiorgio/PiGuard/discussions)
- Submit pull requests for improvements
- Help improve documentation

---

**Protect your network with PiGuard**