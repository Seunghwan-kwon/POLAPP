from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np


DEFAULT_MODEL_DIR = Path(__file__).resolve().parents[1] / "models" / "guardian_context_model"


class ContextThreatClassifier:
    """KCDD로 파인튜닝한 선택적 ONNX 문맥 분류기.

    모델이 없을 때도 서버는 규칙 기반 경로로 동작하며 상태와 오류를 API에 표시합니다.
    """

    def __init__(self, model_dir: str | Path | None = None):
        self.model_dir = Path(model_dir) if model_dir else DEFAULT_MODEL_DIR
        self.session = None
        self.tokenizer = None
        self.labels: dict[int, str] = {}
        self.thresholds: dict[str, Any] = {}
        self.error = "model artifacts not installed"
        self._load()

    @property
    def available(self) -> bool:
        return self.session is not None and self.tokenizer is not None

    def _load(self) -> None:
        model_path = self.model_dir / "model.int8.onnx"
        tokenizer_path = self.model_dir / "tokenizer.json"
        labels_path = self.model_dir / "labels.json"
        if not all(path.exists() for path in (model_path, tokenizer_path, labels_path)):
            return

        try:
            import onnxruntime as ort
            from tokenizers import Tokenizer

            self.session = ort.InferenceSession(
                str(model_path),
                providers=["CPUExecutionProvider"],
            )
            self.tokenizer = Tokenizer.from_file(str(tokenizer_path))
            self.tokenizer.enable_truncation(max_length=256)
            self.tokenizer.enable_padding(length=256)

            labels_payload = json.loads(labels_path.read_text(encoding="utf-8"))
            raw_labels = labels_payload.get("id2label", labels_payload)
            self.labels = {int(key): str(value) for key, value in raw_labels.items()}

            threshold_path = self.model_dir / "thresholds.json"
            if threshold_path.exists():
                self.thresholds = json.loads(threshold_path.read_text(encoding="utf-8"))
            self.error = ""
        except Exception as exc:
            self.session = None
            self.tokenizer = None
            self.error = f"{type(exc).__name__}: {exc}"

    def status(self) -> dict[str, Any]:
        return {
            "available": self.available,
            "model": "KCDD KLUE-RoBERTa-small INT8",
            "error": self.error,
        }

    def predict(self, text: str) -> dict[str, Any]:
        if not self.available or not text.strip():
            return {**self.status(), "threat_score": 0.0, "top_label": ""}

        encoded = self.tokenizer.encode(text)
        values = {
            "input_ids": np.asarray([encoded.ids], dtype=np.int64),
            "attention_mask": np.asarray([encoded.attention_mask], dtype=np.int64),
            "token_type_ids": np.asarray([encoded.type_ids], dtype=np.int64),
        }
        feed = {
            item.name: values[item.name]
            for item in self.session.get_inputs()
            if item.name in values
        }
        logits = np.asarray(self.session.run(None, feed)[0])[0]
        probabilities = np.exp(logits - np.max(logits))
        probabilities = probabilities / np.sum(probabilities)
        scores = {
            self.labels.get(index, str(index)): round(float(probability), 4)
            for index, probability in enumerate(probabilities)
        }

        clean_id = next(
            (
                index
                for index, label in self.labels.items()
                if "clean" in label.casefold() or label == "000001"
            ),
            None,
        )
        clean_probability = float(probabilities[clean_id]) if clean_id is not None else 0.0
        top_index = int(np.argmax(probabilities))
        top_probability = float(probabilities[top_index])
        threshold = float(self.thresholds.get("context_threat_threshold", 0.5))
        accepted = top_index != clean_id and top_probability >= threshold
        threat_score = top_probability * 100.0 if accepted else 0.0
        return {
            **self.status(),
            "threat_score": round(threat_score, 1),
            "top_label": self.labels.get(top_index, str(top_index)),
            "top_score": round(top_probability * 100.0, 1),
            "accepted": accepted,
            "probabilities": scores,
        }
