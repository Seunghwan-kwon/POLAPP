from __future__ import annotations

from typing import Any

import numpy as np


def _clamp(value: float, low: float = 0.0, high: float = 100.0) -> float:
    return float(max(low, min(high, value)))


def _dbfs(value: float) -> float:
    return 20.0 * np.log10(max(value, 1e-8))


def _frame_signal(signal: np.ndarray, frame_size: int, hop_size: int) -> np.ndarray:
    if signal.size < frame_size:
        return np.pad(signal, (0, frame_size - signal.size))[None, :]
    frame_count = 1 + (signal.size - frame_size) // hop_size
    shape = (frame_count, frame_size)
    strides = (signal.strides[0] * hop_size, signal.strides[0])
    return np.lib.stride_tricks.as_strided(signal, shape=shape, strides=strides)


def _pitch_values(frames: np.ndarray, sample_rate: int) -> list[float]:
    min_lag = max(1, int(sample_rate / 500.0))
    max_lag = max(min_lag + 1, int(sample_rate / 75.0))
    pitches: list[float] = []

    # 피치 계산 프레임을 제한해 CPU 환경의 구간별 처리 시간을 일정하게 유지합니다.
    step = max(1, len(frames) // 60)
    for frame in frames[::step]:
        centered = frame - np.mean(frame)
        energy = float(np.sqrt(np.mean(centered * centered)))
        if energy < 0.008:
            continue
        correlation = np.correlate(centered, centered, mode="full")[len(centered) - 1 :]
        upper = min(max_lag, len(correlation) - 1)
        if upper <= min_lag:
            continue
        search = correlation[min_lag : upper + 1]
        lag = int(np.argmax(search)) + min_lag
        if correlation[0] <= 0 or correlation[lag] / correlation[0] < 0.30:
            continue
        pitches.append(sample_rate / lag)
    return pitches


def extract_acoustic_features(
    audio: np.ndarray,
    sample_rate: int,
    transcript: str = "",
) -> dict[str, Any]:
    """eGeMAPS를 참고한 설명 가능한 음향 특성과 진단용 활성도 지수를 반환합니다."""

    if sample_rate <= 0:
        raise ValueError("sample_rate must be positive")

    signal = np.asarray(audio, dtype=np.float32).reshape(-1)
    if signal.size == 0:
        signal = np.zeros(1, dtype=np.float32)
    if np.max(np.abs(signal)) > 1.5:
        signal = signal / 32768.0

    duration = signal.size / float(sample_rate)
    frame_size = max(1, int(sample_rate * 0.025))
    hop_size = max(1, int(sample_rate * 0.010))
    frames = _frame_signal(signal, frame_size, hop_size)
    frame_rms = np.sqrt(np.mean(frames * frames, axis=1) + 1e-12)
    frame_db = 20.0 * np.log10(np.maximum(frame_rms, 1e-8))

    rms = float(np.sqrt(np.mean(signal * signal) + 1e-12))
    peak = float(np.max(np.abs(signal)))
    rms_dbfs = float(_dbfs(rms))
    peak_dbfs = float(_dbfs(peak))
    rms_variability_db = float(np.std(frame_db))
    zero_crossing_rate = float(np.mean(np.abs(np.diff(np.signbit(signal)))))

    pitches = _pitch_values(frames, sample_rate)
    pitch_median_hz = float(np.median(pitches)) if pitches else 0.0
    pitch_variability = (
        float(np.std(pitches) / max(np.mean(pitches), 1e-6)) if len(pitches) >= 3 else 0.0
    )

    compact_text = "".join(transcript.split())
    speech_rate = len(compact_text) / max(duration, 0.25)

    if rms_dbfs <= -55.0:
        activation_score = 0.0
    else:
        loudness_score = _clamp((rms_dbfs + 42.0) / 24.0 * 100.0)
        peak_score = _clamp((peak_dbfs + 22.0) / 20.0 * 100.0)
        variability_score = _clamp(rms_variability_db / 12.0 * 100.0)
        pitch_score = _clamp(pitch_variability / 0.35 * 100.0)
        rate_score = _clamp((speech_rate - 2.0) / 7.0 * 100.0)
        activation_score = (
            0.35 * loudness_score
            + 0.20 * peak_score
            + 0.20 * variability_score
            + 0.15 * pitch_score
            + 0.10 * rate_score
        )

    return {
        "duration_seconds": round(duration, 3),
        "rms_dbfs": round(rms_dbfs, 2),
        "peak_dbfs": round(peak_dbfs, 2),
        "rms_variability_db": round(rms_variability_db, 2),
        "pitch_median_hz": round(pitch_median_hz, 2),
        "pitch_variability": round(pitch_variability, 4),
        "zero_crossing_rate": round(zero_crossing_rate, 4),
        "speech_rate_chars_per_second": round(speech_rate, 2),
        "activation_raw": round(_clamp(activation_score), 1),
    }
