import argparse
from typing import Optional
from datetime import datetime, timedelta
from fastapi import FastAPI, Depends, HTTPException, Header, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from fastapi.staticfiles import StaticFiles
from sqlmodel import select, text
from sqlalchemy import func
import uvicorn
import asyncio, json, pathlib, os, sys, signal
import secrets
import hashlib

from wids.common import load_config, setup_logging
from wids.db     import get_engine, init_db, ensure_schema, session, Event, Alert, Log
import yaml
import subprocess
import re

app = FastAPI(title="PiGuard API")
logger = setup_logging()

cfg = {}
engine = None
cfg_path = None
_alert_poller_task = None
_alert_poller_stop = asyncio.Event()
_last_alert_id_for_sse = 0

# Session store for authenticated users (username -> session_token)
_active_sessions = {}  # session_token -> {'username': str, 'expires': datetime}

# CORS for dev
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def require_key(x_api_key: Optional[str] = Header(None), authorization: Optional[str] = Header(None)):
    # Check session token first (from Authorization: Bearer <token>)
    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:]
        session = _active_sessions.get(token)
        if session and session['expires'] > datetime.utcnow():
            return  # Valid session
        # Clean up expired session
        if token in _active_sessions:
            del _active_sessions[token]

    # Fallback to API key check for backward compatibility
    wanted = cfg.get("api", {}).get("api_key")
    if wanted and x_api_key != wanted:
        raise HTTPException(status_code=401, detail="Invalid API key or session")

def get_db():
    with session(engine) as s:
        yield s

@app.get("/api/health")
def health():
    return {"status": "ok", "ts": datetime.utcnow().isoformat()+"Z"}

@app.post("/api/login")
async def login(request: Request):
    """Authenticate user with username and password from config"""
    try:
        body = await request.json()
        username = body.get("username", "").strip()
        password = body.get("password", "").strip()

        if not username or not password:
            raise HTTPException(status_code=400, detail="Username and password required")

        # Get credentials from config
        api_config = cfg.get("api", {})
        config_username = api_config.get("username", "admin")
        config_password = api_config.get("password", "change-me")

        # Validate credentials
        if username != config_username or password != config_password:
            # Log failed attempt
            try:
                _api_log("warn", f"failed login attempt for user: {username}")
            except Exception:
                pass
            raise HTTPException(status_code=401, detail="Invalid username or password")

        # Generate session token
        session_token = secrets.token_urlsafe(32)
        expires = datetime.utcnow() + timedelta(hours=24)  # 24 hour session

        _active_sessions[session_token] = {
            'username': username,
            'expires': expires
        }

        # Log successful login
        try:
            _api_log("info", f"successful login for user: {username}")
        except Exception:
            pass

        return {
            "ok": True,
            "token": session_token,
            "username": username,
            "expires": expires.isoformat() + "Z"
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Login failed: {str(e)}")

@app.post("/api/logout")
async def logout(authorization: Optional[str] = Header(None)):
    """Logout and invalidate session token"""
    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:]
        if token in _active_sessions:
            username = _active_sessions[token].get('username', 'unknown')
            del _active_sessions[token]
            try:
                _api_log("info", f"logout for user: {username}")
            except Exception:
                pass
            return {"ok": True, "message": "Logged out successfully"}
    return {"ok": True, "message": "No active session"}

@app.get("/api/overview", dependencies=[Depends(require_key)])
def overview(db=Depends(get_db)):
    def _count(model):
        res = db.exec(select(func.count()).select_from(model))
        # Support both SQLAlchemy Result and ScalarResult
        try:
            return res.scalar_one()  # type: ignore[attr-defined]
        except AttributeError:
            try:
                v = res.one()
                return v[0] if isinstance(v, (list, tuple)) else v
            except Exception:
                return 0
    events = _count(Event)
    alerts = _count(Alert)
    return {"events": int(events or 0), "alerts": int(alerts or 0)}

