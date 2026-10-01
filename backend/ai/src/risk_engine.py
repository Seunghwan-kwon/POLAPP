from __future__ import annotations

import json
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

from src.acoustic_features import extract_acoustic_features
from src.audio_event_detector import AudioEventDetector
from src.context_threat_classifier import ContextThreatClassifier


DEFAULT_POLICY_PATH = Path(__file__).resolve().parents[1] / "data" / "risk_policy.json"

CONTEXT_LABELS = {
    "serious threats": "협박",
    "extortion or blackmail": "공갈·협박",
    "harassment in workplace": "괴롭힘",
    "other harassment": "괴롭힘",
}

AUDIO_EVENT_LABELS = (
    ("screaming", "비명"),
    ("scream", "비명"),
    ("shout", "고함"),
    ("yell", "고함"),
    ("glass", "유리 파손"),
    ("breaking", "파손음"),
    ("smash", "충돌·파손음"),
    ("crash", "충돌음"),
    ("slap", "타격음"),
    ("smack", "타격음"),
    ("whack", "타격음"),
    ("thump", "충격음"),
    ("thud", "충격음"),
    ("gunshot", "총성"),
    ("gunfire", "총성"),
    ("explosion", "폭발음"),
)


def _clamp(value: float) -> float:
    return float(max(0.0, min(100.0, value)))


@dataclass
class _SessionState:
    baseline_activation: deque[float] = field(default_factory=lambda: deque(maxlen=20))
    baseline_dbfs: deque[float] = field(default_factory=lambda: deque(maxlen=20))
    events: deque[dict[str, Any]] = field(default_factory=lambda: deque(maxlen=20))
    last_seen: float = field(default_factory=time.time)
    lock: threading.Lock = field(default_factory=threading.Lock)


