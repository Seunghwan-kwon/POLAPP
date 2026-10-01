from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any

import numpy as np


DEFAULT_MODEL_DIR = Path(__file__).resolve().parents[1] / "models" / "yamnet"


class AudioEventDetector:
    """군중과 위험 음향 근거를 추출하는 선택적 YAMNet ONNX 탐지기."""

    def __init__(self, model_dir: str | Path | None = None):
        self.model_dir = Path(model_dir) if model_dir else DEFAULT_MODEL_DIR
        self.session = None
        self.labels: list[str] = []
        self.groups: dict[str, list[str]] = {}
        self.error = "model artifacts not installed"
        self._load()

    @property
    def available(self) -> bool:
        return self.session is not None and bool(self.labels)

    def _load(self) -> None:
        model_path = self.model_dir / "yamnet.onnx"
        class_map_path = self.model_dir / "yamnet_class_map.csv"
        groups_path = self.model_dir / "event_groups.json"
        if not all(path.exists() for path in (model_path, class_map_path, groups_path)):
            return

        try:
            import onnxruntime as ort

            with class_map_path.open("r", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.labels = [str(row.get("display_name", "")) for row in rows]
            self.groups = json.loads(groups_path.read_text(encoding="utf-8"))
            self.session = ort.InferenceSession(
                str(model_path),
                providers=["CPUExecutionProvider"],
            )
            self.error = ""
        except Exception as exc:
            self.session = None
            self.labels = []
            self.error = f"{type(exc).__name__}: {exc}"

    def status(self) -> dict[str, Any]:
        return {
            "available": self.available,
            "model": "YAMNet AudioSet ONNX",
            "error": self.error,
        }

    def _resample(self, signal: np.ndarray, sample_rate: int) -> np.ndarray:
        if sample_rate == 16000:
            return signal
        target_size = max(1, int(round(signal.size * 16000 / sample_rate)))
        source_x = np.linspace(0.0, 1.0, signal.size, endpoint=False)
        target_x = np.linspace(0.0, 1.0, target_size, endpoint=False)
        return np.interp(target_x, source_x, signal).astype(np.float32)

    def _group_score(self, class_scores: np.ndarray, group_name: str) -> float:
        wanted = [item.casefold() for item in self.groups.get(group_name, [])]
        indexes = [
            index
            for index, label in enumerate(self.labels)
            if any(name in label.casefold() for name in wanted)
        ]
        return float(np.max(class_scores[indexes])) if indexes else 0.0

    def predict(self, audio: np.ndarray, sample_rate: int) -> dict[str, Any]:
        if not self.available:
            return {
                **self.status(),
                "crowd_score": 0.0,
                "danger_score": 0.0,
                "top_events": [],
            }

        signal = np.asarray(audio, dtype=np.float32).reshape(-1)
        if np.max(np.abs(signal), initial=0.0) > 1.5:
            signal = signal / 32768.0
        signal = self._resample(signal, sample_rate)

        input_meta = self.session.get_inputs()[0]
        input_value = signal[None, :] if len(input_meta.shape) == 2 else signal
        outputs = self.session.run(None, {input_meta.name: input_value.astype(np.float32)})
        scores = np.asarray(outputs[0])
        if scores.ndim == 3:
            scores = scores[0]
        if scores.ndim == 1:
            scores = scores[None, :]
        class_scores = np.percentile(scores, 90, axis=0)

        top_indexes = np.argsort(class_scores)[-5:][::-1]
        top_events = [
            {
                "label": self.labels[int(index)],
                "score": round(float(class_scores[int(index)]) * 100.0, 1),
            }
            for index in top_indexes
        ]
        return {
            **self.status(),
            "crowd_score": round(self._group_score(class_scores, "crowd") * 100.0, 1),
            "danger_score": round(self._group_score(class_scores, "danger") * 100.0, 1),
            "top_events": top_events,
        }
