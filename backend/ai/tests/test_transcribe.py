import threading
import unittest
from types import SimpleNamespace

import numpy as np

from src.transcribe import STTTranscriber


class _FakeWhisperModel:
    def __init__(self):
        self.calls = []

    def transcribe(self, audio, **options):
        self.calls.append((audio, options))
        return iter(
            [
                SimpleNamespace(
                    text=" 흉기를 내려놓으세요 ",
                    compression_ratio=1.0,
                    avg_logprob=-0.2,
                    no_speech_prob=0.05,
                )
            ]
        ), None


def _transcriber_without_loading() -> STTTranscriber:
    transcriber = STTTranscriber.__new__(STTTranscriber)
    transcriber.language = "ko"
    transcriber.min_level = 20.0
    transcriber.model = _FakeWhisperModel()
    transcriber.model_size = "medium"
    transcriber.device = "cpu"
    transcriber.compute_type = "int8"
    transcriber._inference_lock = threading.RLock()
    return transcriber


class STTTranscriberTests(unittest.TestCase):
    def test_accuracy_and_hallucination_guard_options_are_used(self):
        transcriber = _transcriber_without_loading()
        audio = np.full(16000, 1000, dtype=np.int16)

        result = transcriber.transcribe(
            audio,
            context_id="session-a",
            profile="threat",
        )

        self.assertEqual(result, "흉기를 내려놓으세요")
        options = transcriber.model.calls[0][1]
        self.assertEqual(options["beam_size"], 5)
        self.assertTrue(options["vad_filter"])
        self.assertEqual(options["temperature"], 0.0)
        self.assertEqual(options["no_repeat_ngram_size"], 3)
        self.assertNotIn("initial_prompt", options)
        self.assertNotIn("hotwords", options)

    def test_previous_window_transcript_is_not_added_to_next_prompt(self):
        transcriber = _transcriber_without_loading()
        audio = np.full(16000, 1000, dtype=np.int16)

        transcriber.transcribe(audio, context_id="session-a", profile="threat")
        transcriber.transcribe(audio, context_id="session-a", profile="threat")

        second_options = transcriber.model.calls[1][1]
        self.assertNotIn("initial_prompt", second_options)
        self.assertNotIn("hotwords", second_options)

    def test_repetitive_hallucination_is_rejected(self):
        transcriber = _transcriber_without_loading()
        repeated = "경찰관 신고자 " + "피해자 " * 20
        self.assertTrue(transcriber._looks_repetitive(repeated))
        segment = SimpleNamespace(
            compression_ratio=3.0,
            avg_logprob=-0.2,
            no_speech_prob=0.1,
        )
        self.assertFalse(transcriber._valid_segment(segment, repeated))

    def test_quiet_audio_is_skipped(self):
        transcriber = _transcriber_without_loading()
        result = transcriber.transcribe(np.zeros(16000, dtype=np.int16))
        self.assertEqual(result, "")
        self.assertEqual(transcriber.model.calls, [])


if __name__ == "__main__":
    unittest.main()
