# src/wids/sensor/main.py
from wids.common import load_config, setup_logging
from wids.db import get_engine, init_db, ensure_schema, session, Event, Alert, Log
from wids.alerts import send_discord, send_email

from sqlmodel import select, text
from datetime import datetime, timedelta
import argparse, time, signal, os
from collections import deque, defaultdict
import statistics

def detect_deauths(db, defense: dict, window_sec=10, per_src_limit=30, global_limit=80):
    "Count deauths via SQL GROUP BY to reduce Python overhead."
    since = datetime.utcnow() - timedelta(seconds=window_sec)
    try:
        # Raw SQL for performance: count per src
        rows = db.exec(
            text(
                """
                SELECT COALESCE(LOWER(CAST(src AS TEXT)), 'unknown') AS s, COUNT(1) AS c
                FROM event
                WHERE ts >= :since AND type = 'mgmt.deauth'
                GROUP BY s
                """
            ),
            {"since": since},
        ).all()
        counts = {str(r[0]): int(r[1]) for r in rows}
        total = sum(counts.values())
    except Exception:
        # Fallback to ORM
        rows = db.exec(select(Event).where(Event.ts >= since).where(Event.type == "mgmt.deauth")).all()
        counts: dict[str, int] = {}
        total = 0
        for e in rows:
            src = (e.src or "unknown").lower()
            counts[src] = counts.get(src, 0) + 1
            total += 1
    offenders = [s for s, c in counts.items() if c >= per_src_limit]
    triggered = total >= int(global_limit or 0)
    return triggered, total, offenders, counts

