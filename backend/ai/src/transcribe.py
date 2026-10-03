from __future__ import annotations

import gc
import os
import re
import threading
import ctranslate2
import numpy as np
from faster_whisper import WhisperModel


_TRANSCRIPT_TOKEN = re.compile(r"[0-9A-Za-z가-힣]+")


class STTTranscriber:
    """정확도를 우선하고 로컬 환경에 맞는 대체 경로를 제공하는 한국어 STT."""

    def __init__(
        self,
        model_size: str | None = None,
        language: str = "ko",
        min_level: float = 20.0,
    ):
        self.language = language
        self.min_level = min_level
        self.requested_model_size = (
            model_size or os.environ.get("WHISPER_MODEL_SIZE", "small")
        ).strip()
        self.fallback_model_size = os.environ.get(
            "WHISPER_FALLBACK_MODEL",
            "small",
        ).strip()
        self._inference_lock = threading.RLock()

        preferred_device, preferred_compute = self._select_runtime()
        self.model, self.model_size, self.device, self.compute_type = self._load_best_model(
            preferred_device,
            preferred_compute,
        )

    def _select_runtime(self) -> tuple[str, str]:
        dll_dir = os.environ.get("WHISPER_DLL_DIR")
        if dll_dir and os.path.isdir(dll_dir):
            os.add_dll_directory(dll_dir)

        try:
            supported = ctranslate2.get_supported_compute_types("cuda")
            print("[STT] CUDA supported compute types:", supported)
            if "int8_float16" in supported:
                return "cuda", "int8_float16"
            if "int8" in supported:
                return "cuda", "int8"
            if "float16" in supported:
                return "cuda", "float16"
            if "float32" in supported:
                return "cuda", "float32"
        except Exception as exc:
            print(f"[STT] CUDA unavailable, fallback to CPU: {exc}")

        return "cpu", "int8"

    def _load_best_model(
        self,
        preferred_device: str,
        preferred_compute: str,
    ) -> tuple[WhisperModel, str, str, str]:
        candidates: list[tuple[str, str, str]] = [
            (self.requested_model_size, preferred_device, preferred_compute),
        ]
        if preferred_device == "cuda":
            candidates.append((self.requested_model_size, "cpu", "int8"))
        if self.fallback_model_size != self.requested_model_size:
            candidates.append(
                (self.fallback_model_size, preferred_device, preferred_compute)
            )
            if preferred_device == "cuda":
                candidates.append((self.fallback_model_size, "cpu", "int8"))

        last_error: Exception | None = None
        attempted: set[tuple[str, str, str]] = set()
        for model_size, device, compute_type in candidates:
            candidate = (model_size, device, compute_type)
            if candidate in attempted:
                continue
            attempted.add(candidate)
            print(
                "[STT] model loading start... "
                f"model={model_size}, device={device}, compute_type={compute_type}"
            )
            try:
                model = WhisperModel(
                    model_size,
                    device=device,
                    compute_type=compute_type,
                )
                print("[STT] model loading done.")
                return model, model_size, device, compute_type
            except Exception as exc:
                last_error = exc
                print(
                    "[STT] model load failed... "
                    f"model={model_size}, device={device}: {exc}"
                )

        raise RuntimeError("No Whisper model could be loaded") from last_error

    def _looks_repetitive(self, text: str) -> bool:
        tokens = _TRANSCRIPT_TOKEN.findall(text.casefold())
        if len(tokens) < 6:
            return False

        longest_run = 1
        current_run = 1
        for previous, current in zip(tokens, tokens[1:]):
            if current == previous:
                current_run += 1
                longest_run = max(longest_run, current_run)
            else:
                current_run = 1

        most_common = max(tokens.count(token) for token in set(tokens))
        return longest_run >= 4 or most_common / len(tokens) >= 0.5

    def _valid_segment(self, segment: object, text: str) -> bool:
        if not text or self._looks_repetitive(text):
            return False

        compression_ratio = float(getattr(segment, "compression_ratio", 0.0))
        avg_logprob = float(getattr(segment, "avg_logprob", 0.0))
        no_speech_prob = float(getattr(segment, "no_speech_prob", 0.0))
        if compression_ratio > 2.4 or avg_logprob < -1.0:
            return False
        if no_speech_prob > 0.6 and avg_logprob < -0.8:
            return False
        return True

    def _decode(
        self,
        audio: np.ndarray,
    ) -> list[str]:
        segments, _ = self.model.transcribe(
            audio,
            language=self.language,
            beam_size=5,
            best_of=1,
            patience=1.2,
            repetition_penalty=1.1,
            no_repeat_ngram_size=3,
            temperature=0.0,
            log_prob_threshold=-1.0,
            no_speech_threshold=0.6,
            compression_ratio_threshold=2.4,
            vad_filter=True,
            vad_parameters={
                "threshold": 0.5,
                "min_speech_duration_ms": 250,
                "min_silence_duration_ms": 500,
                "speech_pad_ms": 250,
            },
            condition_on_previous_text=False,
            max_new_tokens=128,
        )
        texts: list[str] = []
        for segment in segments:
            text = segment.text.strip()
            if self._valid_segment(segment, text):
                texts.append(text)
        return texts

    def _move_current_model_to_cpu(self) -> None:
        model_size = self.model_size
        print(f"[STT] CUDA inference failed; reloading {model_size} on CPU int8.")
        del self.model
        gc.collect()
        self.model = WhisperModel(model_size, device="cpu", compute_type="int8")
        self.device = "cpu"
        self.compute_type = "int8"

    def transcribe(
        self,
        audio: np.ndarray,
        previous_text: str = "",
        *,
        context_id: str | None = None,
        profile: str = "general",
    ) -> str:
        if audio.size == 0:
            return ""

        level = float(np.mean(np.abs(audio)))
        if self.min_level > 0 and level < self.min_level:
            return ""

        normalized_audio = audio.astype(np.float32) / 32768.0

        with self._inference_lock:
            try:
                texts = self._decode(normalized_audio)
            except Exception:
                if self.device != "cuda":
                    raise
                self._move_current_model_to_cpu()
                texts = self._decode(normalized_audio)

        result = " ".join(texts).strip()
        return result
