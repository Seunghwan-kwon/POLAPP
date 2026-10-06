# 팀 백엔드 AI 연동 안내

## 목적

이 구현은 팀의 Node.js 백엔드를 다른 서버로 교체하지 않습니다. 기존 로그인, 위치 공유, 메시지, 신고, 세션, Socket.IO 구조를 유지하면서 AI 기능에 필요한 위험 알림 저장과 카메라 프레임 중계만 별도 모듈로 추가합니다.

백엔드 담당자는 이 브랜치의 구현을 검토한 뒤 실제 운영 브랜치에 필요한 부분만 반영하면 됩니다.

## 변경 범위

| 파일 | 내용 |
|---|---|
| `backend/src/AiIntegration.ts` | 위험 알림과 카메라 중계 REST API, 관리자 실시간 이벤트 |
| `backend/src/ai-integration.sql` | `tblThreatAlert` 테이블 마이그레이션 |
| `backend/test/ai-integration.test.js` | 입력 정규화와 카메라 탐지값 단위 테스트 |
| `backend/src/main.ts` | AI 연동 모듈 import 및 등록 각 1줄 |
| `backend/dist/AiIntegration.js`, `backend/dist/main.js` | 바로 실행할 수 있는 컴파일 결과 |

기존 백엔드 파일의 동작은 수정하지 않았습니다. `main.ts`에서도 아래 등록만 추가합니다.

```ts
import{registerAiIntegration}from"./AiIntegration.js";

registerAiIntegration({app,appServer,getJwtSecret});
```

## 동작 흐름

1. 앱이 AI 서버에서 받은 Level 3·4 분석 결과 또는 카메라의 칼 감지 결과를 `POST /threat-alerts`로 전송함.
2. 연동 모듈이 기존 세션 또는 JWT로 경찰관을 식별하고 `tblThreatAlert`에 저장함.
3. `eventId`의 UNIQUE 제약으로 네트워크 재전송에 따른 중복 저장을 차단함.
4. 기존 `AppServer`, `Role`, `Officer` 연결 구조를 통해 접속 중인 관리자에게 `threatDetected`를 전송함.
5. 관리자 웹이 실시간 알림을 표시하고 `GET /threat-alerts`로 과거 기록을 조회함.
6. 카메라는 원본 영상을 저장하지 않고 경찰관별 최신 JPEG 1장만 메모리에 보관함. 8초 동안 갱신되지 않으면 목록에서 제거함.

## 추가 API

| 메서드·경로 | 권한 | 용도 |
|---|---|---|
| `GET /health` | 공개 | Node.js 백엔드 상태 확인 |
| `POST /threat-alerts` | 로그인 사용자 | AI 및 카메라 위험 이벤트 등록 |
| `GET /threat-alerts?limit=50` | 관리자 | 최근 위험 기록 조회 |
| `POST /camera-stream/status` | 로그인 사용자 | 카메라 세션 시작 및 종료 |
| `POST /camera-stream/frame` | 로그인 사용자 | 최신 JPEG와 탐지 결과 전송 |
| `GET /camera-streams` | 관리자 | 활성 카메라 목록 조회 |
| `GET /camera-streams/{officerId}/frame` | 관리자 | 경찰관의 최신 카메라 프레임 조회 |

카메라 프레임은 `Content-Type: image/jpeg` 원본 바이트로 전송합니다. `sessionId`와 JSON 형식의 `detections`는 쿼리 매개변수로 전달하므로 Node.js 패키지를 추가하지 않습니다.

## 인증과 권한

- 앱 요청은 기존 로그인에서 발급한 `Authorization: Bearer <token>`을 사용함
- 기존 세션 쿠키도 동일하게 허용함
- 기록 및 카메라 조회는 기존 DB의 `ADMIN` 역할만 허용함
- 관리자 실시간 이벤트는 기존 관리자 `Officer` 연결에만 전송함

## DB 적용

운영 코드가 요청 처리 중 테이블을 임의 생성하지 않도록 DDL을 런타임에서 분리했습니다. 서버 실행 전에 `backend/src/ai-integration.sql`을 팀 DB에 한 번 적용해야 합니다.

저장 대상은 경찰관, 세션, 위험 종류, Level, 판단 근거, 위치, 발생 시각입니다. 원본 음성, STT 전문, 카메라 프레임은 DB에 저장하지 않습니다.

## 실제 백엔드 반영 순서

1. `ai-integration.sql`을 개발 DB에 적용함.
2. `AiIntegration.ts`를 팀 백엔드에 추가함.
3. `main.ts`에 import와 등록 두 줄만 반영함.
4. 앱과 관리자 웹이 사용하는 API 및 Socket.IO 주소를 개발 서버로 지정함.
5. 일반 사용자 접근 차단, `eventId` 중복 방지, Level 3·4 실시간 알림, 카메라 종료 후 프레임 제거를 확인함.

AI 모델 자체는 `backend/ai`의 별도 Python 서버에서 실행됩니다. Node.js 백엔드는 모델을 실행하지 않고 인증, 저장, 관리자 전달만 담당합니다.
