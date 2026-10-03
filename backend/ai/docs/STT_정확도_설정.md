# POLAPP STT 정확도 설정

## Runtime profile

- Primary model: `small`
- Preferred runtime: CUDA INT8 on the available GPU
- Runtime fallback: the same `small` model on CPU INT8
- Language: Korean (`ko`)

The first backend start downloads the `small` faster-whisper model. The HTTP server starts after model loading so the app cannot send audio to a half-ready STT process.

## Accuracy-oriented decoding

- Continuous PCM capture in the app; analysis continues without a recording gap
- Eight-second, non-overlapping windows
- Beam search size 5 and patience 1.2
- Silero VAD with a speech-confidence threshold of 0.5
- Each eight-second window is decoded independently to prevent prior text from repeating
- No vocabulary prompt injection; this prevents prompt words from appearing as false speech
- Repetition penalty, repeated-ngram blocking, and final hallucination rejection
- Original PCM is retained for YAMNet and acoustic-risk analysis

The model and decoding options are supported by the official [Whisper](https://github.com/openai/whisper) and [faster-whisper](https://github.com/SYSTRAN/faster-whisper) implementations.

## Optional overrides

```powershell
$env:WHISPER_MODEL_SIZE='small'
$env:WHISPER_FALLBACK_MODEL='small'
$env:WHISPER_PRELOAD='1'
.\venv\Scripts\python.exe ai_server.py
```

Setting `WHISPER_MODEL_SIZE=medium` opts into the larger model when the runtime has enough GPU memory. Setting `WHISPER_PRELOAD=0` delays model loading until the first voice request, but the first request may exceed the app timeout while the model downloads.

## Evaluation requirement

Model-size and decoding changes do not establish a performance claim by themselves. Before reporting accuracy, compare the former and current configurations on the same held-out Korean field-audio set using CER, WER, threat-keyword recall, false alarms per hour, and end-to-end latency median/P95.
