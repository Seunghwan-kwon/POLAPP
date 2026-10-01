import io
import json
import tempfile
import unittest
from pathlib import Path

from app import create_app


class LocalBackendTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        database_path = str(Path(self.temp_dir.name) / "test.db")
        self.app, self.socketio = create_app(
            {
                "TESTING": True,
                "DATABASE": database_path,
                "SECRET_KEY": "test-session-secret",
                "JWT_SECRET": "test-jwt-secret",
            }
        )
        self.client = self.app.test_client()

    def tearDown(self):
        self.temp_dir.cleanup()

    def login(self, officer_id: str, matching_code: str):
        return self.client.post(
            "/login",
            json={"officerId": officer_id, "matchingCode": matching_code},
        )

    def test_login_and_report_lifecycle(self):
        response = self.login("ADMIN-001", "13579")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["role"], "ADMIN")

        response = self.client.post(
            "/reports",
            json={
                "title": "Local report",
                "description": "Created by automated test",
                "severity": "HIGH",
                "latitude": 37.654,
                "longitude": 127.056,
            },
        )
        self.assertEqual(response.status_code, 201)
        report = response.get_json()["result"]
        self.assertEqual(report["latitude"], 37.654)
        self.assertEqual(report["longitude"], 127.056)

        response = self.client.patch(f"/reports/{report['id']}/close")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["result"]["status"], "CLOSED")

    def test_mobile_token_and_idempotent_threat_alert(self):
        login = self.login("P-1001", "11111").get_json()
        token = login["token"]
        headers = {"Authorization": f"Bearer {token}"}
        admin_socket = self.socketio.test_client(self.app)
        officer_socket = self.socketio.test_client(self.app)
        admin_socket.emit("join", {"officerId": "ADMIN-001"})
        officer_socket.emit("join", {"officerId": "P-1001"})
        officer_socket.emit(
            "sendMyLocation",
            {"latitude": 37.655, "longitude": 127.061},
        )
        admin_socket.get_received()
        payload = {
            "eventId": "guardian-test-7",
            "sessionId": "guardian-test",
            "category": "weapon",
            "alertLabel": "흉기",
            "riskLevel": 4,
            "evidenceIndex": 91.4,
            "reasons": ["문맥 분류 모델: 흉기 감지"],
            "occurredAt": "2026-09-08T12:00:00+09:00",
        }

        first = self.client.post("/threat-alerts", json=payload, headers=headers)
        duplicate = self.client.post("/threat-alerts", json=payload, headers=headers)
        self.assertEqual(first.status_code, 201)
        self.assertEqual(duplicate.status_code, 200)
        self.assertTrue(first.get_json()["created"])
        self.assertFalse(duplicate.get_json()["created"])
        events = admin_socket.get_received()
        threat = next(event for event in events if event["name"] == "threatDetected")
        self.assertEqual(threat["args"][0]["alertLabel"], "흉기")

        admin_login = self.login("ADMIN-001", "13579")
        self.assertEqual(admin_login.status_code, 200)
        alerts = self.client.get("/threat-alerts").get_json()["result"]
        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0]["officerId"], "P-1001")
        self.assertEqual(alerts[0]["latitude"], 37.655)
        self.assertEqual(alerts[0]["longitude"], 127.061)
        self.assertNotIn("transcript", alerts[0])

    def test_browser_preflight_allows_credentials(self):
        response = self.client.options(
            "/reports",
            headers={"Origin": "http://localhost:52123"},
        )
        self.assertEqual(response.status_code, 204)
        self.assertEqual(
            response.headers["Access-Control-Allow-Origin"],
            "http://localhost:52123",
        )
        self.assertEqual(response.headers["Access-Control-Allow-Credentials"], "true")

    def test_authenticated_camera_frame_is_visible_to_admin(self):
        mobile_login = self.login("P-1001", "11111").get_json()
        mobile_headers = {"Authorization": f"Bearer {mobile_login['token']}"}
        frame = b"\xff\xd8\xff\xe0test-jpeg\xff\xd9"
        response = self.client.post(
            "/camera-stream/frame",
            headers=mobile_headers,
            data={
                "sessionId": "camera-test",
                "detections": json.dumps(
                    [{"label": "knife", "score": 0.82, "box": [0.1, 0.2, 0.5, 0.8]}]
                ),
                "frame": (io.BytesIO(frame), "frame.jpg"),
            },
            content_type="multipart/form-data",
        )
        self.assertEqual(response.status_code, 202)

        admin_login = self.login("ADMIN-001", "13579")
        self.assertEqual(admin_login.status_code, 200)
        streams = self.client.get("/camera-streams").get_json()["result"]
        self.assertEqual(len(streams), 1)
        self.assertEqual(streams[0]["officerId"], "P-1001")
        self.assertEqual(streams[0]["detections"][0]["label"], "knife")
        fetched_frame = self.client.get("/camera-streams/P-1001/frame")
        self.assertEqual(fetched_frame.status_code, 200)
        self.assertEqual(fetched_frame.data, frame)
        self.assertEqual(fetched_frame.mimetype, "image/jpeg")

        with self.client.session_transaction() as browser_session:
            browser_session.clear()
        stopped = self.client.post(
            "/camera-stream/status",
            headers=mobile_headers,
            json={"enabled": False, "sessionId": "camera-test"},
        )
        self.assertEqual(stopped.status_code, 200)
        self.assertEqual(self.login("ADMIN-001", "13579").status_code, 200)
        self.assertEqual(self.client.get("/camera-streams").get_json()["result"], [])

    def test_socket_location_and_radio_message(self):
        admin = self.socketio.test_client(self.app)
        officer = self.socketio.test_client(self.app)
        admin.emit("join", {"officerId": "ADMIN-001"})
        officer.emit("join", {"officerId": "P-1001"})
        admin.get_received()
        officer.get_received()

        officer.emit(
            "sendMyLocation",
            {"officerId": "spoofed", "latitude": 37.655, "longitude": 127.061},
        )
        admin_events = admin.get_received()
        location = next(event for event in admin_events if event["name"] == "updateColleagueLocation")
        self.assertEqual(location["args"][0]["officerId"], "P-1001")

        admin.emit(
            "sendRadioMessage",
            {"officerId": "ADMIN-001", "region": "ALL", "message": "상황 확인"},
        )
        officer_events = officer.get_received()
        radio = next(event for event in officer_events if event["name"] == "receiveRadioMessage")
        self.assertEqual(radio["args"][0]["message"], "상황 확인")


if __name__ == "__main__":
    unittest.main()