def loop(cfg, config_path: str | None = None):
    engine = get_engine(cfg["database"]["path"])
    init_db(engine)

    # Ensure schema + indexes
    with session(engine) as db:
        ensure_schema(engine)
        db.exec(text("CREATE INDEX IF NOT EXISTS idx_events_ts ON event(ts);"))
        db.exec(text("CREATE INDEX IF NOT EXISTS idx_events_type_ts ON event(type, ts);"))
        db.commit()
    # optional DB ready log
    try:
        with session(engine) as db:
            db.add(Log(ts=datetime.utcnow(), source="sensor", level="info", message="db indexes ensured"))
            db.commit()
    except Exception:
        pass

    w = cfg.get("thresholds", {}).get("deauth", {}).get("window_sec", 10)
    per_src = cfg.get("thresholds", {}).get("deauth", {}).get("per_src_limit", 30)
    glob = cfg.get("thresholds", {}).get("deauth", {}).get("global_limit", 80)
    cooldown = cfg.get("thresholds", {}).get("deauth", {}).get("cooldown_sec", 60)
    # Rogue/PWR anomaly thresholds (defaults)
    rogue_cfg = (cfg.get("thresholds", {}).get("rogue", {}) or {})
    pwr_win = int(rogue_cfg.get("pwr_window", 20) or 20)
    pwr_var_threshold = float(rogue_cfg.get("pwr_var_threshold", 150) or 150)
    pwr_cooldown = int(rogue_cfg.get("pwr_cooldown_sec", 10) or 10)
    logger = setup_logging()

    logger.info(f"sensor: deauth window={w}s per_src={per_src} global={glob} cooldown={cooldown}s")

    last_fire_ts = 0.0
    last_sig = None
    # Smart logging state
    last_logged_total = None
    last_logged_offenders = set()
    last_log_ts = 0.0
    stop = False

    def _sig(*_):
        nonlocal stop
        stop = True
        logger.info("sensor: stopping...")

    signal.signal(signal.SIGINT, _sig)
    signal.signal(signal.SIGTERM, _sig)

    defense = cfg.get("defense", {})
    def_ssid = (defense.get("ssid") or "").strip()
    armed = bool(def_ssid)
    def log_db(level: str, msg: str):
        try:
            with session(engine) as db:
                db.add(Log(ts=datetime.utcnow(), source="sensor", level=level, message=msg))
                db.commit()
        except Exception:
            pass

    if not armed:
        log_db("info", "sensor not armed (no defended SSID) — deauth detection still active")

    # In-memory RSN baseline per allowed BSSID
    rsn_baseline = {}  # bssid(lower) -> { 'akms': set, 'ciphers': set }
    # PWR variance tracking
    pwr_windows: dict[str, deque[int]] = defaultdict(lambda: deque(maxlen=max(3, int(pwr_win))))
    last_pwr_alert_ts: dict[str, float] = {}
    # Dynamic tracked BSSIDs if none explicitly allowed
    tracked_bssids = set()
    # Deduplicate beacon events to avoid re-adding same RSSI
    seen_beacon_ids = deque(maxlen=10000)
    seen_beacon_set = set()

    def _remember_eid(eid: int) -> bool:
        try:
            if eid in seen_beacon_set:
                return False
            seen_beacon_set.add(eid)
            seen_beacon_ids.append(eid)
            # Periodic compaction when deque evicts
            if len(seen_beacon_set) > len(seen_beacon_ids):
                try:
                    seen_beacon_set.clear()
                    seen_beacon_set.update(seen_beacon_ids)
                except Exception:
                    pass
            return True
        except Exception:
            return True

    # Simple hot-reload support for config updates from the API/UI
    last_cfg_check = 0.0
    cfg_mtime = None
    if config_path and os.path.exists(config_path):
        try:
            cfg_mtime = os.stat(config_path).st_mtime
        except Exception:
            cfg_mtime = None

    while not stop:
        with session(engine) as db:
            # Hot-reload defense/thresholds if file changed (check every 2s)
            now_ts = time.time()
            if config_path and (now_ts - last_cfg_check) >= 2.0:
                last_cfg_check = now_ts
                try:
                    st = os.stat(config_path)
                    if not cfg_mtime or st.st_mtime > cfg_mtime:
                        cfg_mtime = st.st_mtime
                        cfg = load_config(config_path)
                        defense = cfg.get("defense", {})
                        def_ssid = (defense.get("ssid") or "").strip()
                        armed = bool(def_ssid)
                        w = cfg.get("thresholds", {}).get("deauth", {}).get("window_sec", w)
                        per_src = cfg.get("thresholds", {}).get("deauth", {}).get("per_src_limit", per_src)
                        glob = cfg.get("thresholds", {}).get("deauth", {}).get("global_limit", glob)
                        cooldown = cfg.get("thresholds", {}).get("deauth", {}).get("cooldown_sec", cooldown)
                        # Rogue runtime thresholds
                        rogue_cfg = (cfg.get("thresholds", {}).get("rogue", {}) or {})
                        new_win = int(rogue_cfg.get("pwr_window", pwr_win) or pwr_win)
                        pwr_var_threshold = float(rogue_cfg.get("pwr_var_threshold", pwr_var_threshold) or pwr_var_threshold)
                        pwr_cooldown = int(rogue_cfg.get("pwr_cooldown_sec", pwr_cooldown) or pwr_cooldown)
                        if new_win != pwr_win:
                            pwr_win = new_win
                            try:
                                for b, dq in list(pwr_windows.items()):
                                    pwr_windows[b] = deque(dq, maxlen=max(3, int(pwr_win)))
                            except Exception:
                                pass
                        log_db("info", f"sensor reloaded: armed={armed} ssid='{def_ssid}' window={w}s per_src={per_src} global={glob}")
                except Exception as e:
                    log_db("error", f"sensor config reload failed: {e}")

            # --- Deauth detection (scoped) ---
            trig, total, offenders, counts = detect_deauths(db, defense, w, per_src, glob)
            sig = ("deauth_flood", total, tuple(sorted(offenders)))
            now = time.time()
            too_soon = (now - last_fire_ts) < cooldown
            same_as_before = (sig == last_sig)

            # Smart logging: only log when there is activity or state changes
            if total > 0:
                changed = (last_logged_total != total) or (set(offenders) != last_logged_offenders)
                if changed or (time.time() - last_log_ts) >= 15:
                    log_db("info", f"sensor deauth: total={total} offenders={len(offenders)} window={w}s")
                    last_logged_total = total
                    last_logged_offenders = set(offenders)
                    last_log_ts = time.time()

            # Fire alert solely based on global threshold; ignore 'armed'
            if trig and not (too_soon and same_as_before):
                a = Alert(
                    ts=datetime.utcnow(),
                    severity="critical" if total >= glob*2 else "warn",
                    kind="deauth_flood",
                    summary=f"Deauth burst: total={total}, offenders={len(offenders)}",
                )
                db.add(a)
                db.commit()
                log_db("warn", f"alert: {a.kind} {a.summary}")

                # Notifications (best-effort)
                try:
                    cfg_alerts = cfg.get("alerts", {})
                    msg = f"[PiGuard] {a.kind} ({a.severity}) — {a.summary}"
                    if cfg_alerts.get("discord_webhook"):
                        send_discord(cfg_alerts["discord_webhook"], msg)
                    em = cfg_alerts.get("email", {})
                    if em and em.get("to"):
                        send_email(
                            em.get("smtp_host", "smtp.gmail.com"),
                            int(em.get("smtp_port", 587)),
                            em.get("username", ""),
                            em.get("password", ""),
                            em.get("from", "PiGuard <alerts@example.com>"),
                            em.get("to", []),
                            subject=f"[PiGuard] {a.kind} {a.severity}",
                            body=msg,
                        )
                except Exception as e:
                    log_db("error", f"notify failed: {e}")

                last_fire_ts = now
                last_sig = sig

            # --- Rogue AP check (over recent beacons for defended SSID) ---
            since = datetime.utcnow() - timedelta(seconds=w)
            q = select(Event).where(Event.ts >= since).where(Event.type == "mgmt.beacon")
            if armed and def_ssid:
                q = q.where(Event.ssid == def_ssid)
            beacons = db.exec(q).all()
            for e in beacons:
                if not armed:
                    break
                if not e.ssid or e.ssid != def_ssid:
                    continue

                bssid = (e.bssid or "").lower()
                allowed_bssids = set(b.lower() for b in defense.get("allowed_bssids", []) if isinstance(b, str))
                allowed_channels = set(int(c) for c in defense.get("allowed_channels", []) if isinstance(c, (int, str)))
                allowed_bands = set(str(b) for b in defense.get("allowed_bands", []) if isinstance(b, (int, str)))

                # Build/update RSN baseline for allowed BSSIDs
                akms = set((e.rsn_akms or "").split(",")) if e.rsn_akms else set()
                ciphers = set((e.rsn_ciphers or "").split(",")) if e.rsn_ciphers else set()
                if bssid and bssid in allowed_bssids and (akms or ciphers):
                    if bssid not in rsn_baseline:
                        rsn_baseline[bssid] = {"akms": akms.copy(), "ciphers": ciphers.copy()}
                # Populate tracked set if no explicit allowlist
                if not allowed_bssids and bssid:
                    tracked_bssids.add(bssid)

                reason = None
                if allowed_bssids and (not bssid or bssid not in allowed_bssids):
                    reason = f"SSID {def_ssid} from unknown BSSID {e.bssid}"
                elif allowed_channels and e.chan not in allowed_channels:
                    reason = f"SSID {def_ssid} on unapproved channel {e.chan}"
                elif allowed_bands and str(e.band) not in allowed_bands:
                    reason = f"SSID {def_ssid} on unapproved band {e.band}"
                else:
                    # RSN mismatch check (only if we have a baseline from allowed BSSIDs)
                    if allowed_bssids and rsn_baseline and (akms or ciphers):
                        # Compare against any one baseline (simple approach)
                        base = next(iter(rsn_baseline.values()))
                        if ((base.get("akms") and akms and akms != base["akms"]) or
                            (base.get("ciphers") and ciphers and ciphers != base["ciphers"])):
                            reason = f"SSID {def_ssid} RSN mismatch (akm/cipher) at {e.bssid}"

                # PWR variance anomaly integrated with rogue detection
                if not reason and e.id is not None and bssid:
                    try:
                        if _remember_eid(int(e.id)) and e.rssi is not None:
                            # Track only defended BSSID(s) either via allowlist or learned set
                            if (allowed_bssids and bssid in allowed_bssids) or (not allowed_bssids and bssid in tracked_bssids):
                                dq = pwr_windows[bssid]
                                dq.append(int(e.rssi))
                                if len(dq) >= max(3, int(pwr_win) // 2):
                                    try:
                                        var = statistics.pvariance(dq)
                                    except Exception:
                                        m = sum(dq) / len(dq)
                                        var = sum((x - m) ** 2 for x in dq) / len(dq)
                                    now2 = time.time()
                                    if var > float(pwr_var_threshold) and (now2 - last_pwr_alert_ts.get(bssid, 0.0) >= pwr_cooldown):
                                        reason = f"SSID {def_ssid} power variance anomaly at {e.bssid} (var={var:.1f}, n={len(dq)})"
                                        last_pwr_alert_ts[bssid] = now2
                    except Exception:
                        pass

                if reason:
                    a = Alert(
                        ts=datetime.utcnow(),
                        severity="warn",
                        kind="rogue_ap",
                        summary=reason,
                    )
                    db.add(a)
                    db.commit()
                    log_db("warn", f"alert: {a.kind} {a.summary}")

                    # Optional: minimal Discord notify for rogue AP
                    try:
                        cfg_alerts = cfg.get("alerts", {})
                        if cfg_alerts.get("discord_webhook"):
                            send_discord(cfg_alerts["discord_webhook"], f"[PiGuard] {a.kind} — {a.summary}")
                    except Exception as ex:
                        log_db("error", f"notify failed: {ex}")

        time.sleep(2)

    log_db("info", "sensor exited cleanly")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    args = ap.parse_args()
    cfg = load_config(args.config)
    loop(cfg, args.config)

if __name__ == "__main__":
    main()
