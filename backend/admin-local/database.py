import json
import sqlite3
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from auth import hash_matching_code


SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS officers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE,
    matching_code_hash TEXT NOT NULL,
    name TEXT NOT NULL,
    rank TEXT NOT NULL,
    region TEXT NOT NULL,
    affiliation TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('ADMIN', 'USER')),
    is_active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS officer_locations (
    officer_id INTEGER PRIMARY KEY,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(officer_id) REFERENCES officers(id)
);

CREATE TABLE IF NOT EXISTS reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    severity TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'OPEN' CHECK(status IN ('OPEN', 'CLOSED')),
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    created_by INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    closed_by INTEGER,
    closed_at TEXT,
    FOREIGN KEY(created_by) REFERENCES officers(id),
    FOREIGN KEY(closed_by) REFERENCES officers(id)
);

CREATE TABLE IF NOT EXISTS radio_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    officer_id INTEGER NOT NULL,
    region TEXT NOT NULL,
    message TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(officer_id) REFERENCES officers(id)
);

CREATE TABLE IF NOT EXISTS threat_alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE,
    officer_id INTEGER NOT NULL,
    session_id TEXT,
    category TEXT NOT NULL,
    alert_label TEXT NOT NULL,
    risk_level INTEGER NOT NULL CHECK(risk_level BETWEEN 1 AND 4),
    evidence_index REAL NOT NULL DEFAULT 0,
    reasons_json TEXT NOT NULL DEFAULT '[]',
    latitude REAL,
    longitude REAL,
    occurred_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(officer_id) REFERENCES officers(id)
);
"""


TEST_ACCOUNTS = (
    {
        "code": "ADMIN-001",
        "matching_code": "13579",
        "name": "김관리",
        "rank": "경감",
        "region": "ALL",
        "affiliation": "종합상황실",
        "role": "ADMIN",
    },
    {
        "code": "P-1001",
        "matching_code": "11111",
        "name": "이현장",
        "rank": "순경",
        "region": "SEOUL_NOWON",
        "affiliation": "노원경찰서",
        "role": "USER",
    },
    {
        "code": "P-1002",
        "matching_code": "22222",
        "name": "박순찰",
        "rank": "경장",
        "region": "SEOUL_DOBONG",
        "affiliation": "도봉경찰서",
        "role": "USER",
    },
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class Database:
    def __init__(self, path: str | Path):
        self.path = Path(path).resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._write_lock = threading.RLock()

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    @contextmanager
    def session(self) -> Iterator[sqlite3.Connection]:
        connection = self.connect()
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def initialize(self) -> None:
        with self._write_lock, self.session() as connection:
            connection.executescript(SCHEMA)
            for account in TEST_ACCOUNTS:
                exists = connection.execute(
                    "SELECT 1 FROM officers WHERE code = ?",
                    (account["code"],),
                ).fetchone()
                if exists:
                    continue
                connection.execute(
                    """
                    INSERT INTO officers (
                        code, matching_code_hash, name, rank, region,
                        affiliation, role
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        account["code"],
                        hash_matching_code(account["matching_code"]),
                        account["name"],
                        account["rank"],
                        account["region"],
                        account["affiliation"],
                        account["role"],
                    ),
                )

    def one(self, sql: str, params: tuple[Any, ...] = ()) -> dict[str, Any] | None:
        with self.session() as connection:
            row = connection.execute(sql, params).fetchone()
        return dict(row) if row else None

    def all(self, sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
        with self.session() as connection:
            rows = connection.execute(sql, params).fetchall()
        return [dict(row) for row in rows]

    def execute(self, sql: str, params: tuple[Any, ...] = ()) -> int:
        with self._write_lock, self.session() as connection:
            cursor = connection.execute(sql, params)
            return int(cursor.lastrowid)

    def officer_by_code(self, code: str) -> dict[str, Any] | None:
        return self.one(
            "SELECT * FROM officers WHERE code = ? AND is_active = 1",
            (code,),
        )

    def officer_by_id(self, officer_id: int) -> dict[str, Any] | None:
        return self.one(
            "SELECT * FROM officers WHERE id = ? AND is_active = 1",
            (officer_id,),
        )

    def upsert_location(self, officer_id: int, latitude: float, longitude: float) -> None:
        with self._write_lock, self.session() as connection:
            connection.execute(
                """
                INSERT INTO officer_locations (officer_id, latitude, longitude, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(officer_id) DO UPDATE SET
                    latitude = excluded.latitude,
                    longitude = excluded.longitude,
                    updated_at = excluded.updated_at
                """,
                (officer_id, latitude, longitude, utc_now()),
            )

    def location_for(self, officer_id: int) -> dict[str, Any] | None:
        return self.one(
            "SELECT latitude, longitude, updated_at FROM officer_locations WHERE officer_id = ?",
            (officer_id,),
        )

    def locations(self) -> list[dict[str, Any]]:
        return self.all(
            """
            SELECT o.code AS officer_code, o.name AS officer_name,
                   o.rank AS officer_rank, o.region AS officer_region,
                   o.affiliation AS officer_affiliation,
                   l.latitude, l.longitude, l.updated_at
            FROM officer_locations l
            JOIN officers o ON o.id = l.officer_id
            WHERE o.is_active = 1
            ORDER BY l.updated_at DESC
            """
        )

    def create_report(
        self,
        *,
        title: str,
        description: str,
        severity: str,
        latitude: float,
        longitude: float,
        created_by: int,
    ) -> dict[str, Any]:
        report_id = self.execute(
            """
            INSERT INTO reports (
                title, description, severity, latitude, longitude,
                created_by, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                title,
                description,
                severity,
                latitude,
                longitude,
                created_by,
                utc_now(),
            ),
        )
        return self.one("SELECT * FROM reports WHERE id = ?", (report_id,)) or {}

    def reports(self, status: str = "ALL") -> list[dict[str, Any]]:
        if status == "ALL":
            return self.all("SELECT * FROM reports ORDER BY created_at DESC")
        return self.all(
            "SELECT * FROM reports WHERE status = ? ORDER BY created_at DESC",
            (status,),
        )

    def close_report(self, report_id: int, closed_by: int) -> dict[str, Any] | None:
        with self._write_lock, self.session() as connection:
            cursor = connection.execute(
                """
                UPDATE reports
                SET status = 'CLOSED', closed_by = ?, closed_at = ?
                WHERE id = ? AND status = 'OPEN'
                """,
                (closed_by, utc_now(), report_id),
            )
            if cursor.rowcount == 0:
                return None
            row = connection.execute(
                "SELECT * FROM reports WHERE id = ?",
                (report_id,),
            ).fetchone()
        return dict(row) if row else None

    def save_radio_message(self, officer_id: int, region: str, message: str) -> int:
        return self.execute(
            """
            INSERT INTO radio_messages (officer_id, region, message, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (officer_id, region, message, utc_now()),
        )

    def threat_by_event_id(self, event_id: str) -> dict[str, Any] | None:
        return self._threat_row("WHERE t.event_id = ?", (event_id,))

    def save_threat_alert(
        self,
        *,
        event_id: str,
        officer_id: int,
        session_id: str | None,
        category: str,
        alert_label: str,
        risk_level: int,
        evidence_index: float,
        reasons: list[str],
        latitude: float | None,
        longitude: float | None,
        occurred_at: str,
    ) -> tuple[dict[str, Any], bool]:
        existing = self.threat_by_event_id(event_id)
        if existing:
            return existing, False

        try:
            alert_id = self.execute(
                """
                INSERT INTO threat_alerts (
                    event_id, officer_id, session_id, category, alert_label,
                    risk_level, evidence_index, reasons_json, latitude,
                    longitude, occurred_at, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    event_id,
                    officer_id,
                    session_id,
                    category,
                    alert_label,
                    risk_level,
                    evidence_index,
                    json.dumps(reasons, ensure_ascii=False),
                    latitude,
                    longitude,
                    occurred_at,
                    utc_now(),
                ),
            )
        except sqlite3.IntegrityError:
            duplicate = self.threat_by_event_id(event_id)
            if duplicate:
                return duplicate, False
            raise

        created = self._threat_row("WHERE t.id = ?", (alert_id,))
        if not created:
            raise RuntimeError("Threat alert was inserted but could not be read")
        return created, True

    def threats(self, limit: int = 50) -> list[dict[str, Any]]:
        return self._threat_rows(
            "ORDER BY t.created_at DESC LIMIT ?",
            (limit,),
        )

    def _threat_row(
        self,
        suffix: str,
        params: tuple[Any, ...],
    ) -> dict[str, Any] | None:
        rows = self._threat_rows(suffix, params)
        return rows[0] if rows else None

    def _threat_rows(
        self,
        suffix: str,
        params: tuple[Any, ...],
    ) -> list[dict[str, Any]]:
        return self.all(
            f"""
            SELECT t.*, o.code AS officer_code, o.name AS officer_name,
                   o.rank AS officer_rank, o.region AS officer_region
            FROM threat_alerts t
            JOIN officers o ON o.id = t.officer_id
            {suffix}
            """,
            params,
        )

    def report_payload(self, row: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": row["id"],
            "title": row["title"],
            "description": row["description"],
            "severity": row["severity"],
            "status": row["status"],
            "latitude": row["latitude"],
            "longitude": row["longitude"],
            "createdBy": row["created_by"],
            "createdAt": row["created_at"],
            "closedBy": row["closed_by"],
            "closedAt": row["closed_at"],
        }

    def threat_payload(self, row: dict[str, Any]) -> dict[str, Any]:
        reasons = json.loads(row.get("reasons_json") or "[]")
        return {
            "id": row["id"],
            "eventId": row["event_id"],
            "sessionId": row["session_id"],
            "officerId": row["officer_code"],
            "officerName": row["officer_name"],
            "rank": row["officer_rank"],
            "region": row["officer_region"],
            "category": row["category"],
            "alertLabel": row["alert_label"],
            "riskLevel": row["risk_level"],
            "evidenceIndex": row["evidence_index"],
            "reasons": reasons,
            "latitude": row["latitude"],
            "longitude": row["longitude"],
            "occurredAt": row["occurred_at"],
            "createdAt": row["created_at"],
        }
