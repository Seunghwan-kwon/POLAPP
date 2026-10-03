# AI 모델 준비

실행에 필요한 다음 파일은 저장소의 `models/`에 포함하며 ONNX 바이너리는 Git LFS로 관리합니다.

- `models/guardian_context_model/model.int8.onnx`
- `models/guardian_context_model/tokenizer.json`
- `models/guardian_context_model/labels.json`
- `models/guardian_context_model/thresholds.json`
- `models/yamnet/yamnet.onnx`
- `models/yamnet/yamnet_class_map.csv`

클론 후 파일이 LFS 포인터로만 보이면 `git lfs install`과 `git lfs pull`을 실행합니다. `python scripts/verify_runtime.py` 또는 `GET /health`로 STT, 문맥 모델, 음향 모델과 선택적 LLM 상태를 확인할 수 있습니다.

## LLM 설정

`.env.example`을 `.env`로 복사한 뒤 사용할 공급자의 키만 입력합니다.

- `LLM_PROVIDER=gemini`: `GEMINI_API_KEY`, `GEMINI_MODEL` 사용
- `LLM_PROVIDER=openai`: `OPENAI_API_KEY`, `OPENAI_MODEL` 사용
- 키 없음: 법률·보고서 기능의 규칙 기반 대체 경로 사용

LAN 요청을 인증하려면 서버의 `AI_SERVER_TOKEN`과 Flutter 실행 인자 `--dart-define=AI_SERVER_TOKEN=...`에 같은 값을 지정합니다.