@app.get("/api/ssids", dependencies=[Depends(require_key)])
def list_ssids(minutes: int = Query(default=10, ge=1, le=120), db=Depends(get_db)):
    since = datetime.utcnow() - timedelta(minutes=minutes)
    rows = db.exec(
        select(Event).where(Event.ts >= since).where(Event.type == "mgmt.beacon")
    ).all()
    acc = {}
    for e in rows:
        if not e.ssid:
            continue
        item = acc.setdefault(e.ssid, {"ssid": e.ssid, "bssids": set(), "channels": set(), "bands": set()})
        if e.bssid:
            item["bssids"].add(e.bssid)
        item["channels"].add(e.chan)
        item["bands"].add(e.band)
    out = []
    for v in acc.values():
        out.append({
            "ssid": v["ssid"],
            "bssids": sorted(list(v["bssids"]))[:10],
            "channels": sorted(list(v["channels"]))[:10],
            "bands": sorted(list(v["bands"]))[:3],
        })
    return out

@app.get("/api/defense", dependencies=[Depends(require_key)])
def get_defense():
    return cfg.get("defense", {})

@app.post("/api/defense", dependencies=[Depends(require_key)])
async def set_defense(request: Request):
    body = await request.json()
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="invalid body")
    # Shallow merge
    cfg.setdefault("defense", {})
    allowed_keys = {"ssid", "allowed_bssids", "allowed_channels", "allowed_bands"}
    for k in list(body.keys()):
        if k not in allowed_keys:
            body.pop(k)
    cfg["defense"].update(body)
    # Persist to YAML
    if not cfg_path:
        raise HTTPException(status_code=500, detail="config path unknown")
    try:
        # Load current file to preserve other sections
        p = pathlib.Path(cfg_path)
        doc = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
        doc.setdefault("defense", {})
        doc["defense"].update(cfg["defense"])
        p.write_text(yaml.safe_dump(doc, sort_keys=False), encoding="utf-8")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"failed to persist: {e}")
    return {"ok": True, "defense": cfg["defense"]}

@app.get("/api/alerts", dependencies=[Depends(require_key)])
def list_alerts(limit: int = 100, db=Depends(get_db)):
    rows = db.exec(select(Alert).order_by(Alert.id.desc()).limit(limit)).all()
    return [r.model_dump() for r in rows]

@app.post("/api/alerts/test", dependencies=[Depends(require_key)])
def create_test_alert(db=Depends(get_db)):
    a = Alert(ts=datetime.utcnow(), severity="info", kind="test", summary="hello from PiGuard")
    db.add(a)
    db.commit()
    try:
        publish_alert_sse(a)
    except Exception:
        pass
    return {"ok": True, "id": a.id}

@app.post("/api/alerts/notify_test", dependencies=[Depends(require_key)])
def notify_test():
    # Send test notifications via configured channels (Discord/email)
    try:
        cfg_alerts = cfg.get("alerts", {}) or {}
        msg = "[PiGuard] notify_test — this is a test notification"
        sent = {"discord": False, "email": False}
        if cfg_alerts.get("discord_webhook"):
            try:
                from wids.alerts import send_discord
                send_discord(cfg_alerts["discord_webhook"], msg)
                sent["discord"] = True
            except Exception as e:
                _api_log("error", f"notify_test discord failed: {e}")
        em = cfg_alerts.get("email", {}) or {}
        if em and em.get("to"):
            try:
                from wids.alerts import send_email
                send_email(
                    em.get("smtp_host", "smtp.gmail.com"),
                    int(em.get("smtp_port", 587)),
                    em.get("username", ""),
                    em.get("password", ""),
                    em.get("from", "PiGuard <alerts@example.com>"),
                    em.get("to", []),
                    subject="[PiGuard] notify_test",
                    body=msg,
                )
                sent["email"] = True
            except Exception as e:
                _api_log("error", f"notify_test email failed: {e}")
        return {"ok": True, "sent": sent}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"notify_test failed: {e}")

