# POLAPP

현장 경찰관용 Flutter 앱, 관리자 관제 웹, AI 분석 서버를 포함한 졸업작품 저장소입니다.

이 브랜치의 백엔드는 팀원이 작성한 Node.js 코드를 그대로 기준으로 삼습니다. 기존 로그인, 위치 공유, 메시지, 신고 기능은 유지하고, 위험 알림과 카메라 중계만 `backend/src/AiIntegration.ts`에 분리해 추가했습니다. 이 코드는 운영 백엔드 교체본이 아니라 백엔드 담당자가 실제 서버에 반영할 수 있도록 만든 참고 구현입니다.

## 폴더 구성

- `lib/`: 현장 앱과 관리자 웹 공용 Flutter 코드
- `assets/`: 히트맵 데이터와 모바일 흉기 탐지 ONNX 모델
- `backend/src/`: 팀 Node.js 백엔드와 AI 연동 모듈
- `backend/ai/`: STT, 위험도 분석, 법률 질의, 보고서 초안 서버
- `tools/colab/`: 모델 학습 및 내보내기 노트북
- `docs/`: AI 판정 기준, 로컬 실행법, 백엔드 적용 안내

## 주요 문서

- [로컬 실행 가이드](docs/실행_가이드.md)
- [팀 백엔드 AI 연동 안내](docs/백엔드_AI_연동_안내.md)
- [AI 모델 및 판정 기준](docs/AI_모델_및_판정_기준.md)

## 저장소 규칙

- API 키, 토큰, 개인 IP, DB 접속 정보는 커밋하지 않음
- 실제 값은 `.env.example`을 복사한 로컬 환경 파일이나 `--dart-define`으로 전달함
- ONNX 모델은 Git LFS로 관리함
- AI 결과는 현장 판단 보조 정보이며 자동 조치의 근거로 사용하지 않음

팀 공통 Git 작업 방식은 [COLLABORATION.md](COLLABORATION.md)를 따릅니다.
