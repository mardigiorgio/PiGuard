# PiGuard — Wi‑Fi Intrusion Detection for Raspberry Pi

PiGuard is a Wi‑Fi intrusion detection system (WIDS) designed for home networks and Raspberry Pi enthusiasts. It detects deauthentication attacks and rogue access points in real time, provides a clean web interface, and is perfect for learning about network security.

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
- `--headless` - Silent installation for remote setup

**For detailed installation guide:** [INSTALL.md](INSTALL.md)
**Quick start guide:** [GETTING_STARTED.md](GETTING_STARTED.md)
**Hardware compatibility:** [HARDWARE.md](HARDWARE.md)

## What PiGuard Does

- **Real‑time deauth detection** - Catch Wi-Fi jamming attacks on your home network
- **Rogue AP detection** - Spot fake networks trying to impersonate your Wi-Fi
- **Channel hopping** - Monitor all Wi-Fi channels or focus on specific ones
- **Built‑in web UI** - Easy-to-use interface for monitoring and configuration
- **Alert system** - Get notified via Discord or email when attacks are detected
- **Educational** - Great for learning about Wi-Fi security and network monitoring

## Requirements

- **Hardware**: Raspberry Pi 3/4/5 or similar ARM device
- **OS**: Raspberry Pi OS or Ubuntu (arm64)
- **Wi‑Fi**: Adapter that supports monitor mode (most Pi built-in Wi-Fi works)
- **Network**: Internet connection for installation
- **Storage**: 16GB+ SD card (32GB+ recommended for longer logs)

## What It Detects

| Attack Type | Description | What You'll See |
|-------------|-------------|------------------|
| **Deauth Attacks** | Someone trying to kick devices off your Wi-Fi | Real-time alerts in web UI |
| **Rogue Access Points** | Fake networks pretending to be your Wi-Fi | Instant notifications |
| **Power Anomalies** | Unusual signal strength patterns | Smart analysis and logging |
| **Network Scanning** | People probing your network | Activity logs |

## Web Interface

After installation, visit `http://YOUR_PI_IP:8080` to access the web interface:

**Main tabs:**
- **Overview** - See what's happening on your network right now
- **Alerts** - Review security alerts and potential attacks
- **Defense** - Configure which network to protect
- **Device** - Manage Wi-Fi interfaces and channel settings
- **Settings** - Adjust detection sensitivity
- **Logs** - View detailed system logs

## Managing PiGuard

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

## Configuration

Main config file: `/etc/piguard/wids.yaml`

**Key settings you might want to change:**
- `capture.iface`: Which Wi-Fi interface to monitor (e.g., `wlan0mon`)
- `defense.ssid`: Your Wi-Fi network name to protect
- `thresholds.deauth`: How sensitive the detection should be
- `alerts`: Discord webhook or email settings for notifications

Most settings can be changed through the web interface - no need to edit files manually.

## Common Tasks

**Make detection more sensitive:**
- Increase `window_sec`, lower `global_limit` and `per_src_limit`, reduce `cooldown_sec`

**Monitor specific channels only:**
- Increase `hop.dwell_ms`, set channels to `[1,6,11]`, or switch to `mode=lock`

**Optimize for your Pi:**
- Pi 5/4: Can handle all features
- Pi 3: Works great for home networks, might want to limit channels
- Pi Zero 2: Basic monitoring only

## Troubleshooting

**Common issues:**

| Problem | Solution |
|---------|----------|
| Can't access web interface | Check `sudo systemctl status piguard-api` |
| "HTTP 401 Unauthorized" | Check API key in `/etc/piguard/wids.yaml` |
| No packets being captured | Make sure Wi-Fi interface supports monitor mode |
| Services keep crashing | Check logs with `journalctl -u piguard-sniffer -f` |

**Need help?**
- [Installation Guide](INSTALL.md)
- [Hardware Guide](HARDWARE.md)
- [GitHub Issues](https://github.com/mardigiorgio/PiGuard/issues)

## For Developers

**Run locally:**
```bash
# Start API + sensor (+ sniffer via sudo) using configs/wids.yaml
python -m wids dev --config configs/wids.yaml --ui
```

**CLI tools:**
```bash
python -m wids iface-up --dev wlan0mon
python -m wids sniffer --config configs/wids.yaml
python -m wids sensor  --config configs/wids.yaml
```

## Security Notes

- PiGuard only monitors and alerts - it doesn't block attacks
- All data stays on your Raspberry Pi (no cloud services)
- API access is protected with a secure key
- Consider using a dedicated Pi for monitoring if you're paranoid
- Keep your Pi updated with security patches

## What's Planned

- Better mobile interface
- More alert types
- Improved performance on older Pi models
- Package for easier installation
- Docker container option

## License

MIT License

Copyright (c) 2025 PiGuard

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Contributing

This is a learning project and contributions are welcome! Feel free to:

- Report bugs or suggest features via [GitHub Issues](https://github.com/mardigiorgio/PiGuard/issues)
- Ask questions in [GitHub Discussions](https://github.com/mardigiorgio/PiGuard/discussions)
- Submit pull requests for improvements
- Share your setup and experiences

---

**Protect your home network with PiGuard**