@app.get("/api/events", dependencies=[Depends(require_key)])
def list_events(
    since_seconds: int = Query(default=60, ge=0, le=86400),
    type: Optional[str] = Query(default=None),
    limit: int = Query(default=500, ge=1, le=5000),
    db=Depends(get_db),
):
    since = datetime.utcnow() - timedelta(seconds=since_seconds)
    q = select(Event).where(Event.ts >= since)
    if type:
        q = q.where(Event.type == type)
    rows = db.exec(q.order_by(Event.id.desc()).limit(limit)).all()
    return [r.model_dump() for r in rows]

# === Logs: simple polling endpoint returning recent app logs ===
@app.get("/api/logs", dependencies=[Depends(require_key)])
def list_logs(
    since_id: Optional[int] = Query(default=None, ge=0),
    limit: int = Query(default=200, ge=1, le=1000),
    source: Optional[str] = Query(default=None),
    db=Depends(get_db),
):
    q = select(Log)
    if since_id is not None:
        q = q.where(Log.id > since_id).order_by(Log.id.asc())
    else:
        q = q.order_by(Log.id.desc())
    if source:
        q = q.where(Log.source == source)
    rows = db.exec(q.limit(limit)).all()
    return [r.model_dump() for r in rows]

# === Admin: clear tables (events/alerts/logs) ===
@app.post("/api/admin/clear", dependencies=[Depends(require_key)])
async def admin_clear(request: Request):
    body = await request.json()
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="invalid body")
    tables = body.get("tables") or ["events", "alerts"]
    valid = {"events": "event", "alerts": "alert", "logs": "log"}
    stmts = []
    for t in tables:
        name = valid.get(str(t).lower())
        if name:
            stmts.append(f"DELETE FROM {name};")
    if not stmts:
        raise HTTPException(status_code=400, detail="no valid tables requested")
    try:
        with session(engine) as db:
            for s in stmts:
                db.exec(text(s))
            db.commit()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"clear failed: {e}")
    return {"ok": True, "cleared": tables}

# === Admin: restart services (sensor/sniffer) ===
def _restart_unit_safe(name: str) -> tuple[int, str, str]:
    allowed = {
        "sniffer": "piguard-sniffer",
        "sensor": "piguard-sensor",
    }
    unit = allowed.get(name)
    if not unit:
        return 1, "", f"unsupported service: {name}"
    try:
        # API normally runs as root. Prefer direct systemctl; fallback to sudo -n when not.
        if os.geteuid() == 0:
            p = subprocess.run(["systemctl", "restart", unit], capture_output=True, text=True)
        else:
            p = subprocess.run(["sudo", "-n", "systemctl", "restart", unit], capture_output=True, text=True)
        return p.returncode, p.stdout or "", p.stderr or ""
    except Exception as e:
        return 1, "", str(e)


@app.post("/api/admin/restart", dependencies=[Depends(require_key)])
async def admin_restart(request: Request):
    body = await request.json()
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="invalid body")
    services = body.get("services")
    service = body.get("service")
    if service and not services:
        services = [service]
    if not services or not isinstance(services, list):
        raise HTTPException(status_code=400, detail="service(s) required: ['sniffer'|'sensor']")

    results = {}
    for s in services:
        name = str(s).strip().lower()
        rc, out, err = _restart_unit_safe(name)
        ok = (rc == 0)
        results[name] = {"ok": ok, "stdout": out.strip(), "stderr": err.strip(), "rc": rc}
        try:
            level = "info" if ok else "error"
            _api_log(level, f"admin restart {name}: rc={rc} {('ok' if ok else err or '').strip()}")
        except Exception:
            pass

    # 4xx only if all failed; otherwise return aggregated status
    if all(not v.get("ok") for v in results.values()):
        raise HTTPException(status_code=500, detail={"results": results})
    return {"ok": True, "results": results}