class RiskEngine:
    """음성 근거를 결합해 경찰관의 판단을 보조하는 위험도 엔진."""

    def __init__(
        self,
        policy_path: str | Path | None = None,
        context_classifier: ContextThreatClassifier | None = None,
        audio_event_detector: AudioEventDetector | None = None,
    ):
        path = Path(policy_path) if policy_path else DEFAULT_POLICY_PATH
        self.policy = json.loads(path.read_text(encoding="utf-8"))
        acoustic_policy = self.policy.get("acoustic_thresholds", {})
        self.baseline_min_windows = int(acoustic_policy.get("baseline_min_windows", 3))
        self.high_voice_min_db_rise = float(
            acoustic_policy.get("high_voice_min_db_rise", 10.0)
        )
        self.high_voice_min_activation_rise = float(
            acoustic_policy.get("high_voice_min_activation_rise", 12.0)
        )
        self.high_voice_signal_threshold = float(
            acoustic_policy.get("high_voice_signal_threshold", 75.0)
        )
        self.context_classifier = context_classifier or ContextThreatClassifier()
        self.audio_event_detector = audio_event_detector or AudioEventDetector()
        self._sessions: dict[str, _SessionState] = {}
        self._lock = threading.Lock()

    def capabilities(self) -> dict[str, Any]:
        return {
            "algorithm": self.policy["algorithm"],
            "context_model": self.context_classifier.status(),
            "audio_event_model": self.audio_event_detector.status(),
            "evaluation_only": True,
        }

    def reset(self, session_id: str) -> None:
        with self._lock:
            self._sessions.pop(session_id, None)

    def _state(self, session_id: str) -> _SessionState:
        now = time.time()
        with self._lock:
            stale = [key for key, state in self._sessions.items() if now - state.last_seen > 1800]
            for key in stale:
                self._sessions.pop(key, None)
            state = self._sessions.setdefault(session_id, _SessionState())
            state.last_seen = now
            return state

    def _keyword_score(self, detection: dict[str, Any]) -> tuple[float, str]:
        severities = self.policy["category_severity"]
        top_score = 0.0
        top_category = str(detection.get("category", "none"))
        for category in detection.get("categories", []):
            category_id = str(category.get("id", "unknown"))
            severity = float(severities.get(category_id, 45.0))
            match_strength = min(1.0, float(category.get("score", 0.0)) / 2.5)
            score = severity * match_strength
            if score > top_score:
                top_score = score
                top_category = category_id
        return round(_clamp(top_score), 1), top_category

    def _relative_activation(
        self,
        state: _SessionState,
        raw_score: float,
        current_dbfs: float,
        clean: bool,
    ) -> tuple[float, bool, float | None]:
        baseline_ready = len(state.baseline_activation) >= self.baseline_min_windows
        dbfs_ready = len(state.baseline_dbfs) >= self.baseline_min_windows
        baseline_dbfs = (
            float(np.median(state.baseline_dbfs)) if dbfs_ready else None
        )
        if clean and raw_score < 75.0:
            state.baseline_activation.append(raw_score)
            if current_dbfs > -55.0:
                state.baseline_dbfs.append(current_dbfs)
        if not baseline_ready:
            # 현장 기준음이 잡히기 전에는 음량만으로 위험 알림을 만들지 않습니다.
            return round(min(35.0, raw_score * 0.35), 1), False, baseline_dbfs

        baseline = float(np.median(state.baseline_activation))
        activation_rise = raw_score - baseline
        dbfs_rise = current_dbfs - baseline_dbfs if baseline_dbfs is not None else 0.0
        if (
            activation_rise < self.high_voice_min_activation_rise
            or dbfs_rise < self.high_voice_min_db_rise
        ):
            return round(min(49.0, raw_score * 0.25), 1), True, baseline_dbfs

        activation_evidence = _clamp(
            (activation_rise - self.high_voice_min_activation_rise) / 28.0 * 100.0
        )
        loudness_evidence = _clamp(
            (dbfs_rise - self.high_voice_min_db_rise) / 10.0 * 100.0
        )
        relative = 0.4 * activation_evidence + 0.6 * loudness_evidence
        return round(max(raw_score * 0.20, relative), 1), True, baseline_dbfs

    def _context_label(self, context: dict[str, Any]) -> str:
        raw_label = str(context.get("top_label", "")).strip().casefold()
        return CONTEXT_LABELS.get(raw_label, "위협 표현" if raw_label else "")

    def _audio_event_label(self, audio_events: dict[str, Any]) -> str:
        for event in audio_events.get("top_events", []):
            raw_label = str(event.get("label", "")).casefold()
            for keyword, label in AUDIO_EVENT_LABELS:
                if keyword in raw_label:
                    return label
        return ""

    def _trend_score(
        self,
        state: _SessionState,
        now: float,
        category: str,
        keyword_score: float,
        activation_score: float,
        danger_score: float,
    ) -> float:
        state.events.append(
            {
                "time": now,
                "category": category,
                "k": keyword_score,
                "e": activation_score,
                "s": danger_score,
            }
        )
        recent = [item for item in state.events if now - float(item["time"]) <= 30.0]
        threat_events = [
            item
            for item in recent
            if float(item["k"]) >= 40.0
            or float(item["e"]) >= self.high_voice_signal_threshold
            or float(item["s"]) >= 55.0
        ]
        same_category = [
            item
            for item in threat_events
            if category != "none" and item["category"] == category
        ]
        recurrence = min(60.0, max(0, len(threat_events) - 1) * 20.0)
        repetition = min(25.0, max(0, len(same_category) - 1) * 12.5)
        escalation = 0.0
        if len(recent) >= 2:
            previous = recent[-2]
            delta = max(
                keyword_score - float(previous["k"]),
                activation_score - float(previous["e"]),
                danger_score - float(previous["s"]),
            )
            escalation = min(25.0, max(0.0, delta) * 0.5)
        return round(_clamp(recurrence + repetition + escalation), 1)

    def _level(
        self,
        signals: dict[str, float],
        category: str,
    ) -> tuple[int, float]:
        e, k, c, s, t = (signals[key] for key in ("E", "K", "C", "S", "T"))
        corroborating = sum(value >= 50.0 for value in signals.values())
        severe_category = category in {"weapon", "physical_threat", "assault"}

        if (
            (severe_category and k >= 82.0 and max(e, s, t) >= 60.0)
            or (s >= 90.0 and max(k, e, t) >= 60.0)
            or (k >= 80.0 and t >= 80.0)
        ):
            level = 4
        elif (
            k >= 72.0
            or s >= 75.0
            or (k >= 55.0 and max(e, s, t) >= 50.0)
            or corroborating >= 3
        ):
            level = 3
        elif (
            k >= 40.0
            or e >= 75.0
            or c >= 60.0
            or s >= 55.0
            or t >= 40.0
            or corroborating >= 2
        ):
            level = 2
        else:
            level = 1

        # 근거 지수는 신호 결합값이며 실제 폭력 발생 확률이 아닙니다.
        ranked = sorted(signals.values(), reverse=True)
        evidence_index = _clamp(ranked[0] + 0.20 * ranked[1] + 0.10 * ranked[2])
        return level, round(evidence_index, 1)

    def _reasons(
        self,
        signals: dict[str, float],
        category: str,
        category_label: str,
        acoustic: dict[str, Any],
        context: dict[str, Any],
        audio_events: dict[str, Any],
        baseline_dbfs: float | None,
    ) -> list[str]:
        reasons: list[str] = []
        if signals["K"] >= 40.0:
            detected_label = category_label or self._context_label(context)
            if detected_label:
                reasons.append(f"문맥 분류 모델: {detected_label} 감지")
        if signals["E"] >= self.high_voice_signal_threshold:
            current_dbfs = float(acoustic["rms_dbfs"])
            average = f"{baseline_dbfs:.1f} dB" if baseline_dbfs is not None else "측정 중"
            reasons.append(
                "평소 대비 데시벨: 상승"
                f"(평균: {average}, 현재: {current_dbfs:.1f} dB)"
            )
        if signals["C"] >= 50.0:
            reasons.append("주변 소리: 여러 사람의 목소리 감지")
        if signals["S"] >= 50.0:
            event_label = self._audio_event_label(audio_events)
            reasons.append(
                f"위험 소리: {event_label} 감지" if event_label else "위험 소리 감지"
            )
        if signals["T"] >= 40.0:
            reasons.append("반복 감지: 최근 30초 동안 위험 신호가 반복됨")
        return reasons[:4]

    def _alert_label(
        self,
        detection: dict[str, Any],
        context: dict[str, Any],
        signals: dict[str, float],
    ) -> str:
        category_label = str(detection.get("category_label", "")).strip()
        if category_label:
            return category_label

        context_label = str(context.get("top_label", "")).casefold()
        if signals["K"] >= 40.0:
            if "serious threat" in context_label:
                return "협박"
            if "extortion" in context_label or "blackmail" in context_label:
                return "공갈·협박"
            if "harassment" in context_label:
                return "괴롭힘"
        if signals["S"] >= 50.0:
            return "위험 소리"
        if signals["E"] >= self.high_voice_signal_threshold:
            return "고성"
        if signals["C"] >= 50.0:
            return "군중 소음"
        return "위협"

    def assess(
        self,
        *,
        session_id: str,
        audio: np.ndarray,
        sample_rate: int,
        transcript: str,
        detection: dict[str, Any],
        now: float | None = None,
    ) -> dict[str, Any]:
        timestamp = now if now is not None else time.time()
        state = self._state(session_id)
        acoustic = extract_acoustic_features(audio, sample_rate, transcript)
        context = self.context_classifier.predict(transcript)
        audio_events = self.audio_event_detector.predict(audio, sample_rate)

        rule_score, category = self._keyword_score(detection)
        context_score = float(context.get("threat_score", 0.0))
        keyword_score = round(max(rule_score, context_score), 1)
        crowd_score = round(float(audio_events.get("crowd_score", 0.0)), 1)
        danger_score = round(float(audio_events.get("danger_score", 0.0)), 1)
        with state.lock:
            activation_score, baseline_ready, baseline_dbfs = self._relative_activation(
                state,
                float(acoustic["activation_raw"]),
                float(acoustic["rms_dbfs"]),
                clean=(
                    keyword_score < 40.0
                    and crowd_score < 60.0
                    and danger_score < 55.0
                ),
            )
            trend_score = self._trend_score(
                state,
                timestamp,
                category,
                keyword_score,
                activation_score,
                danger_score,
            )
        signals = {
            "E": activation_score,
            "K": keyword_score,
            "C": crowd_score,
            "S": danger_score,
            "T": trend_score,
        }
        level, evidence_index = self._level(signals, category)
        level_config = self.policy["levels"][str(level)]

        return {
            "algorithm": self.policy["algorithm"],
            "level": level,
            "label": level_config["label"],
            "alert_label": self._alert_label(detection, context, signals),
            "evidence_index": evidence_index,
            "guidance": level_config["guidance"],
            "reasons": self._reasons(
                signals,
                category,
                str(detection.get("category_label", "")),
                acoustic,
                context,
                audio_events,
                baseline_dbfs,
            ),
            "signals": signals,
            "baseline_ready": baseline_ready,
            "models": {
                "context": context,
                "audio_event": audio_events,
            },
            "acoustic": acoustic,
            "limitations": self.policy["limitations"],
        }
