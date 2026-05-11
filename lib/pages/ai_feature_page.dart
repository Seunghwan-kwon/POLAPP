import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/ai_service.dart';

class AiFeaturePage extends StatelessWidget {
  const AiFeaturePage({super.key});

  void _openFeature(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 기능')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AiFeatureButton(
                icon: Icons.hearing_outlined,
                label: '욕설감지',
                onPressed: () => _openFeature(
                  context,
                  const ProfanityDetectionPage(),
                ),
              ),
              const SizedBox(height: 12),
              _AiFeatureButton(
                icon: Icons.gavel_outlined,
                label: '법률응답',
                onPressed: () => _openFeature(
                  context,
                  const ConnectedLegalResponsePage(),
                ),
              ),
              const SizedBox(height: 12),
              _AiFeatureButton(
                icon: Icons.description_outlined,
                label: '보고서 초안생성',
                onPressed: () => _openFeature(
                  context,
                  const ConnectedReportDraftPage(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiFeatureButton extends StatelessWidget {
  const _AiFeatureButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(label),
      ),
    );
  }
}

class ProfanityDetectionPage extends StatefulWidget {
  const ProfanityDetectionPage({super.key});

  @override
  State<ProfanityDetectionPage> createState() => _ProfanityDetectionPageState();
}

class _ProfanityDetectionPageState extends State<ProfanityDetectionPage> {
  final AiService _aiService = AiService();
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isAnalyzing = false;
  bool _keepDetecting = false;
  bool? _serverHealthy;
  String _statusMessage = 'AI 서버 연결 확인 중';
  String _recentText = '아직 인식된 문장이 없습니다.';
  String _alertText = '감지된 욕설이 없습니다.';
  String? _recordingPath;
  ProfanityAnalysisResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  @override
  void dispose() {
    _keepDetecting = false;
    _recorder.dispose();
    _aiService.dispose();
    super.dispose();
  }

  Future<void> _checkServer() async {
    try {
      final healthy = await _aiService.checkHealth();
      if (!mounted) return;
      setState(() {
        _serverHealthy = healthy;
        _statusMessage = healthy
            ? 'AI 서버 연결됨 (${_aiService.serverUrl})'
            : 'AI 서버 응답이 올바르지 않습니다.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _serverHealthy = false;
        _statusMessage = 'AI 서버 연결 실패 (${_aiService.serverUrl})';
      });
    }
  }