# === Settings: deauth thresholds ===
def _ensure_default_deauth(thr: dict | None) -> dict:
    thr = thr or {}
    return {
        "window_sec": int((thr.get("window_sec") or 10)),
        "per_src_limit": int((thr.get("per_src_limit") or 30)),
        "global_limit": int((thr.get("global_limit") or 80)),
        "cooldown_sec": int((thr.get("cooldown_sec") or 60)),
    }


@app.get("/api/settings/deauth", dependencies=[Depends(require_key)])
def get_deauth_settings():
    thr = (((cfg.get("thresholds") or {}).get("deauth")) or {})
    return _ensure_default_deauth(thr)


@app.post("/api/settings/deauth", dependencies=[Depends(require_key)])
async def set_deauth_settings(request: Request):
    body = await request.json()
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="invalid body")
    # Validate and coerce
    allowed = {"window_sec", "per_src_limit", "global_limit", "cooldown_sec"}
    for k in list(body.keys()):
        if k not in allowed:
            body.pop(k)
    try:
        window_sec = max(1, int(body.get("window_sec", 10)))
        per_src = max(1, int(body.get("per_src_limit", 30)))
        glob = max(1, int(body.get("global_limit", 80)))
        cooldown = max(1, int(body.get("cooldown_sec", 60)))
    except Exception:
        raise HTTPException(status_code=400, detail="invalid numeric values")

    # Update in-memory cfg
    cfg.setdefault("thresholds", {}).setdefault("deauth", {})
    cfg["thresholds"]["deauth"].update({
        "window_sec": window_sec,
        "per_src_limit": per_src,
        "global_limit": glob,
        "cooldown_sec": cooldown,
    })

    # Persist to YAML
    if not cfg_path:
        raise HTTPException(status_code=500, detail="config path unknown")
    try:
        p = pathlib.Path(cfg_path)
        doc = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
        doc.setdefault("thresholds", {}).setdefault("deauth", {})
        doc["thresholds"]["deauth"].update({
            "window_sec": window_sec,
            "per_src_limit": per_src,
            "global_limit": glob,
            "cooldown_sec": cooldown,
        })
        p.write_text(yaml.safe_dump(doc, sort_keys=False), encoding="utf-8")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"failed to persist: {e}")

    try:
        _api_log("info", f"deauth settings updated window={window_sec} per_src={per_src} global={glob} cooldown={cooldown}")
    except Exception:
        pass
    return {"ok": True, "deauth": _ensure_default_deauth(cfg.get("thresholds", {}).get("deauth"))}

# Accept alternate forms to avoid 405 from trailing slashes or different verbs
@app.post("/api/settings/deauth/", dependencies=[Depends(require_key)])
async def set_deauth_settings_slash(request: Request):
    return await set_deauth_settings(request)

@app.put("/api/settings/deauth", dependencies=[Depends(require_key)])
async def put_deauth_settings(request: Request):
    return await set_deauth_settings(request)

@app.put("/api/settings/deauth/", dependencies=[Depends(require_key)])
async def put_deauth_settings_slash(request: Request):
    return await set_deauth_settings(request)

# === SSE: stream new alerts in near real-time ===
subscribers = set()

@app.get("/api/stream")
async def stream(request: Request):
    queue = asyncio.Queue()
    subscribers.add(queue)
    # Best-effort log connect
    try:
        _api_log("info", "sse subscriber connected")
    except Exception:
        pass

    async def gen():
        try:
            # initial hello
            hello = {"hello": True, "ts": datetime.utcnow().isoformat()+"Z"}
            yield f"data: {json.dumps(hello)}\n\n"
            while True:
                if await request.is_disconnected():
                    break
                try:
                    item = await asyncio.wait_for(queue.get(), timeout=1.0)
                    yield f"data: {json.dumps(item)}\n\n"
                except asyncio.TimeoutError:
                    # keep connection alive
                    yield ": keep-alive\n\n"
        finally:
            subscribers.discard(queue)
            try:
                _api_log("info", "sse subscriber disconnected")
            except Exception:
                pass

    headers = {"Cache-Control": "no-cache", "Connection": "keep-alive"}
    return StreamingResponse(gen(), media_type="text/event-stream", headers=headers)

