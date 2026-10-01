import unittest

from src.profanity_detector import ProfanityDetector


class ProfanityDetectorTests(unittest.TestCase):
    def setUp(self):
        self.detector = ProfanityDetector()

    def test_drunken_disturbance_accepts_composed_expression(self):
        result = self.detector.detect("술 취한 남자가 복도에서 계속 소리를 지르고 있어요")

        self.assertTrue(result["is_profanity"])
        self.assertEqual(result["category"], "drunken_disturbance")
        self.assertEqual(result["category_label"], "주취 난동")

    def test_intoxication_without_disturbance_is_not_alerted(self):
        result = self.detector.detect("술에 취한 사람이 의자에 앉아 있습니다")

        self.assertFalse(result["is_profanity"])
        self.assertEqual(result["category"], "none")


if __name__ == "__main__":
    unittest.main()
