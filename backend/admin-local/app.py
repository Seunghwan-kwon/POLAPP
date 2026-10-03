import json
import os
import threading
import time
from functools import wraps
from pathlib import Path
from typing import Any, Callable, TypeVar, cast

from flask import Flask, Response, jsonify, request, session
from flask_socketio import SocketIO, emit, join_room
from dotenv import load_dotenv

from auth import decode_token, development_secret, issue_token, verify_matching_code
from database import Database, utc_now


Handler = TypeVar("Handler", bound=Callable[..., Any])
VALID_SEVERITIES = {"LOW", "MEDIUM", "HIGH", "URGENT"}
VALID_REPORT_STATUSES = {"ALL", "OPEN", "CLOSED"}

load_dotenv(Path(__file__).resolve().with_name(".env"))


def create_app(test_config: dict[str, Any] | None = None) -> tuple[Flask, SocketIO]:
    root = Path(__file__).resolve().parent
    app = Flask(__name__)
    app.config.update(
        SECRET_KEY=development_secret("SESSION_SECRET"),
        JWT_SECRET=development_secret("JWT_SECRET"),
        DATABASE=os.environ.get("DATABASE_PATH", str(root / "data" / "polapp_local.db")),
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        SESSION_COOKIE_SECURE=False,
        JSON_AS_ASCII=False,
        TESTING=False,
    )
    if test_config:
        app.config.update(test_config)

    database = Database(app.config["DATABASE"])
    database.initialize()
    app.extensions["polapp_database"] = database

    allowed_origins = _allowed_origins()
    socketio = SocketIO(
        app,
        async_mode="threading",
        cors_allowed_origins=allowed_origins,
        logger=False,
        engineio_logger=False,
    )
    connected_officers: dict[str, dict[str, Any]] = {}
    # 영상 원본은 저장하지 않고 관제 화면에 필요한 최신 프레임만 잠시 보관합니다.
    camera_streams: dict[str, dict[str, Any]] = {}
    camera_stream_lock = threading.RLock()
    camera_stream_timeout_seconds = 8.0

    @app.before_request
    def handle_preflight():
        if request.method == "OPTIONS":
            return ("", 204)
        return None

    @app.after_request
    def add_local_cors_headers(response):
        origin = request.headers.get("Origin")
        if origin and _origin_allowed(origin, allowed_origins):
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Vary"] = "Origin"
            response.headers["Access-Control-Allow-Credentials"] = "true"
            response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
            response.headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, OPTIONS"
        return response

    @app.route("/", methods=["GET"])
    def index():
        return jsonify(
            {
                "service": "POLAPP local administration backend",
                "status": "ok",
                "health": "/health",
            }
        )

    @app.route("/health", methods=["GET"])
    def health():
        return jsonify({"status": "ok", "database": "sqlite", "socketIo": True})

    @app.route("/info", methods=["GET"])
    def info():
        return jsonify(
            {
                "mode": "local-development",
                "features": [
                    "login",
                    "reports",
                    "live-location",
                    "radio-message",
                    "threat-alert",
                    "live-camera",
                ],
            }
        )

    @app.route("/login", methods=["POST", "OPTIONS"])
    def login():
        if request.method == "OPTIONS":
            return ("", 204)
        body = _json_object()
        officer_code = str(body.get("officerId", "")).strip()
        matching_code = str(body.get("matchingCode", "")).strip()
        officer = database.officer_by_code(officer_code)

        if not officer or not verify_matching_code(
            matching_code,
            officer["matching_code_hash"],
        ):
            return jsonify({"code": 401, "message": "Invalid officer ID or matching code"}), 401

        session.clear()
        session["officer_db_id"] = officer["id"]
        token = issue_token(officer, app.config["JWT_SECRET"])
        return jsonify(
            {
                "code": 0,
                "message": "Login successful",
                "token": token,
                "officerId": officer["code"],
                "name": officer["name"],
                "rank": officer["rank"],
                "region": officer["region"],
                "affiliation": officer["affiliation"],
                "role": officer["role"],
            }
        )

    def current_officer() -> dict[str, Any] | None:
        session_id = session.get("officer_db_id")
        if isinstance(session_id, int):
            officer = database.officer_by_id(session_id)
            if officer:
                return officer

        authorization = request.headers.get("Authorization", "")
        if not authorization.startswith("Bearer "):
            return None
        claims = decode_token(authorization[7:].strip(), app.config["JWT_SECRET"])
        if not claims:
            return None
        try:
            return database.officer_by_id(int(claims["sub"]))
        except (KeyError, TypeError, ValueError):
            return None

    def require_auth(*, admin: bool = False):
        def decorate(handler: Handler) -> Handler:
            @wraps(handler)
            def wrapped(*args, **kwargs):
                officer = current_officer()
                if not officer:
                    return jsonify({"code": 401, "message": "Authentication required"}), 401
                if admin and officer["role"] != "ADMIN":
                    return jsonify({"code": 403, "message": "Administrator access required"}), 403
                return handler(officer, *args, **kwargs)

            return cast(Handler, wrapped)

        return decorate

    @app.route("/reports", methods=["GET"])
    @require_auth()
    def list_reports(_officer: dict[str, Any]):
        status = request.args.get("status", "ALL").upper()
        if status not in VALID_REPORT_STATUSES:
            return jsonify({"code": 400, "message": "Invalid report status"}), 400
        result = [database.report_payload(row) for row in database.reports(status)]
        return jsonify({"code": 0, "result": result})

    @app.route("/reports", methods=["POST", "OPTIONS"])
    @require_auth(admin=True)
    def create_report(officer: dict[str, Any]):
        if request.method == "OPTIONS":
            return ("", 204)
        body = _json_object()
        title = str(body.get("title", "")).strip()
        description = str(body.get("description", "")).strip()
        severity = str(body.get("severity", "LOW")).upper()
        try:
            latitude = float(body["latitude"])
            longitude = float(body["longitude"])
        except (KeyError, TypeError, ValueError):
            return jsonify({"code": 400, "message": "Valid coordinates are required"}), 400

        if not title or not description or severity not in VALID_SEVERITIES:
            return jsonify({"code": 400, "message": "Invalid report payload"}), 400
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            return jsonify({"code": 400, "message": "Coordinates are out of range"}), 400

        report = database.report_payload(
            database.create_report(
                title=title,
                description=description,
                severity=severity,
                latitude=latitude,
                longitude=longitude,
                created_by=officer["id"],
            )
        )
        socketio.emit("reportCreated", report, to="role:USER")
        socketio.emit("reportCreated", report, to="role:ADMIN")
        return jsonify({"code": 0, "result": report}), 201

    @app.route("/reports/<int:report_id>/close", methods=["PATCH", "OPTIONS"])
    @require_auth(admin=True)
    def close_report(officer: dict[str, Any], report_id: int):
        if request.method == "OPTIONS":
            return ("", 204)
        row = database.close_report(report_id, officer["id"])
        if not row:
            return jsonify({"code": 404, "message": "Open report not found"}), 404
        report = database.report_payload(row)
        socketio.emit("reportClosed", report, to="role:USER")
        socketio.emit("reportClosed", report, to="role:ADMIN")
        return jsonify({"code": 0, "result": report})

    @app.route("/threat-alerts", methods=["POST", "OPTIONS"])
    @require_auth()
    def create_threat_alert(officer: dict[str, Any]):
        if request.method == "OPTIONS":
            return ("", 204)
        body = _json_object()
        event_id = str(body.get("eventId", "")).strip()[:200]
        category = str(body.get("category", "unknown")).strip()[:80]
        alert_label = str(body.get("alertLabel", "위협")).strip()[:80]
        session_id = str(body.get("sessionId", "")).strip()[:120] or None
        occurred_at = str(body.get("occurredAt", "")).strip()[:80] or utc_now()
        raw_reasons = body.get("reasons", [])
        reasons = (
            [str(value)[:240] for value in raw_reasons if str(value).strip()][:8]
            if isinstance(raw_reasons, list)
            else []
        )
        try:
            risk_level = int(body.get("riskLevel", 1))
            evidence_index = float(body.get("evidenceIndex", 0))
        except (TypeError, ValueError):
            return jsonify({"code": 400, "message": "Invalid risk values"}), 400
        if not event_id or risk_level not in range(1, 5):
            return jsonify({"code": 400, "message": "Invalid threat alert payload"}), 400

        location = database.location_for(officer["id"]) or {}
        latitude = _optional_float(body.get("latitude", location.get("latitude")))
        longitude = _optional_float(body.get("longitude", location.get("longitude")))
        # 앱 재전송 시에도 event_id가 같으면 관제 알림을 중복 생성하지 않습니다.
        row, created = database.save_threat_alert(
            event_id=event_id,
            officer_id=officer["id"],
            session_id=session_id,
            category=category or "unknown",
            alert_label=alert_label or "위협",
            risk_level=risk_level,
            evidence_index=max(0.0, min(100.0, evidence_index)),
            reasons=reasons,
            latitude=latitude,
            longitude=longitude,
            occurred_at=occurred_at,
        )
        payload = database.threat_payload(row)
        if created:
            socketio.emit("threatDetected", payload, to="role:ADMIN")
        return jsonify({"code": 0, "result": payload, "created": created}), 201 if created else 200

    @app.route("/threat-alerts", methods=["GET"])
    @require_auth(admin=True)
    def list_threat_alerts(_officer: dict[str, Any]):
        try:
            limit = max(1, min(200, int(request.args.get("limit", "50"))))
        except ValueError:
            return jsonify({"code": 400, "message": "Invalid limit"}), 400
        result = [database.threat_payload(row) for row in database.threats(limit)]
        return jsonify({"code": 0, "result": result})

    def camera_stream_payload(stream: dict[str, Any]) -> dict[str, Any]:
        return {
            "officerId": stream["officerId"],
            "officerName": stream["officerName"],
            "rank": stream["rank"],
            "region": stream["region"],
            "sessionId": stream["sessionId"],
            "updatedAt": stream["updatedAt"],
            "detections": stream["detections"],
        }

    def prune_camera_streams() -> None:
        now = time.monotonic()
        stale = [
            officer_code
            for officer_code, stream in camera_streams.items()
            if now - float(stream["lastSeen"]) > camera_stream_timeout_seconds
        ]
        for officer_code in stale:
            camera_streams.pop(officer_code, None)

    @app.route("/camera-stream/status", methods=["POST", "OPTIONS"])
    @require_auth()
    def update_camera_stream_status(officer: dict[str, Any]):
        if request.method == "OPTIONS":
            return ("", 204)
        body = _json_object()
        enabled = body.get("enabled") is True
        session_id = str(body.get("sessionId", "")).strip()[:120]
        if not session_id:
            return jsonify({"code": 400, "message": "Camera session is required"}), 400

        with camera_stream_lock:
            if enabled:
                previous = camera_streams.get(officer["code"], {})
                camera_streams[officer["code"]] = {
                    "officerId": officer["code"],
                    "officerName": officer["name"],
                    "rank": officer["rank"],
                    "region": officer["region"],
                    "sessionId": session_id,
                    "updatedAt": utc_now(),
                    "lastSeen": time.monotonic(),
                    "detections": previous.get("detections", []),
                    "frame": previous.get("frame"),
                }
                payload = camera_stream_payload(camera_streams[officer["code"]])
                event_name = "cameraStreamUpdated"
            else:
                camera_streams.pop(officer["code"], None)
                payload = {"officerId": officer["code"], "sessionId": session_id}
                event_name = "cameraStreamStopped"

        socketio.emit(event_name, payload, to="role:ADMIN")
        return jsonify({"code": 0, "result": payload})

    @app.route("/camera-stream/frame", methods=["POST", "OPTIONS"])
    @require_auth()
    def upload_camera_frame(officer: dict[str, Any]):
        if request.method == "OPTIONS":
            return ("", 204)
        frame_file = request.files.get("frame")
        session_id = str(request.form.get("sessionId", "")).strip()[:120]
        if frame_file is None or not session_id:
            return jsonify({"code": 400, "message": "Camera frame and session are required"}), 400
        frame = frame_file.read(700_001)
        if len(frame) > 700_000:
            return jsonify({"code": 413, "message": "Camera frame is too large"}), 413
        if len(frame) < 4 or not frame.startswith(b"\xff\xd8"):
            return jsonify({"code": 400, "message": "JPEG frame is required"}), 400

        try:
            raw_detections = json.loads(request.form.get("detections", "[]"))
        except json.JSONDecodeError:
            raw_detections = []
        detections = []
        if isinstance(raw_detections, list):
            for item in raw_detections[:8]:
                if not isinstance(item, dict):
                    continue
                label = str(item.get("label", ""))
                if label not in {"bottle", "knife"}:
                    continue
                try:
                    score = max(0.0, min(1.0, float(item.get("score", 0))))
                except (TypeError, ValueError):
                    score = 0.0
                box = item.get("box")
                try:
                    normalized_box = (
                        [max(0.0, min(1.0, float(value))) for value in box]
                        if isinstance(box, list) and len(box) == 4
                        else []
                    )
                except (TypeError, ValueError):
                    normalized_box = []
                detections.append(
                    {
                        "label": label,
                        "displayLabel": "칼" if label == "knife" else "병",
                        "score": score,
                        "box": normalized_box,
                    }
                )

        with camera_stream_lock:
            stream = {
                "officerId": officer["code"],
                "officerName": officer["name"],
                "rank": officer["rank"],
                "region": officer["region"],
                "sessionId": session_id,
                "updatedAt": utc_now(),
                "lastSeen": time.monotonic(),
                "detections": detections,
                "frame": frame,
            }
            camera_streams[officer["code"]] = stream
            payload = camera_stream_payload(stream)

        socketio.emit("cameraStreamUpdated", payload, to="role:ADMIN")
        return jsonify({"code": 0, "result": payload}), 202

    @app.route("/camera-streams", methods=["GET"])
    @require_auth(admin=True)
    def list_camera_streams(_officer: dict[str, Any]):
        with camera_stream_lock:
            prune_camera_streams()
            result = [
                camera_stream_payload(stream)
                for stream in camera_streams.values()
                if stream.get("frame") is not None
            ]
        result.sort(key=lambda item: item["updatedAt"], reverse=True)
        return jsonify({"code": 0, "result": result})

    @app.route("/camera-streams/<officer_code>/frame", methods=["GET"])
    @require_auth(admin=True)
    def get_camera_stream_frame(_officer: dict[str, Any], officer_code: str):
        with camera_stream_lock:
            prune_camera_streams()
            stream = camera_streams.get(officer_code)
            frame = stream.get("frame") if stream else None
        if not isinstance(frame, bytes):
            return jsonify({"code": 404, "message": "Active camera frame not found"}), 404
        return Response(
            frame,
            mimetype="image/jpeg",
            headers={
                "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
                "Pragma": "no-cache",
            },
        )

    @socketio.on("join")
    def handle_join(data):
        body = data if isinstance(data, dict) else {}
        officer = database.officer_by_code(str(body.get("officerId", "")).strip())
        if not officer:
            emit("serverError", {"message": "Unknown officer"})
            return

        connected_officers[request.sid] = officer
        join_room(f"role:{officer['role']}")
        if officer["role"] == "USER":
            join_room(f"region:{officer['region']}")

        emit(
            "joined",
            {
                "officerId": officer["code"],
                "role": officer["role"],
                "region": officer["region"],
            },
        )
        for row in database.locations():
            if officer["role"] == "ADMIN" or row["officer_region"] == officer["region"]:
                emit("updateColleagueLocation", _location_payload(row))

    @socketio.on("sendMyLocation")
    def handle_location(data):
        officer = connected_officers.get(request.sid)
        if not officer or officer["role"] != "USER" or not isinstance(data, dict):
            return
        try:
            latitude = float(data["latitude"])
            longitude = float(data["longitude"])
        except (KeyError, TypeError, ValueError):
            return
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            return

        database.upsert_location(officer["id"], latitude, longitude)
        payload = {
            "officerId": officer["code"],
            "name": officer["name"],
            "rank": officer["rank"],
            "region": officer["region"],
            "affiliation": officer["affiliation"],
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": utc_now(),
        }
        emit("updateColleagueLocation", payload, to=f"region:{officer['region']}", include_self=False)
        emit("updateColleagueLocation", payload, to="role:ADMIN")

    @socketio.on("sendRadioMessage")
    def handle_radio_message(data):
        officer = connected_officers.get(request.sid)
        if not officer or not isinstance(data, dict):
            return
        message = str(data.get("message", "")).strip()[:1000]
        if not message:
            return
        requested_region = str(data.get("region", "")).strip()
        region = requested_region if officer["role"] == "ADMIN" else officer["region"]
        if not region:
            region = officer["region"]

        database.save_radio_message(officer["id"], region, message)
        payload = {
            "officerId": officer["code"],
            "region": region,
            "message": message,
            "timestamp": utc_now(),
        }
        if region == "ALL":
            emit("receiveRadioMessage", payload, to="role:USER")
        else:
            emit("receiveRadioMessage", payload, to=f"region:{region}")
        emit("receiveRadioMessage", payload, to="role:ADMIN", include_self=False)

    @socketio.on("disconnect")
    def handle_disconnect():
        officer = connected_officers.pop(request.sid, None)
        if not officer or officer["role"] != "USER":
            return
        payload = {"officerId": officer["code"], "region": officer["region"]}
        emit("removeColleagueLocation", payload, to=f"region:{officer['region']}")
        emit("removeColleagueLocation", payload, to="role:ADMIN")

    return app, socketio


def _optional_float(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _json_object() -> dict[str, Any]:
    body = request.get_json(silent=True)
    return body if isinstance(body, dict) else {}


def _allowed_origins() -> str | list[str]:
    raw = os.environ.get("ALLOWED_ORIGINS", "*").strip()
    if not raw or raw == "*":
        return "*"
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def _origin_allowed(origin: str, allowed_origins: str | list[str]) -> bool:
    return allowed_origins == "*" or origin in allowed_origins


def _location_payload(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "officerId": row["officer_code"],
        "name": row["officer_name"],
        "rank": row["officer_rank"],
        "region": row["officer_region"],
        "affiliation": row["officer_affiliation"],
        "latitude": row["latitude"],
        "longitude": row["longitude"],
        "timestamp": row["updated_at"],
    }


app, socketio = create_app()


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "4440"))
    socketio.run(app, host=host, port=port, allow_unsafe_werkzeug=True)
