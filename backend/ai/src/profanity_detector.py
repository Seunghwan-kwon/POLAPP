import json
import re
import unicodedata
from pathlib import Path
from typing import Any

from rapidfuzz import fuzz


DEFAULT_PATTERN_PATH = Path(__file__).resolve().parents[1] / "data" / "threat_patterns.json"


class ProfanityDetector:
    """기존 API 클래스명을 유지하는 위협 발화 탐지기."""

    def __init__(self, pattern_path: str | Path | None = None):
        self.pattern_path = Path(pattern_path) if pattern_path else DEFAULT_PATTERN_PATH
        self.categories = self._load_categories()
        self.threshold = 86
        self.alert_score = 2.5

    def _load_categories(self) -> list[dict[str, Any]]:
        if self.pattern_path.exists():
            payload = json.loads(self.pattern_path.read_text(encoding="utf-8"))
            categories = payload.get("categories", [])
            if categories:
                return categories

        return [
            {
                "id": "profanity",
                "label": "욕설",
                "alert_label": "욕설",
                "weight": 2.5,
                "phrases": ["씨발", "시발", "개새끼", "새끼", "병신", "미친놈", "미친년"],
            }
        ]

    def _normalize(self, text: str) -> str:
        text = unicodedata.normalize("NFKC", text).lower()
        text = re.sub(r"[^0-9a-z가-힣\s]", " ", text)
        text = re.sub(r"(.)\1{2,}", r"\1\1", text)
        text = re.sub(r"\s+", " ", text).strip()
        return text

    def _candidates(self, normalized_text: str) -> set[str]:
        tokens = normalized_text.split()
        candidates = set(tokens)
        joined = "".join(tokens)
        if joined:
            candidates.add(joined)

        for idx in range(len(tokens) - 1):
            candidates.add(tokens[idx] + tokens[idx + 1])
            candidates.add(tokens[idx] + " " + tokens[idx + 1])
        for idx in range(len(tokens) - 2):
            candidates.add(tokens[idx] + tokens[idx + 1] + tokens[idx + 2])
            candidates.add(tokens[idx] + " " + tokens[idx + 1] + " " + tokens[idx + 2])
        return candidates

    def detect(self, text: str) -> dict[str, Any]:
        normalized_text = self._normalize(text)
        if not normalized_text:
            return self._empty_result()

        compact_text = normalized_text.replace(" ", "")
        candidates = self._candidates(normalized_text)
        category_results = []

        for category in self.categories:
            score = 0.0
            matches = []
            best_similarity = 0.0
            weight = float(category.get("weight", 2.5))

            for phrase in category.get("phrases", []):
                phrase_norm = self._normalize(str(phrase))
                if not phrase_norm:
                    continue
                phrase_compact = phrase_norm.replace(" ", "")

                if phrase_compact and phrase_compact in compact_text:
                    score += weight
                    matches.append(str(phrase))
                    best_similarity = 100.0
                    continue

                local_best = 0.0
                for candidate in candidates:
                    local_best = max(local_best, float(fuzz.ratio(phrase_norm, candidate)))
                best_similarity = max(best_similarity, local_best)
                if local_best >= self.threshold:
                    score += max(1.8, weight * 0.75)
                    matches.append(str(phrase))

            # 주취 난동은 음주 표현과 난동 행동이 함께 확인될 때만 분류합니다.
            required_groups = category.get("required_groups", [])
            if score == 0.0 and required_groups:
                grouped_matches = []
                for group in required_groups:
                    group_match = next(
                        (
                            str(term)
                            for term in group
                            if self._normalize(str(term)).replace(" ", "") in compact_text
                        ),
                        None,
                    )
                    if group_match is None:
                        grouped_matches = []
                        break
                    grouped_matches.append(group_match)
                if grouped_matches:
                    score += weight
                    matches.extend(grouped_matches)

            if score > 0:
                category_results.append(
                    {
                        "id": str(category.get("id", "unknown")),
                        "label": str(category.get("label", "위협")),
                        "alert_label": str(category.get("alert_label", category.get("label", "위협"))),
                        "score": round(score, 2),
                        "similarity": round(best_similarity, 1),
                        "matched": list(dict.fromkeys(matches)),
                    }
                )

        if not category_results:
            return self._empty_result()

        category_results.sort(key=lambda item: item["score"], reverse=True)
        top = category_results[0]
        total_score = round(sum(item["score"] for item in category_results), 2)
        matched = []
        for item in category_results:
            matched.extend(item["matched"])

        return {
            "is_profanity": total_score >= self.alert_score,
            "score": total_score,
            "matched": list(dict.fromkeys(matched)),
            "category": top["id"],
            "category_label": top["alert_label"],
            "categories": category_results,
        }

    def _empty_result(self) -> dict[str, Any]:
        return {
            "is_profanity": False,
            "score": 0.0,
            "matched": [],
            "category": "none",
            "category_label": "",
            "categories": [],
        }
