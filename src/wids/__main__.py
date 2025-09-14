import os
import sys
import signal
import subprocess
import pathlib
import shutil
import threading
import click


def _py():
    return sys.executable


@click.group(help="PiGuard helper CLI: api | sensor | sniffer | replay | dev")
def cli():
    pass


@cli.command()
@click.option("--config", required=True, help="Path to wids.yaml")
def api(config: str):
    """Run the API server (FastAPI/Uvicorn)."""
    from wids.service.api import main as api_main
    api_main(config)


@cli.command()
@click.option("--config", required=True, help="Path to wids.yaml")
def sensor(config: str):
    """Run the sensor/detectors loop."""
    from wids.common import load_config
    from wids.sensor.main import loop
    cfg = load_config(config)
    loop(cfg, config)


@cli.command()
@click.option("--config", required=True, help="Path to wids.yaml")
@click.option("--dwell", type=float, default=0.1, show_default=True, help="Channel dwell time in seconds (airodump-like)")
@click.option("--rssi-window", type=int, default=20, show_default=True, help="RSSI window size for variance")
@click.option("--var-threshold", type=float, default=150.0, show_default=True, help="Variance threshold for PWR flip alert")
@click.option("--anomaly-log", type=str, default=None, help="Path to write anomaly events (optional)")
def sniffer(config: str, dwell: float, rssi_window: int, var_threshold: float, anomaly_log: str | None):
    """Run the live sniffer (requires root)."""
    from wids.common import load_config
    from wids.capture.live import run_sniffer

    if os.geteuid() != 0:
        click.secho("[sniffer] must run as root (sudo)", fg="red")
        sys.exit(1)

    cfg = load_config(config)
    iface = (cfg.get("capture", {}) or {}).get("iface")
    if not iface:
        click.secho("[sniffer] capture.iface not set in config", fg="red")
        sys.exit(1)

    # Preflight: check iface exists and is up
    try:
        res = subprocess.run(["ip", "link", "show", iface], capture_output=True, text=True)
        if res.returncode != 0:
            click.secho(f"[sniffer] interface '{iface}' not found", fg="red")
            sys.exit(1)
        if "state DOWN" in res.stdout:
            click.secho(f"[sniffer] interface '{iface}' is DOWN — 'ip link set {iface} up'", fg="yellow")
    except Exception:
        pass

    dwell_ms = int(max(0, dwell) * 1000)
    run_sniffer(
        cfg,
        config_path=config,
        dwell_override_ms=dwell_ms if dwell_ms > 0 else None,
        rssi_window=int(max(2, rssi_window)),
        var_threshold=float(var_threshold),
        anomaly_log_file=anomaly_log,
    )


@cli.command()
@click.option("--config", required=True, help="Path to wids.yaml")
@click.option("--pcap", required=True, help="PCAP file to replay")
@click.option("--band", default="5")
@click.option("--chan", default="36")
def replay(config: str, pcap: str, band: str, chan: str):
    """Replay a PCAP into the DB (no root)."""
    from wids.common import load_config
    from wids.scripts.replay import replay as do_replay
    cfg = load_config(config)
    do_replay(cfg, pcap, band, chan)


