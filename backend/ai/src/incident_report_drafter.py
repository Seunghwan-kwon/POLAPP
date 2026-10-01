from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from src.llm_client import LlmClient


REPORT_SCHEMA_VERSION = "k_guardian_report_v2"

_CATEGORY_RULES = (
    ("흉기 관련", (("칼", "흉기", "식칼", "과도", "깨진 병", "찔러", "휘두"),)),
    ("폭행", (("폭행", "때리", "맞았", "주먹", "발로 차", "밀치", "싸우"),)),
    ("가정폭력", (("가정폭력", "남편", "아내", "배우자"), ("때리", "폭행", "위협", "물건을 던"))),
    ("주취난동", (("술", "만취", "취객", "주취"), ("난동", "행패", "고성", "욕설", "폭력", "소리 지"))),
    ("교통사고", (("교통사고", "차에 치", "추돌", "접촉사고", "차량 사고"),)),
    ("절도", (("절도", "훔쳐", "도난", "물건이 없어"),)),
    ("실종", (("실종", "사라졌", "찾을 수 없", "연락이 안"),)),
    ("자해 위험", (("자해", "죽고 싶", "뛰어내", "목숨을 끊"),)),
)

_RISK_PATTERNS = {
    "흉기": ("칼", "흉기", "식칼", "과도", "깨진 병", "찔러", "휘두"),
    "폭행": ("폭행", "때리", "맞았", "주먹", "발로 차", "밀치"),
    "주취": ("술", "만취", "취객", "주취"),
    "난동": ("난동", "행패", "고성", "소리 지", "물건을 던"),
    "부상 가능성": ("다쳤", "다친", "피가", "출혈", "부상", "쓰러"),
    "자해 위험": ("자해", "죽고 싶", "뛰어내", "목숨을 끊"),
}

_ACTION_PATTERNS = {
    "관련자 신원을 확인함": r"신원(?:을|을\s*)?\s*확인(?:하였|했|함|했다)",
    "당사자를 분리함": r"(?:당사자|대상자|가해자|피해자).{0,12}분리(?:하였|했|함|했다)",
    "현장을 통제함": r"현장(?:을|을\s*)?\s*통제(?:하였|했|함|했다)",
    "흉기를 회수함": r"(?:칼|흉기|식칼|과도).{0,12}회수(?:하였|했|함|했다)",
    "구급대를 요청함": r"(?:119|구급대).{0,12}요청(?:하였|했|함|했다)",
    "대상자를 체포함": r"(?:대상자|피의자|가해자).{0,12}체포(?:하였|했|함|했다)",
    "관계자 진술을 확보함": r"진술(?:을|을\s*)?\s*확보(?:하였|했|함|했다)",
    "피해자를 보호 조치함": r"피해자.{0,12}보호\s*조치(?:하였|했|함|했다)",
    "관계기관에 인계함": r"(?:구급대|보호자|관계기관).{0,12}인계(?:하였|했|함|했다)",
}

_KNOWN_UNCERTAIN_ITEMS = {
    "정확한 발생 일시",
    "구체적 발생 장소",
    "관계자 인적사항 및 인원",
    "피해 및 부상 정도",
    "현장 조치 결과",
    "목격자 및 영상 자료 존재 여부",
}


