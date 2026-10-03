import unittest

import numpy as np

from src.report_audio_pipeline import transcribe_report_audio


class _FakeTranscriber:
    def __init__(self, outputs):
        self.outputs = iter(outputs)
        self.calls = []

    def transcribe(self, audio, **options):
        self.calls.append((audio, options))
        return next(self.outputs)


class ReportAudioPipelineTests(unittest.TestCase):
    def test_long_audio_is_chunked_and_overlap_text_is_removed(self):
        audio = np.ones(65 * 16000, dtype=np.int16)
        transcriber = _FakeTranscriber(
            [
                "대상자가 칼을 들고 있습니다",
                "들고 있습니다 피해자가 다쳤습니다",
                "경찰관이 흉기를 회수했습니다",
            ]
        )

        result = transcribe_report_audio(transcriber, audio, 16000)

        self.assertEqual(len(transcriber.calls), 3)
        self.assertEqual(
            result["transcript"],
            "대상자가 칼을 들고 있습니다 피해자가 다쳤습니다 경찰관이 흉기를 회수했습니다",
        )
        self.assertEqual(len(result["segments"]), 3)
        self.assertEqual(transcriber.calls[0][1]["profile"], "report")

    def test_non_16khz_audio_is_resampled_before_transcription(self):
        audio = np.ones(8000, dtype=np.int16)
        transcriber = _FakeTranscriber(["신고 내용을 확인했습니다"])

        result = transcribe_report_audio(transcriber, audio, 8000)

        self.assertEqual(transcriber.calls[0][0].size, 16000)
        self.assertEqual(result["duration_seconds"], 1.0)


if __name__ == "__main__":
    unittest.main()