  Future<bool> _ensureMicPermission() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission && mounted) {
      setState(() {
        _statusMessage = '마이크 권한이 필요합니다.';
      });
    }
    return hasPermission;
  }

  Future<String> _recordChunk() async {
    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/polapp_profanity_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingPath = path;
        _statusMessage = '녹음 중';
      });
    }

    await Future.delayed(const Duration(seconds: 3));
    final stoppedPath = await _recorder.stop();

    if (mounted) {
      setState(() {
        _isRecording = false;
      });
    }

    return stoppedPath ?? path;
  }

  Future<void> _startContinuousDetection() async {
    if (_keepDetecting || _isAnalyzing || _isRecording) return;

    final hasPermission = await _ensureMicPermission();
    if (!hasPermission) {
      return;
    }

    setState(() {
      _keepDetecting = true;
      _recentText = '실시간 감지를 시작합니다.';
      _alertText = '감지 대기 중';
      _lastResult = null;
      _statusMessage = '연속 감지 중';
    });

    unawaited(_runDetectionLoop());
  }

  Future<void> _stopContinuousDetection() async {
    _keepDetecting = false;
    if (_isRecording) {
      await _recorder.stop();
    }
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _statusMessage = _isAnalyzing ? '마지막 분석 중' : '감지 중지';
    });
  }

  Future<void> _runDetectionLoop() async {
    while (_keepDetecting && mounted) {
      String? path;
      try {
        path = await _recordChunk();
        if (!_keepDetecting || !mounted) break;

        setState(() {
          _isAnalyzing = true;
          _statusMessage = 'AI 분석 중';
          _recentText = '최근 음성을 분석하고 있습니다.';
        });

        final result = await _aiService.analyzeProfanity(File(path));
        if (!mounted) return;

        setState(() {
          _lastResult = result;
          _recentText = result.text.isEmpty ? '인식된 문장이 없습니다.' : result.text;
          _alertText = result.isProfanity
              ? '욕설 감지: ${result.matched.join(', ')} (score=${result.score})'
              : '감지된 욕설이 없습니다. (score=${result.score})';
          _statusMessage = result.isProfanity ? '욕설 감지됨' : '연속 감지 중';
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _statusMessage = '분석 실패: $error';
          _recentText = '분석에 실패했습니다.';
          _alertText = 'AI 서버 또는 오디오 형식을 확인해 주세요.';
        });
        await Future.delayed(const Duration(seconds: 1));
      } finally {
        if (path != null) {
          try {
            await File(path).delete();
          } catch (_) {
            // Temporary recording cleanup can safely be ignored.
          }
        }
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
          });
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _keepDetecting = false;
      _isRecording = false;
      _isAnalyzing = false;
      if (_statusMessage == '연속 감지 중' || _statusMessage == '마지막 분석 중') {
        _statusMessage = '감지 중지';
      }
    });
  }

  Future<void> _onMainButtonPressed() async {
    if (_keepDetecting || _isRecording) {
      await _stopContinuousDetection();
    } else {
      await _startContinuousDetection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isBusy = _keepDetecting || _isRecording || _isAnalyzing;
    final statusColor = _isRecording
        ? const Color(0xFFDC2626)
        : _isAnalyzing
            ? const Color(0xFFF97316)
            : const Color(0xFF64748B);
    final isProfanity = _lastResult?.isProfanity == true;

    return Scaffold(
      appBar: AppBar(title: const Text('욕설감지')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StatusPanel(
              color: statusColor,
              title: _isRecording
                  ? '녹음 중'
                  : _isAnalyzing
                      ? '분석 중'
                      : '대기 중',
              subtitle: _statusMessage,
              icon: _isRecording
                  ? Icons.mic
                  : _isAnalyzing
                      ? Icons.hourglass_top
                      : Icons.mic_none,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isAnalyzing ? null : _onMainButtonPressed,
                    icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      _keepDetecting || _isRecording ? '감지 중지' : '감지 시작',
                    ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: _checkServer,
                  icon: const Icon(Icons.refresh),
                  tooltip: '서버 연결 확인',
                ),
              ],
            ),
            const SizedBox(height: 20),
            _InfoSection(
              title: '최근 인식 결과',
              child: Text(
                _recentText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF334155),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '감지 알림',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: isProfanity
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF16A34A),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _alertText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isProfanity
                            ? const Color(0xFFB42318)
                            : const Color(0xFF166534),
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '연결 상태',
              child: Text(
                _serverHealthy == null
                    ? '확인 중'
                    : _serverHealthy == true
                        ? '연결됨: ${_aiService.serverUrl}'
                        : '연결 실패: ${_aiService.serverUrl}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _serverHealthy == true
                      ? const Color(0xFF166534)
                      : const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isBusy) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final Color color;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class LegalResponsePage extends StatelessWidget {
  const LegalResponsePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('법률응답')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StatusPanel(
              color: const Color(0xFF2563EB),
              title: '법률 질의 대기 중',
              subtitle: '질문을 입력하거나 음성 질문을 녹음하면 법률 AI가 답변합니다.',
              icon: Icons.gavel_outlined,
            ),
            const SizedBox(height: 16),
            _InfoSection(
              title: '질문 입력',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: '예: 음주운전 처벌 알려줘',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.search),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('질문 실행'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '음성 질문',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.mic_none),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('음성 질문 시작'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.stop),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('음성 질문 종료'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '아직 녹음된 질문이 없습니다.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '답변 결과',
              child: Text(
                '질문을 실행하면 법률 AI 답변이 여기에 표시됩니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '근거 조문',
              child: Text(
                '관련 법률명, 조문, 페이지 정보가 여기에 표시됩니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConnectedLegalResponsePage extends StatefulWidget {
  const ConnectedLegalResponsePage({super.key});

  @override
  State<ConnectedLegalResponsePage> createState() =>
      _ConnectedLegalResponsePageState();
}

class _ConnectedLegalResponsePageState
    extends State<ConnectedLegalResponsePage> {
  final AiService _aiService = AiService();
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final TextEditingController _questionController = TextEditingController();

  bool _isLoading = false;
  bool _isRecordingVoice = false;
  String _statusMessage = '법률 질의 대기 중';
  String _answerText = '질문을 실행하면 법률 AI 답변이 여기에 표시됩니다.';
  String _voiceStatusMessage = '아직 음성 질문이 없습니다.';
  List<String> _citations = const [];
  bool? _usedModel;

  @override
  void dispose() {
    _voiceRecorder.dispose();
    _questionController.dispose();
    _aiService.dispose();
    super.dispose();
  }

  Future<void> _askLegalQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || _isLoading) {
      if (question.isEmpty) {
        setState(() {
          _statusMessage = '질문을 입력해 주세요.';
        });
      }
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _statusMessage = '법률 AI가 답변을 생성하는 중입니다.';
      _answerText = '답변 생성 중...';
      _citations = const [];
      _usedModel = null;
    });

    try {
      final result = await _aiService.answerLegalQuestion(question);
      if (!mounted) return;
      setState(() {
        _answerText = result.answer.isEmpty ? '답변 내용이 비어 있습니다.' : result.answer;
        _citations = result.citations;
        _usedModel = result.usedModel;
        _statusMessage = result.usedModel ? '법률 질의 완료' : '법률 질의 완료 · 근거 기반 응답';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _answerText = '법률 질의에 실패했습니다.\n$error';
        _citations = const [];
        _usedModel = false;
        _statusMessage = '법률 질의 실패';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _ensureLegalMicPermission() async {
    final hasPermission = await _voiceRecorder.hasPermission();
    if (!hasPermission && mounted) {
      setState(() {
        _voiceStatusMessage = '마이크 권한이 필요합니다.';
        _statusMessage = '음성 질문을 시작할 수 없습니다.';
      });
    }
    return hasPermission;
  }

  Future<void> _startVoiceQuestion() async {
    if (_isLoading || _isRecordingVoice) return;

    final hasPermission = await _ensureLegalMicPermission();
    if (!hasPermission) {
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/polapp_legal_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _voiceRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    if (!mounted) return;
    setState(() {
      _isRecordingVoice = true;
      _statusMessage = '음성 질문 녹음 중입니다.';
      _voiceStatusMessage = '질문을 말한 뒤 종료 버튼을 누르세요.';
      _answerText = '음성 질문 녹음 중...';
      _citations = const [];
      _usedModel = null;
    });
  }

  Future<void> _stopVoiceQuestion() async {
    if (!_isRecordingVoice || _isLoading) return;

    final path = await _voiceRecorder.stop();
    if (!mounted) return;

    setState(() {
      _isRecordingVoice = false;
      _isLoading = true;
      _statusMessage = '음성 질문을 인식하고 답변을 생성하는 중입니다.';
      _voiceStatusMessage = '음성 질문 분석 중...';
      _answerText = '답변 생성 중...';
      _citations = const [];
      _usedModel = null;
    });

    if (path == null) {
      setState(() {
        _isLoading = false;
        _statusMessage = '음성 질문 실패';
        _voiceStatusMessage = '녹음 파일을 만들지 못했습니다.';
        _answerText = '음성 질문 녹음에 실패했습니다.';
        _usedModel = false;
      });
      return;
    }

    try {
      final result = await _aiService.answerLegalVoiceQuestion(File(path));
      if (!mounted) return;
      if (result.question.isNotEmpty) {
        _questionController.text = result.question;
      }
      setState(() {
        _answerText = result.answer.isEmpty ? '답변 내용이 비어 있습니다.' : result.answer;
        _citations = result.citations;
        _usedModel = result.usedModel;
        _statusMessage = result.usedModel ? '음성 법률 질의 완료' : '음성 법률 질의 완료 · 근거 기반 응답';
        _voiceStatusMessage = result.question.isEmpty
            ? '인식된 질문이 비어 있습니다.'
            : '인식된 질문: ${result.question}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _answerText = '음성 법률 질의에 실패했습니다.\n$error';
        _citations = const [];
        _usedModel = false;
        _statusMessage = '음성 법률 질의 실패';
        _voiceStatusMessage = '서버 또는 음성 인식 결과를 확인해 주세요.';
      });
    } finally {
      try {
        await File(path).delete();
      } catch (_) {
        // Temporary recording cleanup can safely be ignored.
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _isLoading
        ? const Color(0xFFF97316)
        : _usedModel == false
            ? const Color(0xFF64748B)
            : const Color(0xFF2563EB);

    return Scaffold(
      appBar: AppBar(title: const Text('법률응답')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StatusPanel(
              color: statusColor,
              title: _isLoading ? '답변 생성 중' : '법률 질의',
              subtitle: _statusMessage,
              icon: _isLoading ? Icons.hourglass_top : Icons.gavel_outlined,
            ),
            const SizedBox(height: 16),
            _InfoSection(
              title: '질문 입력',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _questionController,
                    enabled: !_isLoading,
                    minLines: 3,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: '예: 음주운전 처벌 기준 알려줘',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _askLegalQuestion,
                    icon: const Icon(Icons.search),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('질문 실행'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '음성 질문',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading || _isRecordingVoice
                              ? null
                              : _startVoiceQuestion,
                          icon: const Icon(Icons.mic_none),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('음성 질문 시작'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _isRecordingVoice ? _stopVoiceQuestion : null,
                          icon: const Icon(Icons.stop),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('음성 질문 종료'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _voiceStatusMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '답변 결과',
              child: SelectableText(
                _answerText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF334155),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '근거 조문',
              child: _citations.isEmpty
                  ? Text(
                      '관련 법률명, 조문, 페이지 정보가 여기에 표시됩니다.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                        height: 1.45,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final citation in _citations)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.article_outlined,
                                    size: 18,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    citation,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFF334155),
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class ConnectedReportDraftPage extends StatefulWidget {
  const ConnectedReportDraftPage({super.key});

  @override
  State<ConnectedReportDraftPage> createState() =>
      _ConnectedReportDraftPageState();
}

class _ConnectedReportDraftPageState extends State<ConnectedReportDraftPage> {
  final AiService _aiService = AiService();
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _transcriptController = TextEditingController();

  bool _isLoading = false;
  bool _isRecording = false;
  String _statusMessage = '보고서 초안 대기 중';
  String _voiceStatusMessage = '아직 녹음된 사건 기록이 없습니다.';
  String _recognizedTranscript = '음성 기록을 연결하면 STT 변환 결과가 여기에 표시됩니다.';
  String _draftText = '초안을 생성하면 보고서 형식의 문장이 여기에 표시됩니다.';

  @override
  void dispose() {
    _transcriptController.dispose();
    _recorder.dispose();
    _aiService.dispose();
    super.dispose();
  }

  Future<bool> _ensureMicPermission() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission && mounted) {
      setState(() {
        _statusMessage = '마이크 권한이 필요합니다.';
        _voiceStatusMessage = '음성 기록을 시작할 수 없습니다.';
      });
    }
    return hasPermission;
  }

  Future<void> _draftFromText() async {
    final transcript = _transcriptController.text.trim();
    if (transcript.isEmpty || _isLoading || _isRecording) {
      if (transcript.isEmpty) {
        setState(() {
          _statusMessage = '사건 내용을 입력해 주세요.';
        });
      }
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _statusMessage = '보고서 초안을 생성하는 중입니다.';
      _recognizedTranscript = transcript;
      _draftText = '초안 생성 중...';
    });

    try {
      final result = await _aiService.draftReport(transcript);
      if (!mounted) return;
      setState(() {
        _recognizedTranscript =
            result.transcript.isEmpty ? transcript : result.transcript;
        _draftText = result.draft.isEmpty ? '초안 내용이 비어 있습니다.' : result.draft;
        _statusMessage = '보고서 초안 생성 완료';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _draftText = '보고서 초안 생성에 실패했습니다.\n$error';
        _statusMessage = '보고서 초안 생성 실패';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startRecording() async {
    if (_isLoading || _isRecording) return;

    final hasPermission = await _ensureMicPermission();
    if (!hasPermission) return;

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

    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _statusMessage = '사건 내용을 녹음 중입니다.';
      _voiceStatusMessage = '기록을 마친 뒤 종료 버튼을 누르세요.';
      _recognizedTranscript = '녹음 중...';
      _draftText = '녹음 종료 후 초안이 생성됩니다.';
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _isLoading) return;

    final path = await _recorder.stop();
    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _isLoading = true;
      _statusMessage = '음성 기록을 인식하고 보고서 초안을 생성하는 중입니다.';
      _voiceStatusMessage = '음성 기록 분석 중...';
      _recognizedTranscript = 'STT 변환 중...';
      _draftText = '초안 생성 중...';
    });

    if (path == null) {
      setState(() {
        _isLoading = false;
        _statusMessage = '음성 기록 실패';
        _voiceStatusMessage = '녹음 파일을 만들지 못했습니다.';
        _recognizedTranscript = '음성 기록에 실패했습니다.';
        _draftText = '초안을 생성할 수 없습니다.';
      });
      return;
    }

    try {
      final result = await _aiService.draftReportFromVoice(File(path));
      if (!mounted) return;
      if (result.transcript.isNotEmpty) {
        _transcriptController.text = result.transcript;
      }
      setState(() {
        _recognizedTranscript = result.transcript.isEmpty
            ? '인식된 사건 내용이 비어 있습니다.'
            : result.transcript;
        _draftText = result.draft.isEmpty ? '초안 내용이 비어 있습니다.' : result.draft;
        _statusMessage = '보고서 초안 생성 완료';
        _voiceStatusMessage = '음성 기록 인식 완료';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recognizedTranscript = '음성 기록 처리에 실패했습니다.';
        _draftText = '보고서 초안 생성에 실패했습니다.\n$error';
        _statusMessage = '보고서 초안 생성 실패';
        _voiceStatusMessage = '서버 또는 음성 인식 결과를 확인해 주세요.';
      });
    } finally {
      try {
        await File(path).delete();
      } catch (_) {
        // Temporary recording cleanup can safely be ignored.
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _isRecording
        ? const Color(0xFFDC2626)
        : _isLoading
            ? const Color(0xFFF97316)
            : const Color(0xFF0F766E);

    return Scaffold(
      appBar: AppBar(title: const Text('보고서 초안생성')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StatusPanel(
              color: statusColor,
              title: _isRecording
                  ? '음성 기록 중'
                  : _isLoading
                      ? '초안 생성 중'
                      : '보고서 초안',
              subtitle: _statusMessage,
              icon: _isRecording
                  ? Icons.mic
                  : _isLoading
                      ? Icons.hourglass_top
                      : Icons.description_outlined,
            ),
            const SizedBox(height: 16),
            _InfoSection(
              title: '사건 내용 입력',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _transcriptController,
                    enabled: !_isLoading && !_isRecording,
                    minLines: 5,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: '예: 2026년 5월 11일 14시경 노원구 인근에서...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed:
                        _isLoading || _isRecording ? null : _draftFromText,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('초안 생성'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '음성 기록',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading || _isRecording
                              ? null
                              : _startRecording,
                          icon: const Icon(Icons.mic_none),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('기록 시작'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isRecording ? _stopRecording : null,
                          icon: const Icon(Icons.stop),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('기록 종료'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _voiceStatusMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '인식된 사건 내용',
              child: SelectableText(
                _recognizedTranscript,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF334155),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '보고서 초안',
              child: SelectableText(
                _draftText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF334155),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '검토 항목',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReviewItem(
                    icon: Icons.event_note_outlined,
                    text: '발생 일시와 장소',
                    theme: theme,
                  ),
                  _ReviewItem(
                    icon: Icons.groups_outlined,
                    text: '관련자와 피해 상황',
                    theme: theme,
                  ),
                  _ReviewItem(
                    icon: Icons.fact_check_outlined,
                    text: '조치 내용과 후속 처리',
                    theme: theme,
                  ),
                ],
              ),
            ),
            if (_isLoading || _isRecording) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class ReportDraftPage extends StatelessWidget {
  const ReportDraftPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('보고서 초안생성')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _StatusPanel(
              color: Color(0xFF0F766E),
              title: '보고서 초안 대기 중',
              subtitle: '사건 내용을 입력하거나 음성으로 기록하면 보고서 초안이 생성됩니다.',
              icon: Icons.description_outlined,
            ),
            const SizedBox(height: 16),
            _InfoSection(
              title: '사건 내용 입력',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    minLines: 5,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: '예: 2026년 5월 11일 14시경 노원구 인근에서...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('초안 생성'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '음성 기록',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.mic_none),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('기록 시작'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.stop),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('기록 종료'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '아직 녹음된 사건 기록이 없습니다.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '인식된 사건 내용',
              child: Text(
                '음성 기록을 연결하면 STT 변환 결과가 여기에 표시됩니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '보고서 초안',
              child: SelectableText(
                '초안을 생성하면 보고서 형식의 문장이 여기에 표시됩니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF334155),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _InfoSection(
              title: '검토 항목',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReviewItem(
                    icon: Icons.event_note_outlined,
                    text: '발생 일시와 장소',
                    theme: theme,
                  ),
                  _ReviewItem(
                    icon: Icons.groups_outlined,
                    text: '관련자와 피해 상황',
                    theme: theme,
                  ),
                  _ReviewItem(
                    icon: Icons.fact_check_outlined,
                    text: '조치 내용과 후속 처리',
                    theme: theme,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewItem extends StatelessWidget {
  const _ReviewItem({
    required this.icon,
    required this.text,
    required this.theme,
  });

  final IconData icon;
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: const Color(0xFF0F766E),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF334155),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AiFeatureDetailPage extends StatelessWidget {
  const AiFeatureDetailPage({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const SafeArea(
        child: SizedBox.expand(),
      ),
    );
  }
}
