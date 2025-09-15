# PiGuard — Wi‑Fi Intrusion Detection for Raspberry Pi

PiGuard is a lightweight Wi‑Fi intrusion detection system (WIDS) designed for minimal hardware like the Raspberry Pi. It detects deauthentication attacks and rogue access points in real time, provides a web UI, and exposes a clean API for automation.

- Backend: FastAPI + SQLite (SQLModel)
- Sniffer: Scapy + libpcap filters, channel hopping
- Sensor: Stateful detection loop (deauth bursts, rogue AP/RSN mismatch, power variance anomalies)
- UI: Svelte + Vite
- Installer: One‑command setup with interactive config and systemd services

## Features

- Real‑time deauth detection with tunable thresholds
- Rogue AP checks (SSID allowlists, channel/band constraints, RSN mismatch)
- Channel hopper with live config reload; optional fixed channel lock
- Built‑in web UI (device controls, defense config, logs, settings)
- Service management from UI (restart sniffer/sensor)
- SSE stream for alerts; REST API for logs/events/config
- Hardened installer: ensures Python/Node/npm, builds UI, installs systemd units
- Optimized ingest: BPF capture filters, bulk DB inserts, SQLite WAL


## Requirements

- Raspberry Pi 3/4/5 or similar ARM64 device
- OS: Raspberry Pi OS or Ubuntu (arm64)
- Wi‑Fi adapter and driver that support monitor mode (nl80211)
- Root privileges for capture (the sniffer service runs with the required capabilities)


## Quick Start

- Fresh install (clone + install via wrapper):

```
sudo ./install.sh --repo https://github.com/mardigiorgio/PiGuard.git --branch main --interactive
```

- From a local checkout:

```
# Inside the cloned repo
env | grep -i piGuard || true
sudo ./install.sh --source "$PWD" --interactive
```

- Non‑interactive and skipping UI build (headless):

```
sudo ./install.sh --source "$PWD" --no-interactive --skip-ui
```

What the installer does:
- Installs runtime deps (Python, iw/iproute2/libpcap), ensures Node/npm
- Copies code to `/opt/piguard`, sets up venv and installs Python package (editable)
- Builds the UI (unless `--skip-ui`)
- Installs and enables systemd units: `piguard-api`, `piguard-sensor`, `piguard-sniffer`
- Creates config at `/etc/piguard/wids.yaml` (if missing) and offers an interactive setup to choose interface, API key, and defended SSID

After install:
- Browse to `http://<pi-ip>:8080/`
- Use the Settings tab to tune deauth thresholds
- Use the Device tab to create a monitor interface and adjust hopping
- Use the Defense tab to arm a specific SSID


## Services

- `piguard-api` — FastAPI server (serves UI and API)
- `piguard-sniffer` — Capture loop (requires monitor mode)
- `piguard-sensor` — Detection loop (reads DB and emits alerts)

Common operations:

```
sudo systemctl status piguard-api piguard-sniffer piguard-sensor
sudo systemctl restart piguard-sniffer
```

The UI Logs tab includes “Restart Sniffer” and “Restart Sensor” buttons.


## Configuration

The primary config lives at `/etc/piguard/wids.yaml`. A sample is in `configs/wids.example.yaml`.

Key sections:

- `database.path`: SQLite file path (e.g., `/var/lib/piguard/db.sqlite`)
- `api.bind_host` / `api.bind_port` / `api.api_key`: API server and key
- `thresholds.deauth`:
  - `window_sec`: sliding time window for counting deauth frames
  - `per_src_limit`: per‑MAC counter threshold (advisory)
  - `global_limit`: global threshold that actually triggers the alert
  - `cooldown_sec`: minimum interval between identical alerts
- `thresholds.rogue`:
  - `pwr_window`, `pwr_var_threshold`, `pwr_cooldown_sec`: power variance anomaly tuning
- `sniffer`: optional sniffer tuning (e.g., `parse_rsn`, `log_stats`)
- `capture`: capture interface and channel hopping
  - `iface`: monitor‑mode interface (e.g., `wlan0mon`)
  - `hop.enabled`: enable/disable hopping
  - `hop.mode`: `lock` | `list` | `all`
  - `hop.lock_channel`: channel when mode=`lock`
  - `hop.list_channels`: explicit sweep list when mode=`list`
  - `hop.dwell_ms`: ms to spend per hop
  - `hop.channels_24`/`channels_5`/`channels_6`: band channel lists when mode=`all`
- `defense`:
  - `ssid`: the single SSID to protect (arming the sensor)
  - `allowed_bssids` / `allowed_channels` / `allowed_bands`: allowlists
- `alerts`: optional Discord webhook and/or email SMTP settings

