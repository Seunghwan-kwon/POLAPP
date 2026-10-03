from __future__ import annotations

import hashlib
import json
import os
import shutil
import time
import uuid
from pathlib import Path
from typing import Any


class EvaluationRecorder:
    """사람이 라벨링하는 후속 평가용 선택적·제한적 기록 저장소."""

    def __init__(self, output_dir: str | Path | None = None):
        self.enabled = os.environ.get("POLAPP_EVAL_RECORDINGS", "0") == "1"
        self.include_transcript = os.environ.get("POLAPP_EVAL_INCLUDE_TRANSCRIPT", "0") == "1"
        self.output_dir = Path(output_dir or os.environ.get("POLAPP_EVAL_DIR", "data/evaluation"))
        self.retention_days = max(1, int(os.environ.get("POLAPP_EVAL_RETENTION_DAYS", "14")))
        self.max_items = max(10, int(os.environ.get("POLAPP_EVAL_MAX_ITEMS", "1000")))

    def status(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "includes_transcript": self.include_transcript,
            "retention_days": self.retention_days,
            "max_items": self.max_items,
        }

    def _cleanup(self) -> None:
        cutoff = time.time() - self.retention_days * 86400
        metadata_files = sorted(
            self.output_dir.glob("*.json"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        for index, metadata_path in enumerate(metadata_files):
            if index < self.max_items and metadata_path.stat().st_mtime >= cutoff:
                continue
            audio_path = metadata_path.with_suffix(".wav")
            metadata_path.unlink(missing_ok=True)
            audio_path.unlink(missing_ok=True)

    def record(
        self,
        *,
        wav_path: Path,
        session_id: str,
        transcript: str,
        detection: dict[str, Any],
        risk: dict[str, Any],
    ) -> None:
        if not self.enabled:
            return
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self._cleanup()

        item_id = f"{int(time.time())}-{uuid.uuid4().hex[:10]}"
        destination_audio = self.output_dir / f"{item_id}.wav"
        destination_metadata = self.output_dir / f"{item_id}.json"
        shutil.copy2(wav_path, destination_audio)
        session_hash = hashlib.sha256(session_id.encode("utf-8")).hexdigest()[:12]
        payload = {
            "id": item_id,
            "created_at_epoch": int(time.time()),
            "session_hash": session_hash,
            "audio_file": destination_audio.name,
            "transcript": transcript if self.include_transcript else None,
            "detection": detection,
            "risk": risk,
            "human_label": {
                "level": None,
                "categories": [],
                "notes": "",
            },
        }
        destination_metadata.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
