from sqlmodel import SQLModel, Field, create_engine, Session
from typing import Optional
from datetime import datetime
import pathlib, os
from sqlalchemy import text
from sqlalchemy.exc import OperationalError

class Event(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    ts: datetime
    type: str
    band: str
    chan: int
    src: Optional[str] = None
    dst: Optional[str] = None
    bssid: Optional[str] = None
    ssid: Optional[str] = None
    rssi: Optional[int] = None
    # Optional RSN info captured from beacons (comma-separated selector strings)
    rsn_akms: Optional[str] = None
    rsn_ciphers: Optional[str] = None

class Alert(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    ts: datetime
    severity: str     # "info" | "warn" | "critical"
    kind: str         # e.g., "deauth_flood"
    summary: str
    acknowledged: bool = False

class Log(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    ts: datetime
    source: str   # e.g., 'sniffer' | 'sensor' | 'api'
    level: str    # e.g., 'info' | 'warn' | 'error'
    message: str

def get_engine(db_path: str):
    """Return a SQLAlchemy engine for SQLite and ensure its directory exists.

    - Expands ~ and environment variables in db_path.
    - Creates parent directory if missing.
    - Raises a clear error if the directory cannot be created or opened.
    """
    # Expand user and env vars
    db_path = os.path.expandvars(os.path.expanduser(str(db_path)))
    p = pathlib.Path(db_path)
    # Ensure parent directory exists
    try:
        if p.parent and not p.parent.exists():
            p.parent.mkdir(parents=True, exist_ok=True)
    except PermissionError as e:
        raise RuntimeError(
            f"Cannot create database directory '{p.parent}'. Set database.path to a writable location (e.g., /var/lib/piguard/db.sqlite) "
            f"or pre-create the directory with proper ownership. Original error: {e}"
        )
    except Exception as e:
        # Non-fatal if it already exists or will be writable; continue, but surface unexpected issues.
        if not p.parent.exists():
            raise RuntimeError(f"Failed to prepare database directory '{p.parent}': {e}")

    eng = create_engine(f"sqlite:///{p}", connect_args={"check_same_thread": False})
    # Proactively test connectivity to force early, clear errors and create the file when possible
    try:
        with eng.connect() as _:
            pass
    except OperationalError as e:
        raise RuntimeError(
            f"Unable to open SQLite database file at '{p}'. Ensure the directory exists and is writable by the process. Original error: {e}"
        )
    return eng

def init_db(engine):
    """Create tables if they do not exist."""
    SQLModel.metadata.create_all(engine)

def ensure_schema(engine):
    """Lightweight migration to add new columns if missing."""
    with Session(engine) as s:
        cols = set()
        try:
            rows = s.exec(text("PRAGMA table_info(event)")).all()
            cols = {r[1] for r in rows}
        except Exception:
            pass
        alters = []
        if "rsn_akms" not in cols:
            alters.append("ALTER TABLE event ADD COLUMN rsn_akms TEXT NULL;")
        if "rsn_ciphers" not in cols:
            alters.append("ALTER TABLE event ADD COLUMN rsn_ciphers TEXT NULL;")
        for stmt in alters:
            try:
                s.exec(text(stmt))
            except Exception:
                pass
        s.commit()

def session(engine):
    return Session(engine)
