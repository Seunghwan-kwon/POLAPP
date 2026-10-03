import json
import os
import tempfile
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

import numpy as np
from dotenv import load_dotenv

from src.legal_rag import RoadTrafficLawRAG
from src.llm_client import LlmClient
from src.incident_report_drafter import IncidentReportDrafter
from src.evaluation_recorder import EvaluationRecorder
from src.report_audio_pipeline import transcribe_report_audio
from src.profanity_detector import ProfanityDetector
from src.risk_engine import RiskEngine
from src.transcribe import STTTranscriber


load_dotenv(Path(__file__).resolve().with_name(".env"))

HOST = "0.0.0.0"
PORT = 8765
MAX_UPLOAD_BYTES = 20 * 1024 * 1024
MAX_REPORT_UPLOAD_BYTES = 64 * 1024 * 1024
MAX_JSON_BYTES = 1024 * 1024
AI_SERVER_TOKEN = os.environ.get("AI_SERVER_TOKEN", "").strip()
AI_ALLOWED_ORIGIN = os.environ.get("AI_ALLOWED_ORIGIN", "*").strip()

_transcriber: STTTranscriber | None = None
_detector: ProfanityDetector | None = None
_legal_agent: RoadTrafficLawRAG | None = None
_report_drafter: IncidentReportDrafter | None = None
_risk_engine: RiskEngine | None = None
_evaluation_recorder: EvaluationRecorder | None = None


def _get_transcriber() -> STTTranscriber:
    global _transcriber
    if _transcriber is None:
        _transcriber = STTTranscriber(min_level=20.0)
    return _transcriber


def _get_detector() -> ProfanityDetector:
    global _detector
    if _detector is None:
        _detector = ProfanityDetector()
    return _detector


def _get_legal_agent() -> RoadTrafficLawRAG:
    global _legal_agent
    if _legal_agent is None:
        _legal_agent = RoadTrafficLawRAG()
    return _legal_agent


def _get_report_drafter() -> IncidentReportDrafter:
    global _report_drafter
    if _report_drafter is None:
        _report_drafter = IncidentReportDrafter()
    return _report_drafter


def _get_risk_engine() -> RiskEngine:
    global _risk_engine
    if _risk_engine is None:
        _risk_engine = RiskEngine()
    return _risk_engine


def _get_evaluation_recorder() -> EvaluationRecorder:
    global _evaluation_recorder
    if _evaluation_recorder is None:
        _evaluation_recorder = EvaluationRecorder()
    return _evaluation_recorder


def _health_payload() -> dict:
    components: dict[str, dict] = {}
    issues: list[str] = []

    try:
        transcriber = _get_transcriber()
        components["stt"] = {
            "available": True,
            "model": transcriber.model_size,
            "device": transcriber.device,
            "compute_type": transcriber.compute_type,
        }
    except Exception as exc:
        components["stt"] = {
            "available": False,
            "error": f"{type(exc).__name__}: {exc}",
        }
        issues.append("stt")

    try:
        risk = _get_risk_engine().capabilities()
        components["context_model"] = risk["context_model"]
        components["audio_event_model"] = risk["audio_event_model"]
        for name in ("context_model", "audio_event_model"):
            if not components[name].get("available", False):
                issues.append(name)
    except Exception as exc:
        components["risk_engine"] = {
            "available": False,
            "error": f"{type(exc).__name__}: {exc}",
        }
        issues.append("risk_engine")

    llm = LlmClient().status()
    components["llm"] = llm
    if not llm["available"]:
        issues.append("llm_optional")

    ready = not [name for name in issues if name != "llm_optional"]
    return {
        "status": "ok" if ready else "degraded",
        "ready": ready,
        "components": components,
        "issues": issues,
    }