@cli.command()
@click.option("--config", required=True, help="Path to wids.yaml")
@click.option("--no-sniffer", is_flag=True, help="Do not start sniffer")
@click.option("--ui", is_flag=True, help="Start Vite UI dev server as well")
def dev(config: str, no_sniffer: bool, ui: bool):
    """Run API + sensor (+ sniffer via sudo) together. Ctrl+C to stop.

    With --ui, also starts the Vite UI dev server (npm run dev).
    """
    procs: list[subprocess.Popen] = []
    sudo_keepalive_stop = threading.Event()
    sudo_keepalive_thr: threading.Thread | None = None
    sudo_auth_ok = False

    def spawn(
        cmd: list[str],
        name: str,
        use_sudo: bool = False,
        cwd: str | None = None,
        env_extra: dict | None = None,
        sudo_non_interactive: bool = True,
        new_session: bool = True,
    ):
        if use_sudo:
            cmd = ["sudo", "-E"] + (["-n"] if sudo_non_interactive else []) + cmd
        env = os.environ.copy()
        # ensure unbuffered py output for clearer logs
        env.setdefault("PYTHONUNBUFFERED", "1")
        if env_extra:
            env.update(env_extra)
        # Start in a new session (default) so we can kill the whole group on Ctrl+C.
        # If we need an interactive sudo prompt, keep the controlling TTY by not creating a new session.
        p = subprocess.Popen(cmd, env=env, cwd=cwd, start_new_session=new_session)
        procs.append(p)
        click.secho(f"[dev] started {name} pid={p.pid}", fg="green")

    # Pre-auth sudo once so child commands can use non-interactive sudo (-n)
    if not no_sniffer and os.geteuid() != 0:
        try:
            rc = subprocess.call(["sudo", "-v"])  # interactive prompt
        except Exception:
            rc = 1
        if rc == 0:
            # keep timestamp fresh every 60s while dev is running
            def _sudo_keepalive():
                while not sudo_keepalive_stop.is_set():
                    try:
                        subprocess.call(["sudo", "-n", "true"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except Exception:
                        pass
                    sudo_keepalive_stop.wait(60)
            sudo_keepalive_thr = threading.Thread(target=_sudo_keepalive, name="sudo-keepalive", daemon=True)
            sudo_keepalive_thr.start()
            click.secho("[dev] sudo authenticated; will keep alive while running", fg="cyan")
            sudo_auth_ok = True
        else:
            click.secho("[dev] sudo not authenticated; sniffer may fail unless you enter password when prompted", fg="yellow")

    # API (run under sudo if available so iface ops work without prompts)
    if sudo_auth_ok and os.geteuid() != 0:
        # Reuse TTY timestamp: do not create a new session
        spawn([_py(), "-m", "wids", "api", "--config", config], name="api", use_sudo=True, sudo_non_interactive=True, new_session=False)
    else:
        spawn([_py(), "-m", "wids", "api", "--config", config], name="api")
    # Sensor
    spawn([_py(), "-m", "wids", "sensor", "--config", config], name="sensor")
    # Sniffer (sudo)
    if not no_sniffer:
        need_sudo = (os.geteuid() != 0)
        if need_sudo:
            # Try passwordless first; fall back to interactive sudo so it can prompt.
            try:
                rc = subprocess.call(["sudo", "-n", "true"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                rc = 1
            if rc == 0:
                # Use existing TTY timestamp: do not create a new session so sudo -n can reuse it
                spawn([_py(), "-m", "wids", "sniffer", "--config", config], name="sniffer", use_sudo=True, sudo_non_interactive=True, new_session=False)
            else:
                click.secho("[dev] sudo will prompt for password to start sniffer...", fg="yellow")
                # Keep controlling TTY so the prompt works: do NOT create a new session here.
                spawn([_py(), "-m", "wids", "sniffer", "--config", config], name="sniffer", use_sudo=True, sudo_non_interactive=False, new_session=False)
        else:
            spawn([_py(), "-m", "wids", "sniffer", "--config", config], name="sniffer", use_sudo=False)

    # UI (Vite dev server)
    if ui:
        repo_root = pathlib.Path(__file__).resolve().parents[2]
        ui_dir = repo_root / "ui"
        if not ui_dir.exists():
            click.secho(f"[dev] ui directory not found at {ui_dir}", fg="red")
        elif not shutil.which("npm"):
            click.secho("[dev] npm not found in PATH — install Node.js to run UI", fg="red")
        else:
            # Load config to propagate API base + key to Vite
            try:
                from wids.common import load_config
                cfg = load_config(config)
                api = cfg.get("api", {}) or {}
                port = api.get("bind_port", 8080)
                api_key = api.get("api_key", "")
                env_extra = {
                    "VITE_API_BASE": f"http://localhost:{port}/api",
                    "VITE_API_KEY": str(api_key),
                }
            except Exception:
                env_extra = None
            # Run Vite; pass --strictPort to avoid auto-port change confusion
            spawn(["npm", "run", "dev", "--", "--strictPort"], name="ui", cwd=str(ui_dir), env_extra=env_extra)

    # Graceful shutdown on Ctrl+C/TERM
    def _shutdown(*_):
        click.secho("\n[dev] stopping processes...", fg="yellow")
        for p in list(procs):
            try:
                # Terminate the whole process group
                os.killpg(p.pid, signal.SIGTERM)
            except Exception:
                try:
                    p.terminate()
                except Exception:
                    pass
    signal.signal(signal.SIGINT, _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)

    # Wait for children
    import time
    try:
        while any(p.poll() is None for p in procs):
            for p in list(procs):
                rc = p.poll()
                if rc is not None:
                    click.secho(f"[dev] process pid={p.pid} exited rc={rc}", fg="cyan")
                    procs.remove(p)
            if not procs:
                break
            time.sleep(0.5)
    except KeyboardInterrupt:
        _shutdown()
    finally:
        # Ensure all gone
        for p in list(procs):
            try:
                p.wait(timeout=3)
            except Exception:
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except Exception:
                    try:
                        p.kill()
                    except Exception:
                        pass
        # stop sudo keepalive and drop timestamp
        try:
            sudo_keepalive_stop.set()
            if sudo_keepalive_thr:
                sudo_keepalive_thr.join(timeout=1.0)
            subprocess.call(["sudo", "-k"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
        click.secho("[dev] all processes stopped", fg="green")


@cli.command(name="iface-up")
@click.option("--dev", required=True, help="Wireless interface name (e.g., wlan0)")
def iface_up(dev: str):
    """Put an interface into monitor mode and set it UP."""
    cmds = [
        ["ip", "link", "set", dev, "down"],
        ["iw", "dev", dev, "set", "type", "monitor"],
        ["ip", "link", "set", dev, "up"],
    ]
    for c in cmds:
        rc = subprocess.call(["sudo", "-E"] + c if os.geteuid() != 0 else c)
        if rc != 0:
            click.secho(f"[iface] command failed: {' '.join(c)} (rc={rc})", fg="red")
            sys.exit(rc)
    click.secho(f"[iface] {dev} in monitor mode and UP", fg="green")


if __name__ == "__main__":
    cli()
