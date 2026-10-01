from __future__ import annotations

from typing import Any

import numpy as np


TARGET_SAMPLE_RATE = 16000
DEFAULT_CHUNK_SECONDS = 30.0
DEFAULT_OVERLAP_SECONDS = 1.2


def transcribe_report_audio(
    transcriber: Any,
    audio: np.ndarray,
    sample_rate: int,
    *,
    chunk_seconds: float = DEFAULT_CHUNK_SECONDS,
    overlap_seconds: float = DEFAULT_OVERLAP_SECONDS,
) -> dict[str, Any]:
    """긴 녹음을 겹치는 구간으로 분할해 순서대로 전사합니다."""
    if sample_rate <= 0:
        raise ValueError("Invalid audio sample rate")
    if audio.size == 0:
        return {"transcript": "", "segments": [], "duration_seconds": 0.0}

    normalized = _resample_int16(audio, sample_rate, TARGET_SAMPLE_RATE)
    duration_seconds = normalized.size / TARGET_SAMPLE_RATE
    chunk_size = max(1, int(chunk_seconds * TARGET_SAMPLE_RATE))
    overlap_size = max(0, int(overlap_seconds * TARGET_SAMPLE_RATE))
    if overlap_size >= chunk_size:
        raise ValueError("Report audio overlap must be shorter than a chunk")

    step = chunk_size - overlap_size
    segments: list[dict[str, Any]] = []
    merged_text = ""
    start = 0
    index = 1

    while start < normalized.size:
        end = min(normalized.size, start + chunk_size)
        chunk = normalized[start:end]
        text = transcriber.transcribe(
            chunk,
            context_id=f"report-{index}",
            profile="report",
        )
        text = " ".join(text.strip().split())
        if text:
            text = _remove_exact_token_overlap(merged_text, text)
            if text:
                segments.append(
                    {
                        "index": index,
                        "start_seconds": round(start / TARGET_SAMPLE_RATE, 2),
                        "end_seconds": round(end / TARGET_SAMPLE_RATE, 2),
                        "text": text,
                    }
                )
                merged_text = " ".join(part for part in (merged_text, text) if part)

        if end >= normalized.size:
            break
        start += step
        index += 1

    return {
        "transcript": merged_text.strip(),
        "segments": segments,
        "duration_seconds": round(duration_seconds, 2),
    }


def _resample_int16(audio: np.ndarray, source_rate: int, target_rate: int) -> np.ndarray:
    samples = np.asarray(audio, dtype=np.int16).reshape(-1)
    if source_rate == target_rate or samples.size < 2:
        return samples

    target_size = max(1, int(round(samples.size * target_rate / source_rate)))
    source_positions = np.linspace(0.0, 1.0, num=samples.size, endpoint=False)
    target_positions = np.linspace(0.0, 1.0, num=target_size, endpoint=False)
    resampled = np.interp(target_positions, source_positions, samples.astype(np.float32))
    return np.clip(np.rint(resampled), -32768, 32767).astype(np.int16)


def _remove_exact_token_overlap(previous: str, current: str, max_tokens: int = 16) -> str:
    # 인접 구간의 겹친 음성이 같은 문장으로 두 번 들어가는 것을 막습니다.
    previous_tokens = previous.split()
    current_tokens = current.split()
    limit = min(max_tokens, len(previous_tokens), len(current_tokens))
    for size in range(limit, 0, -1):
        left = [token.casefold() for token in previous_tokens[-size:]]
        right = [token.casefold() for token in current_tokens[:size]]
        if left == right:
            return " ".join(current_tokens[size:]).strip()
    return current.strip()
