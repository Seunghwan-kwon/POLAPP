import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'ai_service.dart';
import 'app_alert_service.dart';
import 'threat_alert_service.dart';

class ThreatAnalysisWindowResult {
  const ThreatAnalysisWindowResult({
    required this.sequence,
    required this.capturedAt,
    required this.text,
    required this.isThreat,
    required this.alertLabel,
    required this.riskLevel,
    this.isError = false,
    this.isDemo = false,
  });

  final int sequence;
  final DateTime capturedAt;
  final String text;
  final bool isThreat;
  final String alertLabel;
  final int? riskLevel;
  final bool isError;
  final bool isDemo;
}

class _QueuedAudioWindow {
  const _QueuedAudioWindow({
    required this.sequence,
    required this.capturedAt,
    required this.pcm,
  });

  final int sequence;
  final DateTime capturedAt;
  final Uint8List pcm;
}

class ProfanityDetectionController extends ChangeNotifier {
  ProfanityDetectionController._();

  static final ProfanityDetectionController instance =
      ProfanityDetectionController._();

  final AiService _aiService = AiService();
  final ThreatAlertService _threatAlertService = ThreatAlertService();
  final AudioRecorder _recorder = AudioRecorder();

  static const int _sampleRate = 16000;
  static const int _bytesPerSample = 2;
  static const int _analysisWindowSeconds = 8;
  static const int _analysisWindowBytes =
      _sampleRate * _bytesPerSample * _analysisWindowSeconds;
  static const int _maxQueuedWindows = 3;
  static const Duration _alertCooldown = Duration(seconds: 15);

  bool _isRecording = false;
  bool _isAnalyzing = false;
  bool _keepDetecting = false;
  bool _stopInProgress = false;
  bool _isDrainingQueue = false;
  StreamSubscription<Uint8List>? _audioSubscription;
  final List<int> _pcmBuffer = [];
  final Queue<_QueuedAudioWindow> _analysisQueue = Queue<_QueuedAudioWindow>();
  final List<ThreatAnalysisWindowResult> _analysisHistory = [];
  int _capturedWindowCount = 0;
  int _completedWindowCount = 0;
  int _droppedWindowCount = 0;
  int? _analyzingWindowSequence;
  Timer? _demoTimer;
  int _demoIndex = 0;
  String? _sessionId;
  DateTime? _lastAlertAt;
  String _lastAlertLabel = '';
  int _lastAlertLevel = 0;
  bool? _serverHealthy;
  String _statusMessage = '감지 시작 대기 중';
  String _alertText = '감지된 위협이 없습니다.';
  ProfanityAnalysisResult? _lastResult;

  static const List<String> _demoThreatLabels = [
    '욕설',
    '협박',
    '흉기',
    '폭행',
    '주취 난동',
    '구조 요청',
  ];

  bool get isRecording => _isRecording;
  bool get isAnalyzing => _isAnalyzing;
  bool get keepDetecting => _keepDetecting;
  bool? get serverHealthy => _serverHealthy;
  String get statusMessage => _statusMessage;
  String get alertText => _alertText;
  ProfanityAnalysisResult? get lastResult => _lastResult;
  List<ThreatAnalysisWindowResult> get analysisHistory =>
      List.unmodifiable(_analysisHistory);
  int get capturedWindowCount => _capturedWindowCount;
  int get completedWindowCount => _completedWindowCount;
  int get queuedWindowCount => _analysisQueue.length;
  int get droppedWindowCount => _droppedWindowCount;
  int? get analyzingWindowSequence => _analyzingWindowSequence;
  String get serverUrl => _aiService.serverUrl;

  bool get isBusy => _keepDetecting || _isRecording || _isAnalyzing;

  Future<void> checkServer() async {
    try {
      _serverHealthy = await _aiService.checkHealth();
    } catch (_) {
      _serverHealthy = false;
    }
    notifyListeners();
  }

  Future<void> start() async {
    if (_keepDetecting || _isRecording || _isAnalyzing) return;

    final serverReady = await _ensureServerReady();
    if (!serverReady) {
      _startDemoDetection();
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _statusMessage = '마이크 권한이 필요합니다.';
      notifyListeners();
      return;
    }

    _keepDetecting = true;
    _stopInProgress = false;
    _sessionId = 'guardian-${DateTime.now().microsecondsSinceEpoch}';
    _alertText = '감지 대기 중';
    _lastResult = null;
    _resetAnalysisProgress();
    _statusMessage = '연속 음성 수집 중';
    notifyListeners();

    try {
      await _startContinuousRecording();
    } catch (error) {
      _keepDetecting = false;
      _isRecording = false;
      _statusMessage = '녹음 시작 실패: $error';
      notifyListeners();
      await _stopRecorderSafely();
    }
  }

