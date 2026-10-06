# POLAPP AI 서버

현장 음성을 전사하고 위험도를 분석하며 법률 질의와 보고서 초안을 제공하는 Python HTTP 서버입니다.

## 설치와 실행

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
.\start_ai.ps1
```

상태 확인 주소는 `http://localhost:8765/health`입니다.

## 모델 파일

실행에 필요한 ONNX 모델은 `models/`에 포함되어 있고 Git LFS로 관리합니다. 클론한 모델 파일이 LFS 포인터로만 보이면 저장소 루트에서 아래 명령을 실행합니다.

```powershell
git lfs install
git lfs pull
```

## 선택 설정

- `LLM_PROVIDER=gemini`: `GEMINI_API_KEY` 사용
- `LLM_PROVIDER=openai`: `OPENAI_API_KEY` 사용
- API 키 없음: 법률 질의와 보고서 초안의 규칙 기반 대체 경로 사용
- `AI_SERVER_TOKEN`: 앱의 `--dart-define=AI_SERVER_TOKEN=...`과 같은 값 사용

실제 키는 `.env`에만 저장하고 커밋하지 않습니다. 전체 실행 순서는 [로컬 실행 가이드](../../docs/실행_가이드.md), 모델과 위험도 산출 방식은 [AI 모델 및 판정 기준](../../docs/AI_모델_및_판정_기준.md)을 확인합니다.