def _read_wav_as_int16(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as wav_file:
        channels = wav_file.getnchannels()
        sample_width = wav_file.getsampwidth()
        sample_rate = wav_file.getframerate()
        frames = wav_file.getnframes()
        raw = wav_file.readframes(frames)

    if sample_width != 2:
        raise ValueError("Only 16-bit PCM WAV audio is supported.")

    audio = np.frombuffer(raw, dtype=np.int16)
    if channels > 1:
        audio = audio.reshape(-1, channels).mean(axis=1).astype(np.int16)
    return audio, sample_rate


def analyze_wav(path: Path, session_id: str) -> dict:
    audio, sample_rate = _read_wav_as_int16(path)
    text = _get_transcriber().transcribe(
        audio,
        context_id=session_id,
        profile="threat",
    )
    text = " ".join(text.strip().split())
    result = _get_detector().detect(text)
    risk = _get_risk_engine().assess(
        session_id=session_id,
        audio=audio,
        sample_rate=sample_rate,
        transcript=text,
        detection=result,
    )

    _get_evaluation_recorder().record(
        wav_path=path,
        session_id=session_id,
        transcript=text,
        detection=result,
        risk=risk,
    )

    return {
        "text": text,
        "is_threat": bool(result["is_profanity"] or risk["level"] >= 2),
        "is_profanity": bool(result["is_profanity"]),
        "score": result["score"],
        "matched": result["matched"],
        "category": result.get("category", "none"),
        "category_label": result.get("category_label", ""),
        "categories": result.get("categories", []),
        "risk": risk,
    }


def answer_legal_question(question: str) -> dict:
    question = " ".join(question.strip().split())
    if not question:
        raise ValueError("Question is empty.")
    return _get_legal_agent().answer(question)


def answer_legal_voice(path: Path) -> dict:
    audio, _ = _read_wav_as_int16(path)
    question = _get_transcriber().transcribe(audio, profile="legal")
    question = " ".join(question.strip().split())
    result = answer_legal_question(question)
    return {
        "question": question,
        "answer": result.get("answer", ""),
        "citations": result.get("citations", []),
        "used_model": bool(result.get("used_model", False)),
    }


def draft_report(
    transcript: str,
    *,
    segments: list[dict] | None = None,
    duration_seconds: float = 0.0,
) -> dict:
    transcript = " ".join(transcript.strip().split())
    result = _get_report_drafter().draft(transcript)
    return {
        "transcript": transcript,
        "segments": segments or [],
        "duration_seconds": duration_seconds,
        **result,
    }


def draft_report_voice(path: Path) -> dict:
    audio, sample_rate = _read_wav_as_int16(path)
    transcription = transcribe_report_audio(
        _get_transcriber(),
        audio,
        sample_rate,
    )
    return draft_report(
        transcription["transcript"],
        segments=transcription["segments"],
        duration_seconds=transcription["duration_seconds"],
    )


class AiRequestHandler(BaseHTTPRequestHandler):
    server_version = "POLAPP-AI/0.2"

    def _send_json(self, status_code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        if AI_ALLOWED_ORIGIN:
            self.send_header("Access-Control-Allow-Origin", AI_ALLOWED_ORIGIN)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, X-Guardian-Session, X-AI-Server-Token",
        )
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self._send_json(200, {"ok": True})

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/health":
            if not self._authorized():
                return
            self._send_json(200, _health_payload())
            return
        if not self._authorized():
            return
        if path == "/risk/capabilities":
            self._send_json(200, _get_risk_engine().capabilities())
            return
        self._send_json(404, {"error": "Not found"})

    def do_POST(self) -> None:
        if not self._authorized():
            return
        path = urlparse(self.path).path
        if path in {"/threat/analyze", "/profanity/analyze"}:
            self._handle_threat_analyze()
            return
        if path == "/legal/answer":
            self._handle_legal_answer()
            return
        if path == "/legal/voice-answer":
            self._handle_legal_voice_answer()
            return
        if path == "/report/draft":
            self._handle_report_draft()
            return
        if path == "/report/voice-draft":
            self._handle_report_voice_draft()
            return
        self._send_json(404, {"error": "Not found"})

    def _authorized(self) -> bool:
        if not AI_SERVER_TOKEN:
            return True
        if self.headers.get("X-AI-Server-Token", "") == AI_SERVER_TOKEN:
            return True
        self._send_json(401, {"error": "Unauthorized"})
        return False

    def _handle_threat_analyze(self) -> None:
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length <= 0:
            self._send_json(400, {"error": "Missing audio body"})
            return
        if content_length > MAX_UPLOAD_BYTES:
            self._send_json(413, {"error": "Audio body is too large"})
            return

        try:
            body = self.rfile.read(content_length)
            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as audio_file:
                audio_file.write(body)
                temp_path = Path(audio_file.name)

            try:
                session_id = self.headers.get("X-Guardian-Session", "").strip()
                if not session_id:
                    session_id = f"client-{self.client_address[0]}"
                result = analyze_wav(temp_path, session_id)
            finally:
                temp_path.unlink(missing_ok=True)

            self._send_json(200, result)
        except Exception as exc:
            self._send_json(
                500,
                {
                    "error": type(exc).__name__,
                    "message": str(exc),
                },
            )

    def _handle_legal_answer(self) -> None:
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length <= 0:
            self._send_json(400, {"error": "Missing JSON body"})
            return
        if content_length > MAX_JSON_BYTES:
            self._send_json(413, {"error": "JSON body is too large"})
            return

        try:
            body = self.rfile.read(content_length)
            payload = json.loads(body.decode("utf-8"))
            question = str(payload.get("question", ""))
            result = answer_legal_question(question)
            self._send_json(200, result)
        except json.JSONDecodeError as exc:
            self._send_json(400, {"error": "Invalid JSON", "message": str(exc)})
        except Exception as exc:
            self._send_json(
                500,
                {
                    "error": type(exc).__name__,
                    "message": str(exc),
                },
            )

    def _handle_legal_voice_answer(self) -> None:
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length <= 0:
            self._send_json(400, {"error": "Missing audio body"})
            return
        if content_length > MAX_UPLOAD_BYTES:
            self._send_json(413, {"error": "Audio body is too large"})
            return

        try:
            body = self.rfile.read(content_length)
            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as audio_file:
                audio_file.write(body)
                temp_path = Path(audio_file.name)

            try:
                result = answer_legal_voice(temp_path)
            finally:
                temp_path.unlink(missing_ok=True)

            self._send_json(200, result)
        except Exception as exc:
            self._send_json(
                500,
                {
                    "error": type(exc).__name__,
                    "message": str(exc),
                },
            )

    def _handle_report_draft(self) -> None:
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length <= 0:
            self._send_json(400, {"error": "Missing JSON body"})
            return
        if content_length > MAX_JSON_BYTES:
            self._send_json(413, {"error": "JSON body is too large"})
            return

        try:
            body = self.rfile.read(content_length)
            payload = json.loads(body.decode("utf-8"))
            transcript = str(payload.get("transcript", ""))
            result = draft_report(transcript)
            self._send_json(200, result)
        except json.JSONDecodeError as exc:
            self._send_json(400, {"error": "Invalid JSON", "message": str(exc)})
        except Exception as exc:
            self._send_json(
                500,
                {
                    "error": type(exc).__name__,
                    "message": str(exc),
                },
            )

    def _handle_report_voice_draft(self) -> None:
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length <= 0:
            self._send_json(400, {"error": "Missing audio body"})
            return
        if content_length > MAX_REPORT_UPLOAD_BYTES:
            self._send_json(413, {"error": "Audio body is too large"})
            return

        try:
            body = self.rfile.read(content_length)
            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as audio_file:
                audio_file.write(body)
                temp_path = Path(audio_file.name)

            try:
                result = draft_report_voice(temp_path)
            finally:
                temp_path.unlink(missing_ok=True)

            self._send_json(200, result)
        except Exception as exc:
            self._send_json(
                500,
                {
                    "error": type(exc).__name__,
                    "message": str(exc),
                },
            )

    def log_message(self, format: str, *args) -> None:
        print(f"[AI SERVER] {self.address_string()} - {format % args}")


def main() -> None:
    if os.environ.get("WHISPER_PRELOAD", "1") == "1":
        _get_transcriber()
    if os.environ.get("RISK_PRELOAD", "1") == "1":
        _get_risk_engine()
    server = ThreadingHTTPServer((HOST, PORT), AiRequestHandler)
    print(f"POLAPP AI server listening on http://{HOST}:{PORT}")
    print("Health check: GET /health")
    print("Threat analyze: POST /threat/analyze with 16-bit PCM WAV body")
    print("Legal answer: POST /legal/answer with JSON body")
    print("Legal voice answer: POST /legal/voice-answer with 16-bit PCM WAV body")
    print("Report draft: POST /report/draft with JSON body")
    print("Report voice draft: POST /report/voice-draft with 16-bit PCM WAV body")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down POLAPP AI server...")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