def publish_alert_sse(alert: Alert):
    # called by sensor via direct import is not ideal; normally use a broker.
    # Here we keep it in-process: API and sensor run in the same process only if you embed;
    # For your current split-process setup, SSE will show only test ticks.
    payload = {
        "kind": alert.kind,
        "severity": alert.severity,
        "summary": alert.summary,
        "ts": alert.ts.isoformat()+"Z",
        "id": alert.id,
    }
    for q in list(subscribers):
        try:
            q.put_nowait(payload)
        except Exception:
            pass


async def _alert_poller_loop():
    global _last_alert_id_for_sse
    # Best-effort: seed last seen id to current max to avoid replay flood on startup
    try:
        with session(engine) as db:
            res = db.exec(select(Alert.id).order_by(Alert.id.desc()).limit(1)).all()
            if res:
                v = res[0]
                _last_alert_id_for_sse = int(v if isinstance(v, int) else getattr(v, "id", 0) or 0)
    except Exception:
        pass
    # Poll for new alerts and broadcast via SSE
    while not _alert_poller_stop.is_set():
        try:
            with session(engine) as db:
                rows = (
                    db.exec(
                        select(Alert).where(Alert.id > _last_alert_id_for_sse).order_by(Alert.id.asc()).limit(200)
                    ).all()
                )
            if rows:
                for a in rows:
                    try:
                        publish_alert_sse(a)
                        if a.id and a.id > _last_alert_id_for_sse:
                            _last_alert_id_for_sse = int(a.id)
                    except Exception:
                        pass
                try:
                    _api_log("info", f"sse broadcast alerts={len(rows)} last_id={_last_alert_id_for_sse}")
                except Exception:
                    pass
            try:
                await asyncio.wait_for(_alert_poller_stop.wait(), timeout=0.8)
            except asyncio.TimeoutError:
                pass
        except Exception:
            # Backoff a bit on unexpected errors
            try:
                await asyncio.wait_for(_alert_poller_stop.wait(), timeout=1.5)
            except asyncio.TimeoutError:
                pass


@app.on_event("startup")
async def _on_startup():
    # Start background DB alert poller to feed SSE for multi-process setups
    # Guard if engine not initialized yet (should be set by main())
    global _alert_poller_task
    if engine is None:
        return
    try:
        _alert_poller_stop.clear()
    except Exception:
        pass
    _alert_poller_task = asyncio.create_task(_alert_poller_loop())


@app.on_event("shutdown")
async def _on_shutdown():
    # Stop alert poller
    try:
        _alert_poller_stop.set()
    except Exception:
        pass
    t = None
    try:
        t = _alert_poller_task
    except Exception:
        t = None
    if t:
        try:
            await asyncio.wait_for(t, timeout=2.0)
        except Exception:
            try:
                t.cancel()
            except Exception:
                pass

# === Interface/capture management ===
def _run(cmd: list[str]) -> tuple[int, str, str]:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True)
        return p.returncode, p.stdout, p.stderr
    except Exception as e:
        return 1, "", str(e)

def _sudo(cmd: list[str]) -> tuple[int, str, str]:
    if os.geteuid() == 0:
        return _run(cmd)
    return _run(["sudo", "-n", "-E"] + cmd)

def _parse_iw_dev_list(stdout: str) -> list[dict]:
    out = []
    cur = None
    for line in stdout.splitlines():
        line = line.strip()
        if line.startswith("Interface "):
            if cur:
                out.append(cur)
            cur = {"name": line.split()[1], "type": None}
        elif line.startswith("type ") and cur is not None:
            cur["type"] = line.split()[1]
    if cur:
        out.append(cur)
    return out

