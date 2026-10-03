import json
import os
import re
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from src.llm_client import LlmClient
from pypdf import PdfReader


DEFAULT_CACHE_PATH = Path("data") / "legal_rag_index.json"
DEFAULT_LAW_NAMES = ["도로교통법", "도로교통법 시행령", "도로교통법 시행규칙", "경범죄 처벌법", "경찰관 직무집행법"]
INITIAL_CANDIDATE_COUNT = 12


class RoadTrafficLawRAG:
    def __init__(
        self,
        pdf_path: str | Path | None = None,
        pdf_paths: list[str | Path] | None = None,
        cache_path: str | Path | None = None,
        api_key: str | None = None,
        law_api_key: str | None = None,
    ):
        if pdf_paths:
            self.pdf_paths = [Path(path) for path in pdf_paths]
        elif pdf_path:
            self.pdf_paths = [Path(pdf_path)]
        else:
            self.pdf_paths = []
        self.cache_path = Path(cache_path) if cache_path else DEFAULT_CACHE_PATH
        self.llm = LlmClient(api_key=api_key)
        self.law_api_key = law_api_key or self._read_law_api_key()
        self.chunks: list[dict[str, Any]] = []

    def answer(self, question: str, top_k: int = 5) -> dict[str, Any]:
        self.ensure_index()
        dui_penalty = self._answer_dui_penalty(question)
        if dui_penalty:
            return dui_penalty

        candidates = self.retrieve(question, top_k=max(top_k, INITIAL_CANDIDATE_COUNT))
        if not candidates:
            return {"answer": "관련 법령 조항을 찾지 못했습니다.", "citations": [], "used_model": False}

        if not self.llm.available:
            answer = self._build_concise_answer_from_candidates(candidates)
            return {"answer": answer, "citations": self._format_citations(candidates[:top_k]), "used_model": False}

        try:
            answer_text, selected_ids = self._model_answer(question, candidates)
            selected = [item for item in candidates if item["id"] in selected_ids] or candidates[:top_k]
            return {
                "answer": self._format_final_answer(answer_text),
                "citations": self._format_citations(selected),
                "used_model": True,
            }
        except Exception as exc:
            answer = self._build_concise_answer_from_candidates(candidates)
            if not answer:
                answer = f"법률 답변 생성에 실패했습니다. ({type(exc).__name__})"
            return {"answer": answer, "citations": self._format_citations(candidates[:top_k]), "used_model": False}

    def ensure_index(self) -> None:
        cache = self._load_cache()

        if self.law_api_key:
            try:
                chunks = self._extract_chunks_from_law_api()
                if chunks:
                    self.chunks = chunks
                    self._save_cache()
                    return
            except Exception:
                pass

        if cache and cache.get("chunks"):
            self.chunks = cache["chunks"]
            return

        chunks = self._extract_chunks_from_pdfs() if self.pdf_paths else []
        if not chunks:
            raise FileNotFoundError("법률 인덱스를 만들 공식 법령 API, 기존 캐시 또는 PDF 원문을 찾지 못했습니다.")

        self.chunks = chunks
        self._save_cache()

    def retrieve(self, question: str, top_k: int = INITIAL_CANDIDATE_COUNT) -> list[dict[str, Any]]:
        normalized_question = self._normalize(question)
        query_terms = self._query_terms(normalized_question)
        scored = []

        for chunk in self.chunks:
            haystack = self._normalize(chunk.get("search_text") or chunk.get("text", ""))
            score = 0.0
            if normalized_question and normalized_question in haystack:
                score += 12.0
            for term in query_terms:
                if term in haystack:
                    score += 1.0 + min(haystack.count(term), 3)
                    if term in self._normalize(chunk.get("heading", "")):
                        score += 3.0
            score += self._intent_bonus(normalized_question, haystack)
            score += self._penalty_bonus(normalized_question, chunk)
            if score > 0:
                scored.append({"id": chunk["id"], "chunk": chunk, "score": score})

        scored.sort(key=lambda item: item["score"], reverse=True)
        return scored[:top_k]

    def _model_answer(self, question: str, candidates: list[dict[str, Any]]) -> tuple[str, list[str]]:
        compact_candidates = []
        for item in candidates:
            chunk = item["chunk"]
            compact_candidates.append(
                {
                    "id": chunk["id"],
                    "law_title": chunk.get("law_title", ""),
                    "heading": chunk.get("heading", ""),
                    "text": re.sub(r"\s+", " ", chunk.get("text", ""))[:900],
                }
            )

        prompt = (
            "당신은 경찰 현장 법률 질의에 답하는 보조 AI입니다. "
            "반드시 제공된 후보 조항 안의 내용만 근거로 답하세요. "
            "근거가 부족하면 부족하다고 말하세요. 답변은 짧고 명확하게 작성하세요. "
            "반드시 JSON만 반환하세요.\n\n"
            f"질문: {question}\n\n"
            f"후보 조항: {json.dumps(compact_candidates, ensure_ascii=False)}\n\n"
            '출력 형식: {"answer":"답변", "selected_ids":["id"]}'
        )
        payload = self.llm.generate_json(
            prompt,
            schema={
                    "type": "object",
                    "properties": {
                        "answer": {"type": "string"},
                        "selected_ids": {"type": "array", "items": {"type": "string"}},
                    },
                    "required": ["answer", "selected_ids"],
                },
            max_output_tokens=500,
        )
        return str(payload.get("answer", "")).strip(), [str(item) for item in payload.get("selected_ids", [])]

    def _extract_chunks_from_law_api(self) -> list[dict[str, Any]]:
        chunks = []
        for law_name in DEFAULT_LAW_NAMES:
            for detail in self._fetch_law_details(law_name):
                chunks.extend(self._chunks_from_law_detail(law_name, detail, len(chunks)))
        return chunks

    def _fetch_law_details(self, law_name: str) -> list[Any]:
        details = []
        search_url = "https://www.law.go.kr/DRF/lawSearch.do?" + urllib.parse.urlencode(
            {"OC": self.law_api_key, "target": "law", "type": "JSON", "query": law_name}
        )
        try:
            search_payload = self._read_json(search_url)
        except Exception:
            return details

        law_ids = self._collect_law_ids(search_payload)
        for law_id in law_ids[:3]:
            detail_url = "https://www.law.go.kr/DRF/lawService.do?" + urllib.parse.urlencode(
                {"OC": self.law_api_key, "target": "law", "type": "JSON", "MST": law_id}
            )
            try:
                details.append(self._read_json(detail_url))
            except Exception:
                continue
        return details

    def _chunks_from_law_detail(self, fallback_title: str, detail: Any, offset: int) -> list[dict[str, Any]]:
        title = self._first_string_by_key(detail, ["법령명_한글", "법령명한글", "법령명"]) or fallback_title
        article_texts = self._collect_article_texts(detail)
        chunks = []
        for idx, article in enumerate(article_texts, start=1):
            text = re.sub(r"\s+", " ", article).strip()
            if len(text) < 20:
                continue
            heading = self._article_heading(text) or f"조문 {idx}"
            chunk_id = f"law-{offset + len(chunks) + 1}"
            chunks.append(
                {
                    "id": chunk_id,
                    "law_title": title,
                    "heading": heading,
                    "text": text,
                    "page_label": "공식 법령 API",
                    "search_text": f"{title} {heading} {text}",
                }
            )
        return chunks

    def _extract_chunks_from_pdfs(self) -> list[dict[str, Any]]:
        chunks = []
        for pdf_path in self.pdf_paths:
            if not pdf_path.exists():
                continue
            reader = PdfReader(str(pdf_path))
            title = pdf_path.stem.split("(", 1)[0]
            for page_number, page in enumerate(reader.pages, start=1):
                text = re.sub(r"\s+", " ", page.extract_text() or "").strip()
                if len(text) < 20:
                    continue
                chunk_id = f"pdf-{len(chunks) + 1}"
                chunks.append(
                    {
                        "id": chunk_id,
                        "law_title": title,
                        "heading": f"p.{page_number}",
                        "text": text,
                        "page_label": str(page_number),
                        "search_text": f"{title} p.{page_number} {text}",
                    }
                )
        return chunks

    def _read_json(self, url: str) -> Any:
        request = urllib.request.Request(url, headers={"User-Agent": "POLAPP-AI/1.0"})
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))

    def _collect_law_ids(self, payload: Any) -> list[str]:
        ids = []
        if isinstance(payload, dict):
            for key, value in payload.items():
                key_text = str(key)
                if key_text in {"법령일련번호", "MST", "mst"} and value:
                    ids.append(str(value))
                ids.extend(self._collect_law_ids(value))
        elif isinstance(payload, list):
            for item in payload:
                ids.extend(self._collect_law_ids(item))
        return list(dict.fromkeys(ids))

    def _collect_article_texts(self, payload: Any) -> list[str]:
        texts = []
        if isinstance(payload, dict):
            joined_parts = []
            for key, value in payload.items():
                key_text = str(key)
                if "조문" in key_text and isinstance(value, str):
                    joined_parts.append(value)
                else:
                    texts.extend(self._collect_article_texts(value))
            if joined_parts:
                texts.append(" ".join(joined_parts))
        elif isinstance(payload, list):
            for item in payload:
                texts.extend(self._collect_article_texts(item))
        return list(dict.fromkeys(texts))

    def _first_string_by_key(self, payload: Any, keys: list[str]) -> str:
        if isinstance(payload, dict):
            for key in keys:
                value = payload.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip()
            for value in payload.values():
                result = self._first_string_by_key(value, keys)
                if result:
                    return result
        elif isinstance(payload, list):
            for item in payload:
                result = self._first_string_by_key(item, keys)
                if result:
                    return result
        return ""

    def _article_heading(self, text: str) -> str:
        match = re.search(r"제\s*\d+\s*조(?:의\d+)?\s*\([^)]*\)", text)
        return match.group(0) if match else ""

    def _build_concise_answer_from_candidates(self, candidates: list[dict[str, Any]]) -> str:
        lines = []
        for item in candidates[:3]:
            chunk = item["chunk"]
            sentence = re.split(r"(?<=[.다])\s+", chunk.get("text", ""))[0].strip()
            if sentence:
                lines.append(sentence[:220])
        return "\n".join(f"{idx}. {line}" for idx, line in enumerate(lines, start=1))

    def _format_citations(self, retrieved: list[dict[str, Any]]) -> list[str]:
        citations = []
        for item in retrieved:
            chunk = item["chunk"]
            citations.append(f"{chunk.get('law_title', '')} {chunk.get('heading', '')} ({chunk.get('page_label', '근거 조항')})")
        return list(dict.fromkeys(citations))

    def _format_final_answer(self, text: str) -> str:
        return re.sub(r"\n{3,}", "\n\n", text.strip())

    def _answer_dui_penalty(self, question: str) -> dict[str, Any] | None:
        normalized = self._normalize(question)
        compact = normalized.replace(" ", "")
        is_dui = any(term in compact for term in ["음주운전", "음주", "혈중알코올농도", "술취한상태"])
        asks_penalty = any(term in compact for term in ["벌금", "처벌", "징역", "형량", "기준", "얼마"])
        if not (is_dui and asks_penalty):
            return None

        citations = self._dui_citations()
        answer = (
            "음주운전 처벌 기준은 혈중알코올농도 구간에 따라 달라집니다.\n"
            "1. 0.03% 이상 0.08% 미만: 1년 이하의 징역 또는 500만 원 이하의 벌금.\n"
            "2. 0.08% 이상 0.2% 미만: 1년 이상 2년 이하의 징역 또는 500만 원 이상 1천만 원 이하의 벌금.\n"
            "3. 0.2% 이상: 2년 이상 5년 이하의 징역 또는 1천만 원 이상 2천만 원 이하의 벌금.\n"
            "4. 음주측정 거부: 1년 이상 5년 이하의 징역 또는 500만 원 이상 2천만 원 이하의 벌금.\n\n"
            "면허 행정처분은 별도로 적용되며, 0.08% 이상은 면허취소 기준에 해당할 수 있습니다."
        )
        return {"answer": answer, "citations": citations, "used_model": False}

    def _dui_citations(self) -> list[str]:
        preferred = []
        for chunk in self.chunks:
            law_title = chunk.get("law_title", "")
            heading = chunk.get("heading", "")
            if law_title == "도로교통법" and (
                "제148조의2" in heading or "제44조" in heading or "제93조" in heading
            ):
                preferred.append({"chunk": chunk})
        preferred.sort(
            key=lambda item: (
                0 if "제148조의2" in item["chunk"].get("heading", "") else
                1 if "제44조" in item["chunk"].get("heading", "") else
                2
            )
        )
        return self._format_citations(preferred[:3])

    def _penalty_bonus(self, question: str, chunk: dict[str, Any]) -> float:
        compact = question.replace(" ", "")
        heading = chunk.get("heading", "")
        text = chunk.get("text", "")
        law_title = chunk.get("law_title", "")
        asks_penalty = any(term in compact for term in ["벌금", "처벌", "징역", "형량", "얼마"])
        asks_dui = any(term in compact for term in ["음주운전", "음주", "혈중알코올농도"])
        if not (asks_penalty and asks_dui and law_title == "도로교통법"):
            return 0.0
        if "제148조의2" in heading:
            return 80.0
        if "제44조" in heading:
            return 25.0
        if "제93조" in heading:
            return 20.0
        if "운전면허" in text and ("취소" in text or "정지" in text):
            return 5.0
        return 0.0

    def _intent_bonus(self, question: str, haystack: str) -> float:
        bonus = 0.0
        groups = {
            "speed": ["속도", "과속", "제한속도", "범칙금", "과태료", "제한 속도"],
            "dui": ["음주", "음주운전", "술", "취한", "주취", "면허", "취소", "정지", "제44조"],
            "weapon": ["흉기", "칼", "위협", "폭행", "경범죄", "난동"],
        }
        for terms in groups.values():
            if any(term in question for term in terms):
                bonus += sum(3.0 for term in terms if term in haystack)
        return bonus

    def _query_terms(self, normalized_question: str) -> list[str]:
        tokens = [token for token in normalized_question.split() if len(token) >= 2]
        terms = set(tokens)
        compact = normalized_question.replace(" ", "")
        if len(compact) >= 2:
            terms.add(compact)
        for idx in range(len(tokens) - 1):
            terms.add(tokens[idx] + tokens[idx + 1])

        expansions = {
            "음주운전": ["음주", "술", "취한", "주취", "운전", "면허", "제44조", "도로교통법"],
            "음주": ["술", "취한", "주취", "운전", "면허", "제44조"],
            "과속": ["속도", "제한속도", "최고속도", "범칙금", "과태료"],
            "칼": ["흉기", "위협", "폭행", "경범죄"],
            "흉기": ["칼", "위협", "폭행", "경범죄"],
        }
        for trigger, extra_terms in expansions.items():
            if trigger in normalized_question or trigger in compact:
                terms.update(extra_terms)
        return list(terms)

    def _normalize(self, text: str) -> str:
        text = text.lower()
        text = re.sub(r"[^0-9a-z가-힣\s]", " ", text)
        text = re.sub(r"\s+", " ", text)
        return text.strip()

    def _load_cache(self) -> dict[str, Any] | None:
        if not self.cache_path.exists():
            return None
        try:
            return json.loads(self.cache_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return None

    def _save_cache(self) -> None:
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"source": "official_law_api_or_pdf", "chunks": self.chunks}
        self.cache_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    def _read_law_api_key(self) -> str:
        return os.environ.get("LAW_API_KEY", "").strip() or os.environ.get(
            "LAW_OPEN_API_KEY", ""
        ).strip()
