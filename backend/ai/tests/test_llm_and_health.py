import os
import unittest
from unittest.mock import patch

import ai_server
from src.llm_client import LlmClient


class _TranscriberStub:
    model_size = "small"
    device = "cpu"
    compute_type = "int8"


class _RiskEngineStub:
    def capabilities(self):
        return {
            "context_model": {"available": True, "model": "context-stub"},
            "audio_event_model": {"available": True, "model": "audio-stub"},
        }


class LlmConfigurationTests(unittest.TestCase):
    def test_no_key_keeps_provider_unavailable_without_exposing_a_secret(self):
        with patch.dict(
            os.environ,
            {"LLM_PROVIDER": "gemini", "GEMINI_API_KEY": ""},
            clear=False,
        ):
            status = LlmClient().status()
        self.assertEqual(status["provider"], "gemini")
        self.assertFalse(status["available"])
        self.assertNotIn("api_key", status)

    def test_unknown_provider_is_reported(self):
        client = LlmClient(provider="unknown")
        self.assertFalse(client.available)
        self.assertIn("Unsupported", client.error)


class HealthPayloadTests(unittest.TestCase):
    def test_required_models_ready_even_when_optional_llm_is_absent(self):
        with (
            patch.object(ai_server, "_get_transcriber", return_value=_TranscriberStub()),
            patch.object(ai_server, "_get_risk_engine", return_value=_RiskEngineStub()),
            patch.dict(
                os.environ,
                {"LLM_PROVIDER": "gemini", "GEMINI_API_KEY": ""},
                clear=False,
            ),
        ):
            payload = ai_server._health_payload()

        self.assertTrue(payload["ready"])
        self.assertEqual(payload["status"], "ok")
        self.assertIn("llm_optional", payload["issues"])


if __name__ == "__main__":
    unittest.main()