def _iface_info(dev: str) -> dict:
    info = {"dev": dev, "exists": False, "up": None, "type": None, "channel": None, "freq": None, "band": None}
    # ip link
    rc, out, _ = _run(["ip", "link", "show", dev])
    if rc != 0:
        return info
    info["exists"] = True
    info["up"] = ("state UP" in out) or ("UP,LOWER_UP" in out) or ("<BROADCAST,MULTICAST,UP" in out)
    # iw info
    rc, out, _ = _run(["iw", "dev", dev, "info"])
    if rc == 0:
        m = re.search(r"\btype\s+(\S+)", out)
        if m:
            info["type"] = m.group(1)
        # Try to extract channel - monitor mode may show "channel X (YYYY MHz)" or just frequency
        m = re.search(r"\bchannel\s+(\d+)\s+\((\d+)\s+MHz", out, re.IGNORECASE)
        if m:
            info["channel"] = int(m.group(1))
            info["freq"] = int(m.group(2))
        else:
            # Fallback: look for frequency only and derive channel
            m = re.search(r"\((\d{4,5})\s+MHz", out)
            if m:
                freq = int(m.group(1))
                info["freq"] = freq
                # Derive channel from frequency
                if 2412 <= freq <= 2484:
                    info["channel"] = (freq - 2407) // 5
                    info["band"] = "2.4"
                elif 5000 <= freq <= 5900:
                    info["channel"] = (freq - 5000) // 5
                    info["band"] = "5"
                elif 5955 <= freq <= 7115:
                    info["channel"] = ((freq - 5955) // 5) + 1
                    info["band"] = "6"

    # If channel hopping is active, try to read from state file (more accurate for hopping interfaces)
    if info["type"] == "monitor":
        try:
            import json, os, time
            state_file = "/tmp/piguard_channel_state.json"
            if os.path.exists(state_file):
                # Only use if file is recent (within 5 seconds)
                if time.time() - os.path.getmtime(state_file) < 5:
                    with open(state_file, 'r') as f:
                        state = json.load(f)
                        info["channel"] = state.get("channel")
                        info["freq"] = state.get("freq")
                        info["band"] = state.get("band")
        except Exception:
            pass

    return info

def _api_log(level: str, msg: str):
    try:
        with session(engine) as db:
            db.add(Log(ts=datetime.utcnow(), source="api", level=level, message=msg))
            db.commit()
    except Exception:
        pass

def _iface_has_ip(dev: str) -> bool:
    rc, out, _ = _run(["ip", "-br", "addr", "show", dev])
    if rc != 0:
        return False
    return " inet " in f" {out} "

@app.get("/api/ifaces", dependencies=[Depends(require_key)])
def list_ifaces():
    rc, out, err = _run(["iw", "dev"])
    if rc != 0:
        raise HTTPException(status_code=500, detail=f"iw dev failed: {err or rc}")
    return _parse_iw_dev_list(out)

@app.get("/api/iface", dependencies=[Depends(require_key)])
def get_iface(dev: Optional[str] = None):
    dev = dev or (cfg.get("capture", {}) or {}).get("iface")
    if not dev:
        raise HTTPException(status_code=400, detail="dev not specified and capture.iface missing")
    return _iface_info(dev)

@app.get("/api/capture", dependencies=[Depends(require_key)])
def get_capture_cfg():
    return cfg.get("capture", {}) or {}

@app.post("/api/capture", dependencies=[Depends(require_key)])
async def set_capture_cfg(request: Request):
    body = await request.json()
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="invalid body")
    cap = cfg.setdefault("capture", {})
    allowed = {"iface", "hop"}
    for k in list(body.keys()):
        if k not in allowed:
            body.pop(k)
    # Deep-merge hop if provided
    if isinstance(body.get("hop"), dict):
        hop = cap.setdefault("hop", {})
        hop.update(body["hop"])  # preserve other hop keys (bands, dwell, etc.)
        body.pop("hop", None)
    cap.update(body)
    if not cfg_path:
        raise HTTPException(status_code=500, detail="config path unknown")
    try:
        p = pathlib.Path(cfg_path)
        doc = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
        doc.setdefault("capture", {})
        # Deep-merge capture.hop as well
        if isinstance(cap.get("hop"), dict):
            doc["capture"].setdefault("hop", {})
            doc["capture"]["hop"].update(cap["hop"])  # type: ignore[index]
            tmp = cap.copy()
            tmp.pop("hop", None)
            doc["capture"].update(tmp)
        else:
            doc["capture"].update(cap)
        p.write_text(yaml.safe_dump(doc, sort_keys=False), encoding="utf-8")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"failed to persist: {e}")
    return {"ok": True, "capture": cap}

