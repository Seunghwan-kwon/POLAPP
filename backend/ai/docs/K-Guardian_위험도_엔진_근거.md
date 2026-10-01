# POLAPP K-Guardian 음향 위험도 엔진

## 1. 적용 범위

현재 버전은 스마트폰 마이크 입력만을 이용하는 **현장 경찰관 의사결정 보조 기능**이다. 출력 레벨은 폭력 발생 확률이나 자동 조치 명령이 아니며, 현장 경찰관과 지휘 체계의 판단을 대체하지 않는다.

| 신호 | 구현 내용 | 현재 상태 |
|---|---|---|
| E | RMS, 피크, 음량 변동, 기본주파수 변동, 발화 속도로 구성한 음향 활성도 | 즉시 사용 가능 |
| K | 기존 위협 표현 규칙 + KCDD 문맥 분류 모델 | ONNX 설치 및 사용 중 |
| C | YAMNet의 crowd/speech babble 계열 음향 점수 | ONNX 설치 및 사용 중 |
| S | YAMNet의 비명, 고함, 충격, 파손, 총성 계열 음향 점수 | ONNX 설치 및 사용 중 |
| T | 최근 30초 신호 반복, 동일 범주 반복, 상승 추세 | 즉시 사용 가능 |

카메라 권한은 허용되었지만, 현재 확보된 공개 데이터만으로 실제 경찰 출동 환경의 거리, 흉기, 신체 접촉을 신뢰성 있게 검증할 수 없으므로 시각 판정은 이번 구현에서 제외했다. 관제 시스템 연동도 기존 운영 백엔드에 접근할 수 없어 제외했다.

## 2. 근거와 설계 원칙

- 경찰 바디캠 음향에서 강도와 반복 같은 음향 단서로 갈등 구간을 우선 탐색할 수 있다는 연구 결과를 참고했다: [Automatic Conflict Detection in Police Body-Worn Audio](https://arxiv.org/abs/1711.05355).
- 음성의 주파수, 에너지, 스펙트럼 관련 최소 특징 집합 설계는 [eGeMAPS](https://doi.org/10.1109/TAFFC.2015.2457417)를 참고했다. 현재 코드는 eGeMAPS 전체 구현이 아니라 모바일 백엔드에서 계산 가능한 해석 가능한 부분집합이다.
- 한국어 대화 문맥 분류 학습에는 22,249개 대화와 5개 범주를 제공하는 [KCDD](https://aclanthology.org/2024.findings-eacl.42/)의 공식 분할을 사용한다.
- 군중과 위험 음향은 AudioSet 521개 사건 클래스로 학습된 [YAMNet](https://www.tensorflow.org/hub/tutorials/yamnet)을 사용한다.
- 실제 배치 전 위험, 한계, 성능, 개인정보를 기록하고 사람의 감독을 유지하는 원칙은 [NIST AI RMF](https://www.nist.gov/itl/ai-risk-management-framework)를 따른다.

가중합을 AHP라고 부르지 않는다. 전문가 쌍대비교 조사를 수행하지 않았기 때문이다. 알고리즘 명칭은 `k_guardian_audio_evidence_v1`이며, 레벨 승급 규칙과 범주 심각도는 `data/risk_policy.json`에 공개한다.

## 3. 레벨 해석

| 레벨 | 표시 | 의미 |
|---|---|---|
| 1 | 일반 대응 | 뚜렷한 음향 위험 근거 없음 |
| 2 | 주의 | 단일 약한 신호 또는 복수의 경미한 신호 |
| 3 | 고위험 | 강한 위협 문맥/위험 음향 또는 복수 근거의 교차 확인 |
| 4 | 긴급 | 강한 위협 신호가 다른 독립 신호로 보강되거나 반복·상승한 경우 |

`evidence_index`는 내부 비교와 평가를 위한 0~100 지표이며 확률로 해석하면 안 된다. 레벨 4는 단일 욕설이나 단일 키워드만으로 생성되지 않도록 교차 근거를 요구한다.

## 4. 모델 산출물 설치

KCDD 코랩 노트북 결과 압축을 풀어 다음 파일을 배치한다.

```text
models/guardian_context_model/
  model.int8.onnx
  tokenizer.json
  labels.json
  thresholds.json
  metrics.json
  model_card.md
```

YAMNet 코랩 노트북 결과는 다음과 같이 배치한다.

```text
models/yamnet/
  yamnet.onnx
  yamnet_class_map.csv
  event_groups.json
  model_card.md
```

모델 파일이 없거나 로드에 실패하면 `/health`가 `ready: false`를 반환하여 앱은 데모 모드로 전환한다. 개별 분석 응답에도 `available: false`가 표시된다.

## 5. 평가 녹음

평가용 녹음 저장은 기본 비활성화다.

```powershell
$env:POLAPP_EVAL_RECORDINGS='1'
$env:POLAPP_EVAL_INCLUDE_TRANSCRIPT='1' # 별도 동의가 있을 때만
python ai_server.py
```

기본 보존 기간은 14일, 최대 1,000건이다. 파일은 `data/evaluation/`에 저장되고 Git에서 제외된다. 세션 ID는 해시로만 기록되며 위치·경찰관 식별자는 수집하지 않는다. 실제 연구 평가에는 기관 승인, 참여자 고지·동의, 비식별화, 접근 통제, 폐기 절차가 추가로 필요하다.

## 6. 검증 시 보고할 지표

- 위험 문맥: 범주별 Precision/Recall/F1, Macro-F1, confusion matrix, 3개 seed 평균과 표준편차
- 위험 레벨: Level 3~4를 양성으로 둔 Recall/Precision/F1, false alarms per hour, 탐지 지연
- 음향 사건: 군중/위험 음향별 event-based F1과 false positives per hour
- 시스템: 8초 연속 분석 창별 end-to-end 지연의 중앙값/P95, CPU 사용량, 모델 미탑재/실패율
- 현장 검증: 장소·기기·소음 조건을 분리한 외부 테스트와 경찰관 검토자 간 일치도(Cohen's kappa)
