from datetime import datetime
from scapy.all import sniff, Dot11, Dot11Beacon, Dot11Deauth, Dot11Disas, Dot11Elt, RadioTap, conf
import threading, time, subprocess, random, statistics, math
from collections import deque, defaultdict

from wids.db import get_engine, init_db, ensure_schema, session, Event, Log
from wids.ie.rsn import parse_rsn_info


def _extract_ssid(pkt):
    try:
        elt = pkt.getlayer(Dot11Elt)
        while elt is not None:
            if getattr(elt, 'ID', None) == 0:  # SSID
                return elt.info.decode(errors="ignore")
            elt = elt.payload.getlayer(Dot11Elt)
    except Exception:
        pass
    return None


def _derive_chan_band(pkt):
    # Try DS Parameter Set first (ID=3)
    chan = None
    try:
        elt = pkt.getlayer(Dot11Elt)
        while elt is not None:
            if getattr(elt, 'ID', None) == 3 and len(elt.info) >= 1:
                chan = int(elt.info[0])
                break
            elt = elt.payload.getlayer(Dot11Elt)
    except Exception:
        pass

    # Band inference
    band = "?"
    if chan is not None:
        if 1 <= chan <= 14:
            band = "2.4"
        elif 36 <= chan <= 196:
            band = "5"
        elif 1 <= chan <= 233:  # ambiguous; without freq assume 6GHz if not 2.4 range
            band = "6"

    # If no channel from DS, try RadioTap frequency
    if chan is None:
        try:
            if pkt.haslayer(RadioTap) and hasattr(pkt[RadioTap], 'ChannelFrequency'):
                freq = int(pkt[RadioTap].ChannelFrequency)
                if 2412 <= freq <= 2484:
                    chan = int(round((freq - 2407) / 5.0))
                    band = "2.4"
                elif 5000 <= freq <= 5900:
                    chan = int(round((freq - 5000) / 5.0))
                    band = "5"
                elif 5955 <= freq <= 7115:
                    chan = int(round((freq - 5955) / 5.0) + 1)
                    band = "6"
                else:
                    chan = 0
                    band = "?"
        except Exception:
            chan = 0
            band = "?"

    if chan is None:
        chan = 0
    return int(chan), str(band)


def _extract_rssi(pkt):
    try:
        if pkt.haslayer(RadioTap) and hasattr(pkt[RadioTap], 'dBm_AntSignal'):
            return int(pkt[RadioTap].dBm_AntSignal)
    except Exception:
        return None
    return None


