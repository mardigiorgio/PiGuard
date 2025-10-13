# PiGuard — Wi‑Fi Intrusion Detection for Raspberry Pi

## Overview
PiGuard is a Wi‑Fi intrusion detection system (WIDS) designed for home networks and Raspberry Pi enthusiasts. It detects deauthentication attacks and rogue access points in real time, provides a clean web interface, and is perfect for learning about network security.

## Features
- **Real‑time deauth detection** — Catch Wi-Fi jamming attacks on your home network
- **Rogue AP detection** — Spot fake networks trying to impersonate your Wi-Fi
- **Channel hopping** — Monitor all Wi-Fi channels or focus on specific ones
- **Built‑in web UI** — Easy-to-use interface for monitoring and configuration
- **Alert system** — Get notified via Discord or email when attacks are detected
- **Educational** — Great for learning about Wi-Fi security and network monitoring

## Technical Stack
- **Backend**: FastAPI + SQLite (SQLModel)
- **Sniffer**: Scapy + libpcap filters, channel hopping
- **Sensor**: Stateful detection loop (deauth bursts, rogue AP/RSN mismatch, power variance anomalies)
- **UI**: Svelte + Vite
- **Installer**: One‑command setup with interactive config and systemd services

## Quick Start

**One-line installation:**

```bash
curl -sSL https://raw.githubusercontent.com/mardigiorgio/PiGuard/main/install.sh | sudo bash
```

After installation, visit `http://YOUR_PI_IP:8080` to access the web interface.

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

## Documentation

- [Installation Guide](INSTALL.md) — Detailed installation instructions, modes, and hardware setup
- [Getting Started](GETTING_STARTED.md) — Quick start guide for new users
- [Configuration Guide](CONFIGURATION.md) — Configure detection sensitivity, alerts, and monitoring
- [Operations Guide](OPERATIONS.md) — Managing services, updating, and troubleshooting
- [Hardware Guide](HARDWARE.md) — Hardware compatibility and recommendations

## Contributing

This is a learning project and contributions are welcome! Feel free to:

- Report bugs or suggest features via [GitHub Issues](https://github.com/mardigiorgio/PiGuard/issues)
- Ask questions in [GitHub Discussions](https://github.com/mardigiorgio/PiGuard/discussions)
- Submit pull requests for improvements
- Share your setup and experiences

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

**Protect your home network with PiGuard**
