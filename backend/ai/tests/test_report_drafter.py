import unittest

from src.incident_report_drafter import IncidentReportDrafter


class _UnavailableLlm:
    available = False


class _GroundingLlm:
    available = True

    def generate_json(self, prompt, *, schema, max_output_tokens):
        return {
            "incident_type": {"value": "흉기 관련", "evidence": "칼을 들고 있습니다"},
            "location": {"value": "노원역", "evidence": "노원역"},
            "occurrence_time": {"value": "오후 3시", "evidence": "오후 3시"},
            "observations": [
                {"value": "대상자가 칼을 소지한 정황", "evidence": "칼을 들고 있습니다"},
                {"value": "총기를 소지함", "evidence": "총기를 들고 있습니다"},
            ],
            "actions_taken": [
                {"value": "흉기를 회수함", "evidence": "칼을 내려놓으세요"},
                {"value": "현장을 통제함", "evidence": "현장을 통제했습니다"},
            ],
            "risk_factors": [],
            "people_involved": [],
            "injuries": [],
            "weapons": [{"value": "칼", "evidence": "칼을 들고 있습니다"}],
        }


class IncidentReportDrafterTests(unittest.TestCase):
    def _drafter(self):
        drafter = IncidentReportDrafter()
        drafter.llm = _UnavailableLlm()
        return drafter

    def test_command_is_not_written_as_completed_action(self):
        result = self._drafter().draft("대상자가 칼을 들고 있습니다. 칼을 내려놓으세요.")

        self.assertEqual(result["facts"]["incident_type"], "흉기 관련")
        self.assertEqual(result["facts"]["actions_taken"], [])
        self.assertIn("완료된 조치 확인되지 않음", result["draft"])

    def test_completed_action_is_reported(self):
        result = self._drafter().draft("대상자의 칼을 회수했습니다. 피해자가 다쳤습니다.")

        self.assertIn("흉기를 회수함", result["facts"]["actions_taken"])
        self.assertIn("부상 가능성", result["facts"]["risk_factors"])

    def test_intoxication_without_disturbance_is_not_drunken_disorder(self):
        result = self._drafter().draft("대상자가 술을 마셨다고 말했습니다.")

        self.assertEqual(result["facts"]["incident_type"], "현장 확인")

    def test_model_values_without_source_evidence_are_rejected(self):
        drafter = IncidentReportDrafter()
        drafter.llm = _GroundingLlm()
        result = drafter.draft(
            "오후 3시 노원역에서 대상자가 칼을 들고 있습니다. 현장을 통제했습니다. 칼을 내려놓으세요."
        )

        self.assertNotIn("총기를 소지함", result["facts"]["observations"])
        self.assertNotIn("흉기를 회수함", result["facts"]["actions_taken"])
        self.assertIn("현장을 통제함", result["facts"]["actions_taken"])
        self.assertTrue(result["used_model"])


if __name__ == "__main__":
    unittest.main()
