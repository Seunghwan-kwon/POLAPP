import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'ai_service.dart';

class ReportRecordController extends ChangeNotifier {
  ReportRecordController._();

  static final ReportRecordController instance = ReportRecordController._();

  final AiService _aiService = AiService();
  final AudioRecorder _recorder = AudioRecorder();

  bool _isLoading = false;
  bool _isRecording = false;
  bool? _serverHealthy;
  String? _recordingPath;
  String _statusMessage = '보고서 초안 대기 중';
  String _voiceStatusMessage = '아직 음성 기록이 없습니다.';
  String _transcriptText = '';
  String _draftText = '';
  List<String> _reviewWarnings = const [];
  int? _completeness;

  bool get isLoading => _isLoading;
  bool get isRecording => _isRecording;
  bool? get serverHealthy => _serverHealthy;
  String get serverUrl => _aiService.serverUrl;
  String get statusMessage => _statusMessage;
  String get voiceStatusMessage => _voiceStatusMessage;
  String get transcriptText => _transcriptText;
  String get draftText => _draftText;
  List<String> get reviewWarnings => _reviewWarnings;
  int? get completeness => _completeness;

  Future<void> checkServer() async {
    await _ensureServerReady(showMessage: false);
  }

  Future<void> prepareDemoIfOffline() async {
    final serverReady = await _ensureServerReady(showMessage: false);
    if (serverReady) return;
    _applyDemoDraft();
  }

  Future<void> startRecording() async {
    if (_isLoading || _isRecording) return;

    final serverReady = await _ensureServerReady();
    if (!serverReady) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _statusMessage = '마이크 권한이 필요합니다.';
      _voiceStatusMessage = '음성 기록을 시작할 수 없습니다.';
      notifyListeners();
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/polapp_report_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    _recordingPath = path;
    _isRecording = true;
    _statusMessage = '보고서 내용을 녹음 중입니다.';
    _voiceStatusMessage = '기록을 마친 뒤 종료 버튼을 누르세요.';
    _transcriptText = '';
    _draftText = '녹음 종료 후 보고서 초안을 생성합니다.';
    _reviewWarnings = const [];
    _completeness = null;
    notifyListeners();
  }

  Future<void> stopRecording() async {
    if (!_isRecording || _isLoading) return;

    final stoppedPath = await _recorder.stop();
    final path = stoppedPath ?? _recordingPath;

    _isRecording = false;
    notifyListeners();

    if (path == null) {
      _statusMessage = '음성 기록 실패';
      _voiceStatusMessage = '녹음 파일을 만들지 못했습니다.';
      _transcriptText = '';
      _draftText = '보고서 초안을 생성할 수 없습니다.';
      _reviewWarnings = const [];
      _completeness = null;
      notifyListeners();
      return;
    }

    final serverReady = await _ensureServerReady();
    if (!serverReady) {
      await _deleteTempFile(path);
      _recordingPath = null;
      return;
    }

    _isLoading = true;
    _statusMessage = '음성 기록을 분석하고 보고서 초안을 생성하는 중입니다.';
    _voiceStatusMessage = '음성 기록 분석 중...';
    _draftText = '보고서 초안 생성 중...';
    notifyListeners();

    try {
      final result = await _aiService.draftReportFromVoice(File(path));
      _transcriptText = result.transcript;
      _draftText = result.draft.isEmpty ? '보고서 초안 내용이 비어 있습니다.' : result.draft;
      _reviewWarnings = result.warnings;
      _completeness = result.completeness;
      _statusMessage = '보고서 초안 생성 완료';
      final duration = result.durationSeconds.round();
      _voiceStatusMessage = duration > 0
          ? '음성 기록 인식 완료 ($duration초)'
          : '음성 기록 인식 완료';
    } catch (error) {
      _draftText = '보고서 초안 생성에 실패했습니다.\n$error';
      _transcriptText = '';
      _reviewWarnings = const [];
      _completeness = null;
      _statusMessage = '보고서 초안 생성 실패';
      _voiceStatusMessage = '서버 또는 음성 인식 결과를 확인해 주세요.';
    } finally {
      await _deleteTempFile(path);
      _recordingPath = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _ensureServerReady({bool showMessage = true}) async {
    try {
      _serverHealthy = await _aiService.checkHealth();
    } catch (_) {
      _serverHealthy = false;
    }

    if (_serverHealthy != true && showMessage) {
      _isLoading = false;
      _statusMessage = 'AI 서버 연결 실패';
      _voiceStatusMessage = '백엔드 연결 실패 상태입니다.';
      _applyDemoDraft(notify: false);
    }
    notifyListeners();
    return _serverHealthy == true;
  }

  void _applyDemoDraft({bool notify = true}) {
    _isLoading = false;
    _isRecording = false;
    _statusMessage = '데모 모드';
    _voiceStatusMessage = '''예시 대화
그만 소리 지르시고 이쪽으로 나오세요.
나 건들지 마. 다 부숴버릴 거야.
손에 든 물건 내려놓으세요. 다칠 수 있습니다.
싫어. 가까이 오면 던질 거야.
주변 분들 뒤로 물러나세요. 대상자 진정 유도 중입니다.''';
    _transcriptText =
        '''그만 소리 지르시고 이쪽으로 나오세요. 나 건들지 마. 다 부숴버릴 거야. 손에 든 물건 내려놓으세요. 다칠 수 있습니다. 싫어. 가까이 오면 던질 거야. 주변 분들 뒤로 물러나세요. 대상자 진정 유도 중입니다.''';
    _draftText = '''1. 사건 유형: 주취난동
2. 상황 개요: 공동주택 복도에서 주취난동과 관련된 발화가 확인되어 사실관계 확인이 필요한 사안.
3. 현장 확인 사항: 주취난동 관련 발화 또는 정황이 녹음에서 확인됨.
4. 위험 요소: 주취, 난동
5. 현장 조치 사항: 녹음 내용에서 완료된 조치 확인되지 않음.
6. 추가 확인 필요: 인명 피해 여부, CCTV 확보 여부.''';
    _reviewWarnings = const ['데모 예시 초안으로 실제 보고에 사용할 수 없음'];
    _completeness = 67;
    if (notify) notifyListeners();
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