Most of these can be edited from the UI tabs (Defense, Device, Settings). The sensor and hopper observe config updates at runtime.


## Architecture

- Sniffer (`src/wids/capture/live.py`)
  - Scapy capture with libpcap (`conf.use_pcap=True`) and BPF filter to limit to management frames (beacon/deauth/disassoc)
  - Channel hopper thread reads the YAML for live updates; supports lock/list/all modes
  - Batches `Event` inserts and uses bulk operations for throughput
  - Optional RSN parsing from beacons (AKMs/ciphers)

- Sensor (`src/wids/sensor/main.py`)
  - Periodically queries recent events to detect deauth floods (SQL `GROUP BY` for efficiency)
  - Rogue checks scoped to defended SSID and optional allowlists
  - Power variance anomaly detection on defended BSSIDs
  - Emits `Alert` rows and optional notifications (Discord/email)

- API (`src/wids/service/api.py`)
  - FastAPI app serving the UI and JSON endpoints
  - Logs, events, alerts, SSE stream, device controls (monitor mode, channel), capture config, defense settings
  - Settings endpoints for deauth thresholds; admin restart endpoints for sniffer/sensor

- Data model (`src/wids/db.py`)
  - `Event`, `Alert`, `Log` tables (SQLModel)
  - SQLite with WAL and pragmatic `PRAGMA` tuning for write‑heavy workloads

- UI (`/ui`)
  - Svelte + Vite + Tailwind; routes for Overview, Alerts, Defense, Device, Settings, Logs
  - Runtime API base computed from browser location; API key can be provided via URL query `?apikey=...` or stored in localStorage


## API Quick Reference

- Health/overview: `GET /api/health`, `GET /api/overview`
- Alerts: `GET /api/alerts`, `POST /api/alerts/test`, `GET /api/stream` (SSE)
- Logs/events: `GET /api/logs`, `GET /api/events`
- Settings (deauth): `GET /api/settings/deauth`, `POST/PUT /api/settings/deauth`
- Defense: `GET/POST /api/defense`
- Capture: `GET/POST /api/capture`
- Device/iface: `GET /api/ifaces`, `GET /api/iface?dev=wlan0mon`, `POST /api/iface/monitor`, `POST /api/iface/monitor_clone`, `POST /api/iface/channel`
- Admin: `POST /api/admin/clear`, `POST /api/admin/restart`

All protected endpoints require `X-Api-Key` header.


## Tuning & Tips

- Make deauth more sensitive: increase `window_sec`, lower `global_limit` and `per_src_limit`, reduce `cooldown_sec`.
- Capture more packets per channel: increase `hop.dwell_ms`, reduce hopped channel set (e.g., `[1,6,11]`), or switch to `mode=lock` on a busy channel.
- Prefer creating a monitor vdev (Device → “Create Monitor”) to avoid disrupting connectivity.
- Keep UI and API in sync by redeploying from your working tree:

```
sudo ./install.sh --source "$PWD" --no-interactive
sudo systemctl restart piguard-api
```


## Troubleshooting

- `HTTP 401 Unauthorized`: wrong or missing `X-Api-Key`; check `/etc/piguard/wids.yaml`.
- `HTTP 405 Method Not Allowed` on settings: API service is old; redeploy and restart.
- `sniffer: interface DOWN`: bring the interface up or create a monitor interface in the UI.
- UI missing: UI may not have built. Re‑run installer without `--skip-ui` or ensure npm/Node are present.
- Node not found: installer attempts apt and NodeSource (Node 20.x). Build logs appear in the installer output.


## Development

- Local dev server (API + sensor + optional sniffer + UI dev server):

```
# API + sensor (+ sniffer via sudo) using configs/wids.yaml
python -m wids dev --config configs/wids.yaml --ui
```

- CLI helpers:

```
python -m wids iface-up --dev wlan0mon
python -m wids sniffer --config configs/wids.yaml
python -m wids sensor  --config configs/wids.yaml
```


## Security Considerations

- Capture requires raw socket privileges; services are installed as systemd units and may run as root for simplicity on constrained devices.
- Prefer deploying PiGuard on a dedicated device or VLAN.


## Roadmap (suggested)

- Native sniffer in Rust or Go for lower CPU and higher throughput on minimal hardware
- Optional external time‑series DB for long‑term storage
- Expanded Settings UI for rogue thresholds and notifications
- Packaging as a .deb and Docker image


---

### Short description (for GitHub repo)

Raspberry Pi Wi‑Fi IDS (deauth/rogue AP) with FastAPI backend, Svelte UI, and a one‑command installer. Real‑time detection, channel hopping, and a clean web console for device control, logs, and settings.
