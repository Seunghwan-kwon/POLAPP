# POLAPP 로컬 연동 백엔드

현장 앱과 관리자 웹의 로그인, 위치, 메시지, 신고, 위험 알림, 최신 카메라 프레임을 로컬에서 검증하는 Flask/Socket.IO 서버입니다. 팀 백엔드를 교체하기 위한 구현이 아니며 실제 반영 계약은 [`../../docs/팀_백엔드_연동_계약.md`](../../docs/팀_백엔드_연동_계약.md)를 기준으로 합니다.

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
.\start_backend.ps1
```

서버 상태는 `http://localhost:4440/health`에서 확인합니다. 테스트 계정은 루트 [실행 가이드](../../docs/실행_가이드.md)에 정리되어 있습니다.

로컬 DB `data/polapp_local.db`는 최초 실행 때 자동 생성되며 Git에 포함되지 않습니다. 공유 환경에서는 `.env`의 두 비밀값을 반드시 설정하세요.
