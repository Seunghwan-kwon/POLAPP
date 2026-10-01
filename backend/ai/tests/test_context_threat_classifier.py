import unittest
from types import SimpleNamespace

import numpy as np

from src.context_threat_classifier import ContextThreatClassifier


class _TokenizerStub:
    def encode(self, _text):
        return SimpleNamespace(ids=[1], attention_mask=[1], type_ids=[0])


class _SessionStub:
    def __init__(self, logits):
        self.logits = np.asarray([logits], dtype=np.float32)

    def get_inputs(self):
        return [SimpleNamespace(name="input_ids")]

    def run(self, _outputs, _feed):
        return [self.logits]


def _classifier(logits) -> ContextThreatClassifier:
    classifier = ContextThreatClassifier.__new__(ContextThreatClassifier)
    classifier.session = _SessionStub(logits)
    classifier.tokenizer = _TokenizerStub()
    classifier.labels = {
        0: "Clean Dialogue",
        1: "Serious Threats",
        2: "Extortion or Blackmail",
        3: "Harassment in Workplace",
        4: "Other Harassment",
    }
    classifier.thresholds = {"context_threat_threshold": 0.5}
    classifier.error = ""
    return classifier


class ContextThreatClassifierTests(unittest.TestCase):
    def test_clean_dialogue_does_not_add_threat_score(self):
        result = _classifier([3.0, 0.0, 0.0, 0.0, 0.0]).predict("안녕하세요")
        self.assertFalse(result["accepted"])
        self.assertEqual(result["threat_score"], 0.0)

    def test_ambiguous_non_clean_prediction_is_rejected(self):
        result = _classifier([0.0, 0.2, 0.1, 0.0, 0.0]).predict("불분명한 문장")
        self.assertFalse(result["accepted"])
        self.assertEqual(result["threat_score"], 0.0)

    def test_confident_threat_prediction_is_accepted(self):
        result = _classifier([0.0, 3.0, 0.0, 0.0, 0.0]).predict("죽여 버리겠다")
        self.assertTrue(result["accepted"])
        self.assertGreater(result["threat_score"], 50.0)


if __name__ == "__main__":
    unittest.main()