class IncidentReportDrafter:
    """녹음 근거에서 사실을 추출한 뒤 정해진 보고서 형식으로 구성합니다."""

    def __init__(
        self,
        api_key: str | None = None,
        example_path: str | Path | None = None,
    ):
        self.llm = LlmClient(api_key=api_key)

    def draft(self, transcript: str) -> dict[str, Any]:
        transcript = " ".join(transcript.strip().split())
        if not transcript:
            return {
                "draft": "녹음된 대화가 없어 보고서 초안을 생성할 수 없습니다.",
                "facts": {},
                "warnings": ["인식된 음성이 없어 초안을 생성하지 못함"],
                "completeness": 0,
                "review_required": True,
                "used_model": False,
                "schema_version": REPORT_SCHEMA_VERSION,
            }

        facts = self._rule_extract(transcript)
        used_model = False
        if self.llm.available:
            try:
                candidate = self._extract_with_model(transcript)
                facts = self._merge_grounded_model_facts(transcript, facts, candidate)
                used_model = True
            except Exception:
                used_model = False

        facts = self._finalize_facts(facts)
        completeness = self._completeness(facts)
        warnings = self._warnings(facts, used_model)
        return {
            "draft": self._render(facts),
            "facts": facts,
            "warnings": warnings,
            "completeness": completeness,
            "review_required": True,
            "used_model": used_model,
            "schema_version": REPORT_SCHEMA_VERSION,
        }

    def _extract_with_model(self, transcript: str) -> dict[str, Any]:
        prompt = (
            "다음 내용은 경찰 현장에서 녹음된 음성의 STT 결과입니다. "
            "보고서에 필요한 사실을 JSON으로 추출하세요. 원문에 직접 근거가 있는 정보만 "
            "기록하고, 각 값에는 반드시 원문에서 그대로 복사한 짧은 evidence를 붙이세요. "
            "명령이나 예정 사항을 완료된 조치로 기록하지 마세요. 정보가 없으면 빈 값으로 "
            "두고 추측하지 마세요.\n\n"
            f"STT 원문:\n{transcript}"
        )
        item = {
            "type": "object",
            "properties": {
                "value": {"type": "string"},
                "evidence": {"type": "string"},
            },
            "required": ["value", "evidence"],
        }
        schema = {
            "type": "object",
            "properties": {
                "incident_type": item,
                "location": item,
                "occurrence_time": item,
                "observations": {"type": "array", "items": item},
                "actions_taken": {"type": "array", "items": item},
                "risk_factors": {"type": "array", "items": item},
                "people_involved": {"type": "array", "items": item},
                "injuries": {"type": "array", "items": item},
                "weapons": {"type": "array", "items": item},
            },
            "required": [
                "incident_type",
                "location",
                "occurrence_time",
                "observations",
                "actions_taken",
                "risk_factors",
                "people_involved",
                "injuries",
                "weapons",
            ],
        }
        return self.llm.generate_json(prompt, schema=schema, max_output_tokens=1100)

    def _rule_extract(self, transcript: str) -> dict[str, Any]:
        lowered = transcript.casefold()
        incident_type = "현장 확인"
        incident_score = 0
        incident_evidence: list[str] = []

        for candidate, required_groups in _CATEGORY_RULES:
            matched_groups = [
                [keyword for keyword in group if keyword.casefold() in lowered]
                for group in required_groups
            ]
            if not all(matched_groups):
                continue
            score = sum(len(group) for group in matched_groups)
            if score > incident_score:
                incident_type = candidate
                incident_score = score
                incident_evidence = self._find_phrases(
                    transcript,
                    [keyword for group in matched_groups for keyword in group],
                )

        risk_factors: list[str] = []
        evidence_phrases = list(incident_evidence)
        for label, keywords in _RISK_PATTERNS.items():
            matched = [keyword for keyword in keywords if keyword.casefold() in lowered]
            if matched:
                risk_factors.append(label)
                evidence_phrases.extend(self._find_phrases(transcript, matched))

        actions_taken = [
            label
            for label, pattern in _ACTION_PATTERNS.items()
            if re.search(pattern, transcript, flags=re.IGNORECASE)
        ]
        observations = self._build_rule_observations(incident_type, risk_factors)
        location = self._extract_location(transcript)
        occurrence_time = self._extract_time(transcript)
        people = self._extract_people(transcript)
        injuries = self._extract_injuries(transcript)
        weapons = self._extract_weapons(transcript)

        return {
            "incident_type": incident_type,
            "location": location,
            "occurrence_time": occurrence_time,
            "observations": observations,
            "actions_taken": actions_taken,
            "risk_factors": risk_factors,
            "people_involved": people,
            "injuries": injuries,
            "weapons": weapons,
            "evidence_phrases": self._unique(evidence_phrases),
            "uncertain_items": [],
        }

    def _merge_grounded_model_facts(
        self,
        transcript: str,
        base: dict[str, Any],
        candidate: dict[str, Any],
    ) -> dict[str, Any]:
        merged = {key: list(value) if isinstance(value, list) else value for key, value in base.items()}

        for field in ("incident_type", "location", "occurrence_time"):
            accepted = self._grounded_value(transcript, candidate.get(field))
            if accepted:
                merged[field] = accepted[0]
                merged["evidence_phrases"].append(accepted[1])

        for field in (
            "observations",
            "actions_taken",
            "risk_factors",
            "people_involved",
            "injuries",
            "weapons",
        ):
            accepted_values: list[str] = []
            for item in candidate.get(field, []) if isinstance(candidate.get(field), list) else []:
                accepted = self._grounded_value(transcript, item)
                if not accepted:
                    continue
                value, evidence = accepted
                if field == "actions_taken" and not self._looks_like_completed_action(evidence):
                    continue
                accepted_values.append(value)
                merged["evidence_phrases"].append(evidence)
            merged[field] = self._unique([*merged.get(field, []), *accepted_values])

        merged["evidence_phrases"] = self._unique(merged["evidence_phrases"])
        return merged

    def _grounded_value(self, transcript: str, item: Any) -> tuple[str, str] | None:
        if not isinstance(item, dict):
            return None
        value = " ".join(str(item.get("value", "")).strip().split())
        evidence = " ".join(str(item.get("evidence", "")).strip().split())
        if not value or len(evidence) < 2:
            return None
        if self._normalize_for_match(evidence) not in self._normalize_for_match(transcript):
            return None
        return value[:160], evidence[:160]

    def _finalize_facts(self, facts: dict[str, Any]) -> dict[str, Any]:
        for field in (
            "observations",
            "actions_taken",
            "risk_factors",
            "people_involved",
            "injuries",
            "weapons",
            "evidence_phrases",
        ):
            facts[field] = self._unique([str(value) for value in facts.get(field, [])])

        uncertain: list[str] = []
        if not facts.get("occurrence_time"):
            uncertain.append("정확한 발생 일시")
        if not facts.get("location"):
            uncertain.append("구체적 발생 장소")
        if not facts.get("people_involved"):
            uncertain.append("관계자 인적사항 및 인원")
        if not facts.get("injuries"):
            uncertain.append("피해 및 부상 정도")
        if not facts.get("actions_taken"):
            uncertain.append("현장 조치 결과")
        uncertain.append("목격자 및 영상 자료 존재 여부")
        facts["uncertain_items"] = [item for item in self._unique(uncertain) if item in _KNOWN_UNCERTAIN_ITEMS]
        facts["summary"] = self._build_summary(facts)
        return facts

    def _render(self, facts: dict[str, Any]) -> str:
        return (
            f"1. 사건 유형: {facts.get('incident_type') or '현장 확인'}\n"
            f"2. 상황 개요: {facts.get('summary') or '녹음 내용을 바탕으로 추가 확인이 필요한 상황.'}\n"
            f"3. 현장 확인 사항: {self._join_or_missing(facts.get('observations'), '녹음 내용만으로 직접 확인된 현장 사실 없음')}\n"
            f"4. 위험 요소: {self._join_or_missing(facts.get('risk_factors'), '확인된 위험 요소 없음')}\n"
            f"5. 현장 조치 사항: {self._join_or_missing(facts.get('actions_taken'), '녹음 내용에서 완료된 조치 확인되지 않음')}\n"
            f"6. 추가 확인 필요: {self._join_or_missing(facts.get('uncertain_items'), '없음')}"
        )

    def _warnings(self, facts: dict[str, Any], used_model: bool) -> list[str]:
        warnings = ["AI가 작성한 초안이므로 제출 전 담당 경찰관의 사실 확인이 필요함"]
        if not used_model:
            warnings.append("모델 기반 사실 추출을 사용할 수 없어 규칙 기반 결과로 생성됨")
        if facts.get("uncertain_items"):
            warnings.append("미확인 항목이 있어 추가 입력이 필요함")
        if not facts.get("evidence_phrases"):
            warnings.append("위험 상황을 뒷받침하는 직접 발화 근거가 부족함")
        return warnings

    def _completeness(self, facts: dict[str, Any]) -> int:
        checks = (
            facts.get("incident_type") not in (None, "", "현장 확인"),
            bool(facts.get("occurrence_time")),
            bool(facts.get("location")),
            bool(facts.get("people_involved")),
            bool(facts.get("observations")),
            bool(facts.get("actions_taken")),
        )
        return round(sum(bool(value) for value in checks) / len(checks) * 100)

    def _build_summary(self, facts: dict[str, Any]) -> str:
        prefix = " ".join(
            value
            for value in (str(facts.get("occurrence_time") or ""), str(facts.get("location") or ""))
            if value
        )
        incident_type = str(facts.get("incident_type") or "현장 확인")
        description = (
            "현장 상황과 관련된 내용이 녹음에서 확인되어 사실관계 확인이 필요한 사안."
            if incident_type == "현장 확인"
            else f"{incident_type} 관련 내용이 녹음에서 확인되어 사실관계 확인이 필요한 사안."
        )
        return f"{prefix} {description}".strip()

    def _build_rule_observations(self, incident_type: str, risks: list[str]) -> list[str]:
        observations: list[str] = []
        if incident_type != "현장 확인":
            observations.append(f"{incident_type} 관련 발화 또는 정황이 녹음에서 확인됨")
        if "부상 가능성" in risks:
            observations.append("부상과 관련된 발화가 확인됨")
        if "흉기" in risks:
            observations.append("흉기 소지 또는 사용 가능성과 관련된 발화가 확인됨")
        return self._unique(observations)

    def _extract_location(self, transcript: str) -> str:
        patterns = (
            r"([가-힣A-Za-z0-9]+(?:아파트|공원|주차장|편의점|주점|상가|학교|놀이터|광장|복도|계단|도로|역))",
            r"([가-힣A-Za-z0-9]+(?:동|로|길)\s*\d+(?:번길)?(?:\s*\d+)?)",
        )
        for pattern in patterns:
            match = re.search(pattern, transcript)
            if match:
                return match.group(1).strip()
        return ""

    def _extract_time(self, transcript: str) -> str:
        patterns = (
            r"(?:오늘|어제|금일)?\s*(?:오전|오후)?\s*\d{1,2}\s*시(?:\s*\d{1,2}\s*분)?(?:경)?",
            r"\d{1,2}\s*월\s*\d{1,2}\s*일(?:\s*(?:오전|오후)?\s*\d{1,2}\s*시)?",
        )
        for pattern in patterns:
            match = re.search(pattern, transcript)
            if match:
                return " ".join(match.group(0).split())
        return ""

    def _extract_people(self, transcript: str) -> list[str]:
        labels = ("신고자", "피해자", "가해자", "피의자", "목격자", "보호자", "아동", "대상자")
        return [label for label in labels if label in transcript]

    def _extract_injuries(self, transcript: str) -> list[str]:
        results = []
        for phrase in self._find_phrases(transcript, ["다쳤", "다친", "피가", "출혈", "부상", "쓰러"]):
            results.append(phrase)
        return self._unique(results)

    def _extract_weapons(self, transcript: str) -> list[str]:
        labels = ("칼", "흉기", "식칼", "과도", "깨진 병")
        return [label for label in labels if label in transcript]

    def _find_phrases(self, transcript: str, keywords: list[str]) -> list[str]:
        sentences = re.split(r"(?<=[.!?。])\s+|(?<=다)\s+|(?<=요)\s+", transcript)
        return [
            sentence.strip()[:160]
            for sentence in sentences
            if sentence.strip() and any(keyword.casefold() in sentence.casefold() for keyword in keywords)
        ]

    def _looks_like_completed_action(self, evidence: str) -> bool:
        return any(re.search(pattern, evidence, flags=re.IGNORECASE) for pattern in _ACTION_PATTERNS.values())

    def _normalize_for_match(self, value: str) -> str:
        return re.sub(r"\s+", "", value).casefold()

    def _join_or_missing(self, value: Any, missing: str) -> str:
        if isinstance(value, list):
            joined = ", ".join(str(item) for item in value if str(item).strip())
            return joined or missing
        return str(value or missing)

    def _unique(self, values: list[str]) -> list[str]:
        return list(dict.fromkeys(value.strip() for value in values if value.strip()))