  Future<void> stop() async {
    if (!_keepDetecting && !_isRecording && !_isAnalyzing) return;

    _stopDemoTimer();
    _keepDetecting = false;
    _analysisQueue.clear();
    _pcmBuffer.clear();
    _statusMessage = '감지 중지';
    notifyListeners();

    await _stopRecorderSafely();
  }

  Future<void> _stopRecorderSafely() async {
    if (_stopInProgress) return;
    _stopInProgress = true;
    try {
      await _recorder.stop().timeout(const Duration(seconds: 2));
    } catch (_) {
    } finally {
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _isRecording = false;
      _stopInProgress = false;
      notifyListeners();
    }
  }

  void _startDemoDetection() {
    _stopDemoTimer();
    _keepDetecting = true;
    _isRecording = false;
    _isAnalyzing = false;
    _sessionId = null;
    _statusMessage = '데모 모드 감지 중';
    _alertText = '데모 모드 준비 중';
    _lastResult = null;
    _resetAnalysisProgress();
    notifyListeners();

    _emitDemoThreat();
    _demoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_keepDetecting) {
        _stopDemoTimer();
        return;
      }
      _emitDemoThreat();
    });
  }

  void _emitDemoThreat() {
    final label = _demoThreatLabels[_demoIndex % _demoThreatLabels.length];
    final demoText = '데모 발화 감지: $label 상황';
    _demoIndex++;
    _alertText = '위협 감지: $label';
    _statusMessage = '데모 위협 감지';
    _lastResult = ProfanityAnalysisResult(
      text: demoText,
      isProfanity: true,
      score: 1,
      matched: [label],
      category: 'demo',
      categoryLabel: label,
      risk: RiskAssessmentResult(
        algorithm: 'demo',
        level: label == '흉기' || label == '폭행' ? 3 : 2,
        label: label == '흉기' || label == '폭행' ? '고위험' : '주의',
        alertLabel: label,
        evidenceIndex: label == '흉기' || label == '폭행' ? 82 : 55,
        guidance: const ['안전거리를 확보하고 현장 상황을 계속 확인하세요.'],
        reasons: ['데모 위협 범주: $label'],
        signals: const {},
        baselineReady: false,
        limitations: const ['백엔드 연결 실패 상태의 데모 결과입니다.'],
      ),
    );
    _capturedWindowCount++;
    _completedWindowCount++;
    _addHistory(
      ThreatAnalysisWindowResult(
        sequence: _capturedWindowCount,
        capturedAt: DateTime.now(),
        text: demoText,
        isThreat: true,
        alertLabel: label,
        riskLevel: _lastResult?.risk?.level,
        isDemo: true,
      ),
    );
    notifyListeners();
    showTopAppAlert(message: _alertText);
  }

  void _stopDemoTimer() {
    _demoTimer?.cancel();
    _demoTimer = null;
  }

  Future<void> _startContinuousRecording() async {
    _pcmBuffer.clear();
    _analysisQueue.clear();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        streamBufferSize: 4096,
      ),
    );

    _isRecording = true;
    _statusMessage = '연속 녹음 중';
    notifyListeners();

    _audioSubscription = stream.listen(
      _handleAudioData,
      onError: (Object error, StackTrace stackTrace) {
        if (!_keepDetecting) return;
        _keepDetecting = false;
        _isRecording = false;
        _analysisQueue.clear();
        _pcmBuffer.clear();
        _statusMessage = '녹음 오류: $error';
        notifyListeners();
        unawaited(_stopRecorderSafely());
      },
      onDone: () {
        _isRecording = false;
        if (_keepDetecting) {
          _keepDetecting = false;
          _statusMessage = '마이크 스트림 종료';
        }
        notifyListeners();
      },
    );
  }

  void _handleAudioData(Uint8List data) {
    if (!_keepDetecting || data.isEmpty) return;
    _pcmBuffer.addAll(data);

    while (_pcmBuffer.length >= _analysisWindowBytes) {
      final window = Uint8List.fromList(
        _pcmBuffer.sublist(0, _analysisWindowBytes),
      );
      _pcmBuffer.removeRange(0, _analysisWindowBytes);
      if (_analysisQueue.length >= _maxQueuedWindows) {
        _analysisQueue.removeFirst();
        _droppedWindowCount++;
      }
      _capturedWindowCount++;
      _analysisQueue.addLast(
        _QueuedAudioWindow(
          sequence: _capturedWindowCount,
          capturedAt: DateTime.now(),
          pcm: window,
        ),
      );
    }

    if (_analysisQueue.isNotEmpty) {
      unawaited(_drainAnalysisQueue());
    }
  }

  Future<void> _drainAnalysisQueue() async {
    if (_isDrainingQueue) return;
    _isDrainingQueue = true;

    try {
      while (_keepDetecting && _analysisQueue.isNotEmpty) {
        final window = _analysisQueue.removeFirst();
        _analyzingWindowSequence = window.sequence;
        _isAnalyzing = true;
        _statusMessage =
            '8초 구간 #${window.sequence} 분석 중 · 대기 ${_analysisQueue.length}개';
        notifyListeners();

        try {
          final result = await _aiService.analyzeThreatBytes(
            _pcmToWav(window.pcm),
            sessionId: _sessionId,
          );
          if (!_keepDetecting) break;

          _lastResult = result;
          final recognizedText = result.text.isEmpty
              ? '인식된 문장이 없습니다.'
              : result.text;
          _alertText = result.isProfanity
              ? '위협 감지: ${result.alertLabel}'
              : '감지된 위협이 없습니다.';
          _statusMessage = result.isProfanity ? '위협 감지' : '연속 녹음 중';
          _completedWindowCount++;
          _addHistory(
            ThreatAnalysisWindowResult(
              sequence: window.sequence,
              capturedAt: window.capturedAt,
              text: recognizedText,
              isThreat: result.isProfanity,
              alertLabel: result.isProfanity ? result.alertLabel : '',
              riskLevel: result.risk?.level,
            ),
          );
          notifyListeners();

          if (result.isProfanity && _shouldShowAlert(result)) {
            showTopAppAlert(message: _alertText);
            unawaited(_publishThreatAlert(result, window));
          }
        } catch (error) {
          if (!_keepDetecting) break;
          _statusMessage = '분석 실패: $error';
          _alertText = 'AI 서버 또는 오디오 형식을 확인해 주세요.';
          _completedWindowCount++;
          _addHistory(
            ThreatAnalysisWindowResult(
              sequence: window.sequence,
              capturedAt: window.capturedAt,
              text: '분석 실패: $error',
              isThreat: false,
              alertLabel: '',
              riskLevel: null,
              isError: true,
            ),
          );
          notifyListeners();
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    } finally {
      _isDrainingQueue = false;
      _isAnalyzing = false;
      _analyzingWindowSequence = null;
      if (_keepDetecting) {
        _statusMessage = _droppedWindowCount > 0
            ? '연속 녹음 중 · 누락 $_droppedWindowCount개'
            : '연속 녹음 중 · 대기 ${_analysisQueue.length}개';
      }
      notifyListeners();
    }
  }

  Uint8List _pcmToWav(Uint8List pcm) {
    final header = ByteData(44);

    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        header.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, _sampleRate * _bytesPerSample, Endian.little);
    header.setUint16(32, _bytesPerSample, Endian.little);
    header.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);

    final wav = BytesBuilder(copy: false);
    wav.add(header.buffer.asUint8List());
    wav.add(pcm);
    return wav.takeBytes();
  }

  void _resetAnalysisProgress() {
    _analysisHistory.clear();
    _capturedWindowCount = 0;
    _completedWindowCount = 0;
    _droppedWindowCount = 0;
    _analyzingWindowSequence = null;
    _lastAlertAt = null;
    _lastAlertLabel = '';
    _lastAlertLevel = 0;
  }

  bool _shouldShowAlert(ProfanityAnalysisResult result) {
    final now = DateTime.now();
    final label = result.alertLabel;
    final level = result.risk?.level ?? 1;
    final isNewCategory = label != _lastAlertLabel;
    final isEscalation = level > _lastAlertLevel;
    final cooldownPassed =
        _lastAlertAt == null || now.difference(_lastAlertAt!) >= _alertCooldown;

    if (!isNewCategory && !isEscalation && !cooldownPassed) return false;
    _lastAlertAt = now;
    _lastAlertLabel = label;
    _lastAlertLevel = level;
    return true;
  }

  Future<void> _publishThreatAlert(
    ProfanityAnalysisResult result,
    _QueuedAudioWindow window,
  ) async {
    final sessionId = _sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    try {
      await _threatAlertService.publish(
        eventId: '$sessionId-${window.sequence}',
        sessionId: sessionId,
        category: result.category,
        alertLabel: result.alertLabel,
        riskLevel: result.risk?.level ?? 1,
        evidenceIndex: result.risk?.evidenceIndex ?? result.score * 100,
        reasons: result.risk?.reasons ?? const [],
        occurredAt: window.capturedAt,
      );
    } catch (error) {
      debugPrint('[Threat Alert] 관리자 백엔드 전송 실패: $error');
    }
  }

  void _addHistory(ThreatAnalysisWindowResult result) {
    _analysisHistory.insert(0, result);
    if (_analysisHistory.length > 10) {
      _analysisHistory.removeLast();
    }
  }

  Future<bool> _ensureServerReady() async {
    try {
      _serverHealthy = await _aiService.checkHealth();
    } catch (_) {
      _serverHealthy = false;
    }

    if (_serverHealthy != true) {
      _keepDetecting = false;
      _isRecording = false;
      _isAnalyzing = false;
      _statusMessage = 'AI 서버 연결 실패';
      _alertText = '데모 모드 준비 전까지 서버 연결 후 사용해 주세요.';
      notifyListeners();
      return false;
    }

    notifyListeners();
    return true;
  }
}
