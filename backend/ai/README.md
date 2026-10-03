# POLAPP AI 서버

현장 음성을 전사하고 위험도를 분석하며, 법률 질의와 보고서 초안을 제공하는 로컬 HTTP 서버입니다.

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
.\start_ai.ps1
```

상태 확인은 `http://localhost:8765/health`를 사용합니다. 모델 구성과 판정 기준은 [`../../docs/AI_모델_및_판정_기준.md`](../../docs/AI_모델_및_판정_기준.md), 전체 실행 순서는 [`../../docs/실행_가이드.md`](../../docs/실행_가이드.md)를 확인하세요.

실제 키는 `.env`에만 입력하며 저장소에 커밋하지 않습니다. `models/`의 ONNX 파일은 실행에 필요하고 Git LFS로 관리합니다.
