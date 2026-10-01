import json
import os
import re
from typing import Any


class LlmClient:
    """보고서와 법률 답변에 선택적으로 사용하는 LLM 공급자 어댑터."""

    def __init__(self, provider: str | None = None, api_key: str | None = None):
        self.provider = (provider or os.environ.get("LLM_PROVIDER", "gemini")).strip().lower()
        self.model = ""
        self.client: Any = None
        self.error = ""

        try:
            if self.provider == "gemini":
                key = api_key or os.environ.get("GEMINI_API_KEY", "").strip()
                self.model = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash").strip()
                if key:
                    from google import genai

                    self.client = genai.Client(api_key=key)
            elif self.provider == "openai":
                key = api_key or os.environ.get("OPENAI_API_KEY", "").strip()
                self.model = os.environ.get("OPENAI_MODEL", "gpt-5.6-terra").strip()
                if key:
                    from openai import OpenAI

                    self.client = OpenAI(api_key=key)
            elif self.provider not in {"none", "disabled"}:
                self.error = f"Unsupported LLM_PROVIDER: {self.provider}"
        except Exception as exc:
            self.error = f"{type(exc).__name__}: {exc}"
            self.client = None

    @property
    def available(self) -> bool:
        return self.client is not None

    def status(self) -> dict[str, Any]:
        return {
            "provider": self.provider,
            "model": self.model,
            "available": self.available,
            "error": self.error,
        }

    def generate_json(
        self,
        prompt: str,
        *,
        schema: dict[str, Any],
        max_output_tokens: int,
    ) -> dict[str, Any]:
        if not self.available:
            raise RuntimeError("LLM provider is not configured")

        if self.provider == "gemini":
            from google.genai import types

            response = self.client.models.generate_content(
                model=self.model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.0,
                    response_mime_type="application/json",
                    response_schema=schema,
                    max_output_tokens=max_output_tokens,
                ),
            )
            text = response.text or "{}"
        else:
            schema_prompt = (
                f"{prompt}\n\nReturn JSON only. JSON schema:\n"
                f"{json.dumps(schema, ensure_ascii=False)}"
            )
            response = self.client.responses.create(
                model=self.model,
                input=schema_prompt,
                max_output_tokens=max_output_tokens,
            )
            text = response.output_text or "{}"
        return json.loads(self._strip_code_fence(text))

    def generate_text(self, prompt: str, *, max_output_tokens: int) -> str:
        if not self.available:
            raise RuntimeError("LLM provider is not configured")

        if self.provider == "gemini":
            from google.genai import types

            response = self.client.models.generate_content(
                model=self.model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.0,
                    top_p=0.9,
                    max_output_tokens=max_output_tokens,
                ),
            )
            return (response.text or "").strip()

        response = self.client.responses.create(
            model=self.model,
            input=prompt,
            max_output_tokens=max_output_tokens,
        )
        return (response.output_text or "").strip()

    def _strip_code_fence(self, text: str) -> str:
        cleaned = text.strip()
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"\s*```$", "", cleaned)
        return cleaned.strip()