def run_sniffer(
    cfg: dict,
    config_path: str | None = None,
    *,
    dwell_override_ms: int | None = None,
    rssi_window: int = 20,
    var_threshold: float = 150.0,
    anomaly_log_file: str | None = None,
):
    """Start a Scapy sniffer on cfg['capture']['iface'] and insert Event rows."""
    iface = cfg.get("capture", {}).get("iface")
    if not iface:
        raise RuntimeError("capture.iface not configured")

    def log_db(level: str, msg: str):
        try:
            with session(engine) as db:
                db.add(Log(ts=datetime.utcnow(), source="sniffer", level=level, message=msg))
                db.commit()
        except Exception:
            pass
    log_db("info", f"sniffer starting on iface={iface}")

    engine = get_engine(cfg["database"]["path"])
    init_db(engine)
    ensure_schema(engine)

    # Sniffer tuning from config (optional)
    sncfg = (cfg.get("sniffer") or {}) if isinstance(cfg, dict) else {}
    parse_rsn = bool(sncfg.get("parse_rsn", False))
    log_stats_enabled = bool(sncfg.get("log_stats", False))
    stats_period = int(sncfg.get("stats_period_sec", 10) or 10)
    debug_print = bool(sncfg.get("debug_print", False))

    # Target tracking: defended SSID and allowed BSSIDs
    defense = (cfg.get("defense") or {}) if isinstance(cfg, dict) else {}
    defended_ssid = (defense.get("ssid") or "").strip()
    tracked_bssids = set()
    try:
        tracked_bssids = {str(x).lower() for x in (defense.get("allowed_bssids") or []) if isinstance(x, str)}
    except Exception:
        tracked_bssids = set()

    # RSSI window and ESSID flip tracking structures
    rssi_windows: dict[str, deque] = defaultdict(lambda: deque(maxlen=max(2, int(rssi_window))))
    essids_seen: dict[str, set[str]] = defaultdict(set)
    last_var_alert_ts: dict[str, float] = {}
    last_essid_alert_ts: dict[str, float] = {}

    # Optional anomaly file logger
    anomaly_fh = None
    if anomaly_log_file:
        try:
            anomaly_fh = open(anomaly_log_file, "a", encoding="utf-8")
        except Exception:
            anomaly_fh = None

    stats = {
        "seen": 0,
        "beacon": 0,
        "deauth": 0,
        "disassoc": 0,
        "last_log": 0.0,
    }

    def _maybe_log():
        now = time.time()
        if log_stats_enabled and (now - stats["last_log"]) >= max(1, stats_period):
            buf_len = len(getattr(handle, "_buf", []))
            log_db(
                "info",
                f"sniffer stats: seen={stats['seen']} beacon={stats['beacon']} deauth={stats['deauth']} disassoc={stats['disassoc']} buf={buf_len}",
            )
            stats["last_log"] = now

    def _anomaly_log(msg: str):
        try:
            ts = datetime.utcnow().isoformat() + "Z"
            line = f"[{ts}] {msg}\n"
            if anomaly_fh:
                anomaly_fh.write(line)
                anomaly_fh.flush()
        except Exception:
            pass

    def handle(pkt):
        if not pkt.haslayer(Dot11):
            return
        stats["seen"] += 1

        d11 = pkt[Dot11]
        ev_type = None
        ssid = None
        if pkt.haslayer(Dot11Beacon):
            ev_type = "mgmt.beacon"
            ssid = _extract_ssid(pkt)
            stats["beacon"] += 1
        elif pkt.haslayer(Dot11Deauth):
            ev_type = "mgmt.deauth"
            stats["deauth"] += 1
        elif pkt.haslayer(Dot11Disas):
            ev_type = "mgmt.disassoc"
            stats["disassoc"] += 1
        else:
            # Not a frame we persist — still log rate
            _maybe_log()
            return

        src = getattr(d11, 'addr2', None)
        dst = getattr(d11, 'addr1', None)
        bssid = getattr(d11, 'addr3', None)
        chan, band = _derive_chan_band(pkt)
        rssi = _extract_rssi(pkt)

        # Always insert deauth/disassoc; filtering is done by detectors for accuracy.

        rsn = {}
        if ev_type == "mgmt.beacon" and parse_rsn:
            rsn = parse_rsn_info(pkt) or {}

        e = Event(
            ts=datetime.utcnow(),
            type=ev_type,
            band=str(band),
            chan=int(chan),
            src=src,
            dst=dst,
            bssid=bssid,
            ssid=ssid,
            rssi=rssi,
            rsn_akms=",".join(sorted(rsn.get("akms", []))) if rsn else None,
            rsn_ciphers=",".join(sorted(rsn.get("ciphers", []))) if rsn else None,
        )

        # Batch insertions with periodic flush
        if not hasattr(handle, "_buf"):
            handle._buf = []  # type: ignore[attr-defined]
            handle._last_flush = 0.0  # type: ignore[attr-defined]
        handle._buf.append(e)  # type: ignore[attr-defined]
        now = time.time()
        should_flush = (len(handle._buf) >= 400) or (now - getattr(handle, "_last_flush", 0.0) >= 0.8)  # type: ignore[attr-defined]
        if should_flush:
            with session(engine) as db:
                try:
                    # Use bulk insert to reduce ORM overhead
                    db.bulk_save_objects(handle._buf)  # type: ignore[attr-defined]
                except Exception:
                    # Fallback to add loop on any edge case
                    for x in handle._buf:  # type: ignore[attr-defined]
                        db.add(x)
                db.commit()
            handle._buf.clear()  # type: ignore[attr-defined]
            handle._last_flush = now  # type: ignore[attr-defined]
        # Live updates and anomaly detection for defended BSSID(s)
        try:
            b_lower = (bssid or "").lower() if bssid else ""
            # If no explicit BSSID allowlist but defended SSID is set, learn dynamically
            if not tracked_bssids and defended_ssid and ssid and ssid == defended_ssid and b_lower:
                tracked_bssids.add(b_lower)

            if b_lower and ((tracked_bssids and b_lower in tracked_bssids) or (defended_ssid and ssid == defended_ssid)):
                # Maintain ESSIDs seen per BSSID
                if ssid:
                    ess_before = len(essids_seen[b_lower])
                    essids_seen[b_lower].add(ssid)
                    if len(essids_seen[b_lower]) > 1 and ess_before <= 1:
                        # ESSID flip detected
                        if time.time() - last_essid_alert_ts.get(b_lower, 0.0) > 5.0:
                            _anomaly_log(f"ESSID flip detected for {b_lower}: {sorted(list(essids_seen[b_lower]))}")
                            last_essid_alert_ts[b_lower] = time.time()

                # Track RSSI window and compute variance; trigger on large variance
                if rssi is not None:
                    win = rssi_windows[b_lower]
                    win.append(int(rssi))
                    # Optional live debug printing (disabled by default for performance)
                    if debug_print:
                        try:
                            _anomaly_log(f"sniffer: ch={chan} pwr={int(rssi)} ssid={ssid or ''} bssid={b_lower}")
                        except Exception:
                            pass
                    if len(win) >= max(3, int(rssi_window) // 2):
                        try:
                            var = statistics.pvariance(win)  # population variance
                        except Exception:
                            # Fallback manual variance
                            m = sum(win) / len(win)
                            var = sum((x - m) ** 2 for x in win) / len(win)
                        if var > float(var_threshold) and (time.time() - last_var_alert_ts.get(b_lower, 0.0) > 5.0):
                            _anomaly_log(f"PWR flip anomaly detected for {b_lower}: variance={var:.1f} window={list(win)}")
                            last_var_alert_ts[b_lower] = time.time()
        except Exception:
            pass

        _maybe_log()

    # Flush any remaining buffered events periodically
    def flush():
        if hasattr(handle, "_buf") and handle._buf:  # type: ignore[attr-defined]
            with session(engine) as db:
                try:
                    db.bulk_save_objects(handle._buf)  # type: ignore[attr-defined]
                except Exception:
                    for x in handle._buf:  # type: ignore[attr-defined]
                        db.add(x)
                db.commit()
            handle._buf.clear()  # type: ignore[attr-defined]

    # Optional: channel hopper
    stop_evt = threading.Event()

    def _chan_to_freq(band: str, ch: int) -> int:
        try:
            ch = int(ch)
        except Exception:
            return 0
        if band == "2.4":
            return 2407 + 5 * ch
        if band == "5":
            return 5000 + 5 * ch
        if band == "6":
            return 5955 + (ch - 1) * 5
        return 0

    def _hop_loop():
        import os, yaml
        last_plan = None
        last_plan_ts = 0.0
        last_plan_key = None  # (plan_src, frozenset(channels))
        dwell_ms = 250
        idx = 0
        last_cfg_mtime = 0.0

        def _build_plan():
            nonlocal dwell_ms, last_plan, last_plan_ts, last_plan_key
            # Prefer reading from config file to support live updates from API/UI
            hop_cfg = None
            try:
                if config_path and os.path.exists(config_path):
                    st = os.stat(config_path)
                    nonlocal last_cfg_mtime
                    if st.st_mtime > last_cfg_mtime:
                        last_cfg_mtime = st.st_mtime
                    doc = yaml.safe_load(open(config_path, 'r').read()) or {}
                    hop_cfg = ((doc.get('capture') or {}).get('hop') or {})
                else:
                    hop_cfg = ((cfg.get('capture') or {}).get('hop') or {})
            except Exception:
                hop_cfg = ((cfg.get('capture') or {}).get('hop') or {})

            enabled = bool(hop_cfg.get('enabled', False))
            if not enabled:
                return enabled, [], None

            # Simple modes only: lock | list | all
            mode = (hop_cfg.get('mode') or 'all').strip().lower()
            if mode not in {'lock','list','all'}:
                mode = 'all'

            bands = hop_cfg.get('bands') or ["2.4", "5"]
            # Precompute union of channels for 'all' mode; favor full 2.4 coverage if unset
            chans = []
            c24 = hop_cfg.get('channels_24')
            if c24 is None and mode == 'all' and '2.4' in bands:
                c24 = list(range(1, 14))
            if '2.4' in bands:
                chans += list(c24 or [1, 6, 11])
            if '5' in bands:
                chans += list(hop_cfg.get('channels_5') or [36, 40, 44, 48, 149, 153, 157, 161])
            if '6' in bands:
                chans += list(hop_cfg.get('channels_6') or [])

            # Replace legacy smart modes with simple, explicit modes only: lock | list | all
            plan_src = 'static'
            if mode == 'lock':
                lc = hop_cfg.get('lock_channel')
                try:
                    chans = [int(lc)] if lc is not None else []
                except Exception:
                    chans = []
                plan_src = 'lock'
            elif mode == 'list':
                v = hop_cfg.get('list_channels') or []
                vv = []
                for x in v:
                    try:
                        vv.append(int(x))
                    except Exception:
                        pass
                chans = vv
                plan_src = 'list'
            else:  # 'all'
                plan_src = 'all'

            plan = []
            for ch in chans:
                try:
                    ch = int(ch)
                except Exception:
                    continue
                if 1 <= ch <= 14 and '2.4' in bands:
                    plan.append(("2.4", ch))
                elif 36 <= ch <= 196 and '5' in bands:
                    plan.append(("5", ch))
                elif 1 <= ch <= 233 and '6' in bands:
                    plan.append(("6", ch))

            # Dwell override (CLI) wins over file/config
            if dwell_override_ms and int(dwell_override_ms) > 0:
                dwell_ms = int(dwell_override_ms)
            else:
                dwell_ms = int(hop_cfg.get('dwell_ms', 100) or 100)
            # Decide whether to adopt a new plan or keep the previous order
            if plan:
                plan_channels = [p[1] for p in plan]
                key = (plan_src or mode or 'static', frozenset(plan_channels))
            else:
                key = None
            if plan and key != last_plan_key:
                # New channel set: create a fresh order once and remember it
                random.shuffle(plan)
                try:
                    with session(engine) as db:
                        src = plan_src or mode or 'static'
                        db.add(Log(ts=datetime.utcnow(), source="sniffer", level="info", message=f"hop plan {src} channels={','.join(str(p[1]) for p in plan)}"))
                        db.commit()
                except Exception:
                    pass
                last_plan = list(plan)
                last_plan_ts = time.time()
                last_plan_key = key
            # Reuse prior order if channel set hasn't changed
            if plan and key == last_plan_key and last_plan:
                plan = list(last_plan)
            return True, plan, (plan_src or mode or 'static')

        while not stop_evt.is_set():
            try:
                enabled, plan, _plan_src = _build_plan()
                if not enabled or not plan:
                    # Disabled or no plan — wait a bit and retry (supports live enable)
                    stop_evt.wait(1.0)
                    continue

                band, ch = plan[idx % len(plan)]
                idx += 1
                freq = _chan_to_freq(band, ch)
                cmd = ["iw", "dev", iface, "set", "freq", str(freq)] if freq else ["iw", "dev", iface, "set", "channel", str(ch)]
                try:
                    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except Exception:
                    pass
                # Optional: log occasionally
                if idx % len(plan) == 1:
                    try:
                        with session(engine) as db:
                            db.add(Log(ts=datetime.utcnow(), source="sniffer", level="info", message=f"hop step mode={_plan_src} band={band} ch={ch} plan_sz={len(plan)}"))
                            db.commit()
                    except Exception:
                        pass
                # Allow faster hopping; floor at 20ms to avoid hammering drivers
                stop_evt.wait(max(dwell_ms, 20) / 1000.0)
            except Exception as e:
                # Make the hopper resilient to unexpected errors
                try:
                    with session(engine) as db:
                        db.add(Log(ts=datetime.utcnow(), source="sniffer", level="error", message=f"hop loop error: {e}"))
                        db.commit()
                except Exception:
                    pass
                stop_evt.wait(1.0)

    hopper = threading.Thread(target=_hop_loop, name="chan-hopper", daemon=True)
    hopper.start()

    def _iface_is_up(name: str) -> bool:
        """Return True if the interface appears usable for sniffing.

        Accepts ip -br states like UP or UNKNOWN (common for monitor ifaces).
        Only treats explicit DOWN as unavailable.
        """
        try:
            res = subprocess.run(["ip", "-br", "link", "show", name], capture_output=True, text=True)
            if res.returncode == 0 and res.stdout:
                out = f" {res.stdout.strip()} ".upper()
                # Consider anything that's not explicitly DOWN as usable (UNKNOWN is OK in monitor mode)
                if " DOWN " in out:
                    return False
                return True
        except Exception:
            pass
        # Fallback: parse verbose ip link output
        try:
            res = subprocess.run(["ip", "link", "show", name], capture_output=True, text=True)
            if res.returncode != 0:
                return False
            out = res.stdout
            # Look for flags containing UP inside angle brackets, or absence of 'state DOWN'
            return ("<" in out and ",UP," in out) or ("state DOWN" not in out)
        except Exception:
            return False

    try:
        # Filter at the capture layer to reduce Python work
        def _lfilter(p):
            try:
                if not p.haslayer(Dot11):
                    return False
                return p.haslayer(Dot11Beacon) or p.haslayer(Dot11Deauth) or p.haslayer(Dot11Disas)
            except Exception:
                return False
        # Resilient sniff loop: restart on link-down or transient errors
        backoff = 0.5
        # Prefer libpcap backend for BPF filtering where available
        try:
            conf.use_pcap = True
        except Exception:
            pass
        # BPF to restrict to beacon/deauth/disassoc when supported
        bpf = "wlan type mgt and (wlan subtype beacon or wlan subtype deauth or wlan subtype disassoc)"
        while not stop_evt.is_set():
            # Wait until interface is UP to avoid immediate socket failure
            if not _iface_is_up(iface):
                try:
                    log_db("warn", f"sniffer: interface {iface} is DOWN; waiting...")
                except Exception:
                    pass
                stop_evt.wait(1.0)
                continue
            try:
                sniff(
                    iface=iface,
                    store=False,
                    prn=handle,
                    lfilter=_lfilter,
                    filter=bpf,
                    timeout=5,
                )
                # sniff returns periodically due to timeout; loop continues
                backoff = 0.5
            except Exception as e:
                try:
                    log_db("warn", f"sniffer socket error: {e}; retrying")
                except Exception:
                    pass
                stop_evt.wait(backoff)
                backoff = min(backoff * 2, 5.0)
    finally:
        stop_evt.set()
        try:
            hopper.join(timeout=1.0)
        except Exception:
            pass
        flush()
        log_db("info", "sniffer stopped")
        try:
            if anomaly_fh:
                anomaly_fh.close()
        except Exception:
            pass