@app.post("/api/iface/monitor", dependencies=[Depends(require_key)])
async def set_monitor_mode(request: Request):
    body = await request.json()
    dev = (body or {}).get("dev") or (cfg.get("capture", {}) or {}).get("iface")
    ch = (body or {}).get("channel")
    force = bool((body or {}).get("force", False))
    if not dev:
        raise HTTPException(status_code=400, detail="dev required")
    # Optionally warn if iface has IP; allow override via force
    if _iface_has_ip(dev) and not force:
        raise HTTPException(status_code=409, detail=f"{dev} has an IP address. Pass force=true to proceed (may drop connectivity).")
    # Perform operations with rollback: always try to leave iface up on failure
    attempted: list[list[str]] = []
    def _run_step(c: list[str]) -> tuple[int, str]:
        rc, _out, err = _sudo(c)
        attempted.append(c + [f"rc={rc}", (err or "").strip()])
        return rc, (err or "").lower()

    steps = [
        ["ip", "link", "set", dev, "down"],
        ["iw", "dev", dev, "set", "type", "monitor"],
    ]
    if ch:
        steps.append(["iw", "dev", dev, "set", "channel", str(ch)])
    steps.append(["ip", "link", "set", dev, "up"])

    failed_detail = None
    for c in steps:
        rc, err_l = _run_step(c)
        if rc != 0:
            # Best-effort bring iface up before returning error
            try:
                _sudo(["ip", "link", "set", dev, "up"])
            except Exception:
                pass
            msg = " ".join(c)
            # Provide actionable guidance when driver does not support mode switch
            if any(s in err_l for s in [
                "operation not supported",
                "resource busy",
                "device or resource busy",
                "invalid argument",
            ]):
                failed_detail = (
                    f"command failed: {msg} ({attempted[-1][-1] or 'error'}) — try creating a separate monitor interface via /api/iface/monitor_clone"
                )
                raise HTTPException(status_code=409, detail=failed_detail)
            failed_detail = f"command failed: {msg} ({attempted[-1][-1] or rc})"
            raise HTTPException(status_code=500, detail=failed_detail)

    return {"ok": True, "iface": _iface_info(dev)}

@app.post("/api/iface/monitor_clone", dependencies=[Depends(require_key)])
async def create_monitor_iface(request: Request):
    body = await request.json()
    if not isinstance(body, dict):
        body = {}
    base = body.get("dev") or (cfg.get("capture", {}) or {}).get("iface")
    new_name = body.get("name")
    ch = body.get("channel")
    make_default = bool(body.get("make_default", True))
    if not base:
        raise HTTPException(status_code=400, detail="dev required")

    # Propose a name if not given
    if not new_name:
        candidates = [f"{base}mon", f"{base}mon0", f"{base}mon1"]
        existing = {i.get("name") for i in _parse_iw_dev_list(_run(["iw", "dev"])[1])}
        new_name = next((c for c in candidates if c not in existing), f"{base}mon")

    # Create monitor interface
    rc, _, err = _sudo(["iw", "dev", base, "interface", "add", new_name, "type", "monitor"])
    if rc != 0:
        raise HTTPException(status_code=500, detail=f"failed to add monitor interface: {err or rc}")
    # Set channel if provided (best-effort)
    if ch:
        _sudo(["iw", "dev", new_name, "set", "channel", str(int(ch))])
    # Bring up
    rc, _, err = _sudo(["ip", "link", "set", new_name, "up"])
    if rc != 0:
        raise HTTPException(status_code=500, detail=f"failed to bring up {new_name}: {err or rc}")

    # Optionally set as capture.iface and persist
    if make_default:
        cfg.setdefault("capture", {})["iface"] = new_name
        try:
            p = pathlib.Path(cfg_path)
            doc = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
            doc.setdefault("capture", {})
            doc["capture"]["iface"] = new_name
            p.write_text(yaml.safe_dump(doc, sort_keys=False), encoding="utf-8")
        except Exception:
            pass

    return {"ok": True, "iface": _iface_info(new_name), "capture": cfg.get("capture", {})}

