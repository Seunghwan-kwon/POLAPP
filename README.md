# POLAPP 프로젝트 안내

POLAPP은 현장 경찰관용 Flutter 앱, 관리자 관제 웹, AI 분석 서버와 로컬 연동 백엔드를 한 저장소에서 관리하는 졸업작품 프로젝트입니다.

## 구성

- `lib/`: 현장 앱과 관리자 웹 공용 Flutter 코드
- `assets/`: 치안 히트맵 데이터와 모바일 흉기 탐지 ONNX 모델
- `backend/ai/`: STT, 위험도 분석, 법률 질의, 보고서 초안 서버
- `backend/admin-local/`: 팀 백엔드 연동 전 검증을 위한 로컬 기준 구현
- `tools/colab/`: 모델 학습·내보내기 노트북
- `docs/`: 구조, 실행법, 팀 백엔드 적용 계약

관리자 웹은 별도 프런트엔드가 아니라 같은 Flutter 프로젝트의 웹 빌드입니다. 로컬 관리자 백엔드는 팀 백엔드를 교체하기 위한 코드가 아니라 앱과 AI 확장 기능을 독립적으로 시험하기 위한 기준 구현입니다.

## 빠른 시작

필요한 키와 로컬 주소는 저장소에 커밋하지 않습니다. `.env.example`을 참고하고 실제 값은 실행 인자로 전달합니다.

```powershell
flutter pub get
flutter run `
  --dart-define=NAVER_MAP_CLIENT_ID=YOUR_CLIENT_ID `
  --dart-define=API_SERVER_URL=http://YOUR_SERVER_IP:4440 `
  --dart-define=WS_SERVER_URL=http://YOUR_SERVER_IP:4440 `
  --dart-define=AI_SERVER_URL=http://YOUR_SERVER_IP:8765
```

전체 실행 순서와 관리자 웹 명령은 [실행 가이드](docs/실행_가이드.md)를 확인하세요. 팀 백엔드에 위험 알림과 카메라 연동을 적용할 때는 [백엔드 연동 계약](docs/팀_백엔드_연동_계약.md)을 기준으로 사용합니다.

## 저장소 규칙

- 실제 API 키, 토큰, 개인 IP와 로컬 DB는 커밋하지 않음
- ONNX 모델은 Git LFS로 관리함
- 기능 브랜치에서 작업하고 Pull Request로 병합함
- 모델 출력은 현장 판단 보조 정보이며 자동 조치의 근거로 사용하지 않음

협업 규칙은 [COLLABORATION.md](COLLABORATION.md)에 정리되어 있습니다.
