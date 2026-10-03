import unittest
from pathlib import Path

import numpy as np

from src.acoustic_features import extract_acoustic_features
from src.risk_engine import RiskEngine, _SessionState


class _ContextStub:
    def status(self):
        return {"available": False, "model": "stub", "error": "test"}

    def predict(self, _text):
        return {**self.status(), "threat_score": 0.0, "top_label": ""}


class _AudioEventStub:
    def status(self):
        return {"available": False, "model": "stub", "error": "test"}

    def predict(self, _audio, _sample_rate):
        return {
            **self.status(),
            "crowd_score": 0.0,
            "danger_score": 0.0,
            "top_events": [],
        }


class AcousticFeatureTests(unittest.TestCase):
    def test_silence_has_zero_activation(self):
        result = extract_acoustic_features(np.zeros(16000, dtype=np.int16), 16000)
        self.assertEqual(result["activation_raw"], 0.0)
        self.assertAlmostEqual(result["duration_seconds"], 1.0)

    def test_loud_tone_has_higher_activation(self):
        time_axis = np.arange(16000) / 16000.0
        audio = (np.sin(2 * np.pi * 220 * time_axis) * 28000).astype(np.int16)
        result = extract_acoustic_features(audio, 16000, "멈춰 움직이지 마")
        self.assertGreater(result["activation_raw"], 40.0)
        self.assertGreater(result["pitch_median_hz"], 150.0)


class RiskEngineTests(unittest.TestCase):
    def setUp(self):
        policy = Path(__file__).resolve().parents[1] / "data" / "risk_policy.json"
        self.engine = RiskEngine(
            policy_path=policy,
            context_classifier=_ContextStub(),
            audio_event_detector=_AudioEventStub(),
        )
        self.silence = np.zeros(16000, dtype=np.int16)

    def test_clean_silence_is_level_one(self):
        result = self.engine.assess(
            session_id="clean",
            audio=self.silence,
            sample_rate=16000,
            transcript="안녕하세요",
            detection={"category": "none", "category_label": "", "categories": []},
            now=1.0,
        )
        self.assertEqual(result["level"], 1)
        self.assertEqual(result["signals"]["K"], 0.0)

    def test_loudness_alone_does_not_alert_before_baseline_is_ready(self):
        time_axis = np.arange(16000) / 16000.0
        loud_audio = (np.sin(2 * np.pi * 220 * time_axis) * 28000).astype(np.int16)
        result = self.engine.assess(
            session_id="uncalibrated",
            audio=loud_audio,
            sample_rate=16000,
            transcript="",
            detection={"category": "none", "category_label": "", "categories": []},
            now=1.0,
        )
        self.assertFalse(result["baseline_ready"])
        self.assertEqual(result["level"], 1)

    def test_small_loudness_increase_is_not_high_voice(self):
        state = _SessionState()
        state.baseline_activation.extend([30.0, 31.0, 29.0])
        state.baseline_dbfs.extend([-32.0, -31.0, -33.0])

        score, ready, _ = self.engine._relative_activation(
            state,
            raw_score=48.0,
            current_dbfs=-25.0,
            clean=False,
        )

        self.assertTrue(ready)
        self.assertLess(score, self.engine.high_voice_signal_threshold)

    def test_large_loudness_increase_reaches_high_voice_threshold(self):
        state = _SessionState()
        state.baseline_activation.extend([30.0, 31.0, 29.0])
        state.baseline_dbfs.extend([-32.0, -31.0, -33.0])

        score, ready, _ = self.engine._relative_activation(
            state,
            raw_score=70.0,
            current_dbfs=-12.0,
            clean=False,
        )

        self.assertTrue(ready)
        self.assertGreaterEqual(score, self.engine.high_voice_signal_threshold)

    def test_weapon_phrase_is_high_risk_without_claiming_emergency(self):
        detection = {
            "category": "weapon",
            "category_label": "흉기",
            "categories": [{"id": "weapon", "score": 2.5}],
        }
        result = self.engine.assess(
            session_id="weapon",
            audio=self.silence,
            sample_rate=16000,
            transcript="칼 내려놔",
            detection=detection,
            now=2.0,
        )
        self.assertEqual(result["level"], 3)
        self.assertEqual(result["signals"]["K"], 96.0)
        self.assertEqual(result["alert_label"], "흉기")
        self.assertIn("문맥 분류 모델: 흉기 감지", result["reasons"])

    def test_repetition_increases_temporal_signal(self):
        detection = {
            "category": "profanity",
            "category_label": "욕설",
            "categories": [{"id": "profanity", "score": 2.5}],
        }
        first = self.engine.assess(
            session_id="repeat",
            audio=self.silence,
            sample_rate=16000,
            transcript="욕설",
            detection=detection,
            now=10.0,
        )
        second = self.engine.assess(
            session_id="repeat",
            audio=self.silence,
            sample_rate=16000,
            transcript="욕설",
            detection=detection,
            now=15.0,
        )
        self.assertGreater(second["signals"]["T"], first["signals"]["T"])


if __name__ == "__main__":
    unittest.main()