@app.post("/api/iface/channel", dependencies=[Depends(require_key)])
async def set_channel(request: Request):
    body = await request.json()
    dev = (body or {}).get("dev") or (cfg.get("capture", {}) or {}).get("iface")
    ch = (body or {}).get("channel")
    if not dev or not ch:
        raise HTTPException(status_code=400, detail="dev and channel required")
    ch = int(ch)
    # First try set channel
    rc, out, err = _sudo(["iw", "dev", dev, "set", "channel", str(ch)])
    attempted = [["iw", "dev", dev, "set", "channel", str(ch), f"rc={rc}", err or ""]]
    # Fallbacks: set freq for 2.4/5/6 GHz
    if rc != 0:
        candidates = []
        try:
            candidates.append(2407 + 5 * ch)  # 2.4 GHz
            candidates.append(5000 + 5 * ch)  # 5 GHz
            candidates.append(5955 + (ch - 1) * 5)  # 6 GHz
        except Exception:
            candidates = []
        for f in candidates:
            rc2, out2, err2 = _sudo(["iw", "dev", dev, "set", "freq", str(int(f))])
            attempted.append(["iw", "dev", dev, "set", "freq", str(int(f)), f"rc={rc2}", err2 or ""])
            if rc2 == 0:
                rc, _, err = rc2, out2, err2
                break
    if rc != 0:
        detail = "; ".join([" ".join(x) for x in attempted])
        _api_log("error", f"iface channel change failed dev={dev} ch={ch}: {detail}")
        raise HTTPException(status_code=500, detail=f"failed to set channel: {detail}")
    _api_log("info", f"iface channel set dev={dev} ch={ch}")
    return {"ok": True, "iface": _iface_info(dev)}

# Removed: sniffer restart endpoint

def main(config_path: str):
    global cfg, engine, cfg_path
    cfg_path = config_path
    cfg = load_config(config_path)
    engine = get_engine(cfg["database"]["path"])
    init_db(engine)
    ensure_schema(engine)

    # ensure indexes
    with session(engine) as db:
        db.exec(text("CREATE INDEX IF NOT EXISTS idx_events_ts ON event(ts);"))
        db.exec(text("CREATE INDEX IF NOT EXISTS idx_events_type_ts ON event(type, ts);"))
        db.commit()

    # serve built UI if present (repo root/ui/dist)
    # __file__ = <repo>/src/wids/service/api.py; repo root is parents[3]
    dist = pathlib.Path(__file__).resolve().parents[3] / "ui" / "dist"
    if dist.exists():
        app.mount("/", StaticFiles(directory=str(dist), html=True), name="ui")
        try:
            _api_log("info", f"ui mounted from {dist}")
        except Exception:
            pass
    else:
        try:
            _api_log("warn", f"ui not found at {dist}; serving API only")
        except Exception:
            pass

    uvicorn.run(app, host=cfg["api"]["bind_host"], port=cfg["api"]["bind_port"])

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    args = ap.parse_args()
    main(args.config)
