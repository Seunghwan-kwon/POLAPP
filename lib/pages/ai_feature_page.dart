import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/ai_service.dart';
import '../services/camera_threat_controller.dart';
import '../services/profanity_detection_controller.dart';
import '../services/report_record_controller.dart';

class AiFeaturePage extends StatefulWidget {
  const AiFeaturePage({super.key});

  @override
  State<AiFeaturePage> createState() => _AiFeaturePageState();
}

class _AiFeaturePageState extends State<AiFeaturePage> {
  final AiService _aiService = AiService();
  final ProfanityDetectionController _profanityController =
      ProfanityDetectionController.instance;
  final CameraThreatController _cameraController =
      CameraThreatController.instance;
  final ReportRecordController _reportController =
      ReportRecordController.instance;

  bool? _serverHealthy;

  @override
  void initState() {
    super.initState();
    _profanityController.addListener(_refresh);
    _cameraController.addListener(_refresh);
    _reportController.addListener(_refresh);
    _checkServer();
  }

  @override
  void dispose() {
    _profanityController.removeListener(_refresh);
    _cameraController.removeListener(_refresh);
    _reportController.removeListener(_refresh);
    _aiService.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _checkServer() async {
    setState(() {
      _serverHealthy = null;
    });
    try {
      final healthy = await _aiService.checkHealth();
      if (!mounted) return;
      setState(() {
        _serverHealthy = healthy;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _serverHealthy = false;
      });
    }
  }

  Future<void> _toggleThreatDetection(bool value) async {
    if (value) {
      await _profanityController.start();
    } else {
      await _profanityController.stop();
    }
  }

  Future<void> _toggleCameraDetection() async {
    await _cameraController.toggle(!_cameraController.enabled);
  }

  Future<void> _toggleReportDraft(bool value) async {
    if (value) {
      await _reportController.startRecording();
    } else {
      await _reportController.stopRecording();
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
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
              _AiFeatureTile(
                icon: Icons.hearing_outlined,
                title: '위협 인식 AI',
                active: _profanityController.keepDetecting,
                onToggle: _toggleThreatDetection,
                onTap: () => _open(const PersistentProfanityDetectionPage()),
                secondaryAction: IconButton(
                  onPressed: _cameraController.initializing
                      ? null
                      : _toggleCameraDetection,
                  tooltip: _cameraController.enabled
                      ? '카메라 감지 끄기'
                      : '카메라 감지 켜기',
                  style: IconButton.styleFrom(
                    backgroundColor: _cameraController.enabled
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF1F5F9),
                    foregroundColor: _cameraController.enabled
                        ? const Color(0xFF15803D)
                        : const Color(0xFF64748B),
                  ),
                  icon: _cameraController.initializing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _cameraController.enabled
                              ? Icons.videocam
                              : Icons.videocam_outlined,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              _AiFeatureTile(
                icon: Icons.description_outlined,
                title: '보고서 초안 AI',
                active:
                    _reportController.isRecording ||
                    _reportController.isLoading,
                onToggle: _reportController.isLoading
                    ? null
                    : _toggleReportDraft,
                onTap: () => _open(const ConnectedReportDraftPage()),
              ),
              const SizedBox(height: 12),
              _AiFeatureTile(
                icon: Icons.gavel_outlined,
                title: '법률 에이전트',
                onTap: () => _open(const ConnectedLegalResponsePage()),
              ),
              const Spacer(),
              _ConnectionStatusSection(
                serverUrl: _aiService.serverUrl,
                serverHealthy: _serverHealthy,
                onRefresh: _checkServer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiFeatureTile extends StatelessWidget {
  const _AiFeatureTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.active = false,
    this.onToggle,
    this.secondaryAction,
  });

  final IconData icon;
  final String title;
  final bool active;
  final ValueChanged<bool>? onToggle;
  final Widget? secondaryAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasToggle = icon != Icons.gavel_outlined;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: const Color(0xFF1D4ED8)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              if (secondaryAction != null) ...[
                secondaryAction!,
                const SizedBox(width: 4),
              ],
              if (hasToggle)
                Switch(value: active, onChanged: onToggle)
              else
                const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
            ],
          ),
        ),
      ),
    );
  }
}

class PersistentProfanityDetectionPage extends StatefulWidget {
  const PersistentProfanityDetectionPage({super.key});

  @override
  State<PersistentProfanityDetectionPage> createState() =>
      _PersistentProfanityDetectionPageState();
}

class _PersistentProfanityDetectionPageState
    extends State<PersistentProfanityDetectionPage> {
  final ProfanityDetectionController _controller =
      ProfanityDetectionController.instance;
  final CameraThreatController _cameraController =
      CameraThreatController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    _cameraController.addListener(_refresh);
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _cameraController.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isThreat = _controller.lastResult?.isProfanity == true;
    final risk = _controller.lastResult?.risk;
    final statusColor = _controller.isRecording
        ? const Color(0xFFDC2626)
        : _controller.isAnalyzing
        ? const Color(0xFFF97316)
        : const Color(0xFF64748B);

    return Scaffold(
      appBar: AppBar(title: const Text('위협 인식 AI')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StatusPanel(
              color: statusColor,
              title: _controller.isRecording
                  ? '녹음 중'
                  : _controller.isAnalyzing
                  ? '분석 중'
                  : _controller.keepDetecting
                  ? '감지 중'
                  : '대기 중',
              subtitle: _controller.statusMessage,
              icon: _controller.isRecording
                  ? Icons.mic
                  : _controller.isAnalyzing
                  ? Icons.hourglass_top
                  : Icons.mic_none,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _controller.keepDetecting
                        ? null
                        : _controller.start,
                    icon: const Icon(Icons.play_arrow),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('감지 시작'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _controller.isBusy ? _controller.stop : null,
                    icon: const Icon(Icons.stop),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('종료'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _CameraThreatPanel(controller: _cameraController),
            const SizedBox(height: 14),
            _ThreatAnalysisHistorySection(controller: _controller),
            const SizedBox(height: 14),
            _InfoSection(
              title: '감지 알림',
              child: Text(
                _controller.alertText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isThreat
                      ? const Color(0xFFB42318)
                      : const Color(0xFF166534),
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
            ),
            if (risk != null) ...[
              const SizedBox(height: 14),
              _RiskAssessmentSection(risk: risk),
            ],
            if (_controller.isBusy) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _CameraThreatPanel extends StatelessWidget {
  const _CameraThreatPanel({required this.controller});

  final CameraThreatController controller;

  @override
  Widget build(BuildContext context) {
    final camera = controller.cameraController;
    final previewReady =
        controller.enabled && camera != null && camera.value.isInitialized;
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final aspectRatio = previewReady
        ? (isPortrait ? 1 / camera.value.aspectRatio : camera.value.aspectRatio)
        : 3 / 4;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.videocam_outlined, color: Color(0xFF1D4ED8)),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  '카메라 위험 물체 감지',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Switch(
                value: controller.enabled,
                onChanged: controller.initializing
                    ? null
                    : (value) => controller.toggle(value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: aspectRatio,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: !previewReady
                    ? Center(
                        child: controller.initializing
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    controller.enabled
                                        ? Icons.hourglass_top
                                        : Icons.videocam_off_outlined,
                                    color: const Color(0xFF94A3B8),
                                    size: 34,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    controller.enabled
                                        ? '첫 분석 화면 준비 중'
                                        : '카메라가 꺼져 있습니다.',
                                    style: const TextStyle(
                                      color: Color(0xFFCBD5E1),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(camera),
                          CustomPaint(
                            painter: _WeaponDetectionPainter(
                              detections: controller.detections,
                              imageWidth: controller.frameWidth,
                              imageHeight: controller.frameHeight,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                controller.enabled ? Icons.circle : Icons.circle_outlined,
                size: 10,
                color: controller.enabled
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  controller.statusMessage,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (controller.lastInferenceMilliseconds != null)
                Text(
                  '${controller.lastInferenceMilliseconds}ms',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                controller.remoteConnected
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                size: 17,
                color: controller.remoteConnected
                    ? const Color(0xFF15803D)
                    : const Color(0xFFB45309),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  controller.remoteStatusMessage,
                  style: TextStyle(
                    color: controller.remoteConnected
                        ? const Color(0xFF15803D)
                        : const Color(0xFF92400E),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (controller.detections.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: controller.detections
                  .map(
                    (detection) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: detection.isKnife
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${detection.displayLabel} '
                        '${(detection.score * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: detection.isKnife
                              ? const Color(0xFFB91C1C)
                              : const Color(0xFFC2410C),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeaponDetectionPainter extends CustomPainter {
  const _WeaponDetectionPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<WeaponDetection> detections;
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth <= 0 || imageHeight <= 0) return;
    final imageAspect = imageWidth / imageHeight;
    final canvasAspect = size.width / size.height;
    final renderedWidth = canvasAspect > imageAspect
        ? size.height * imageAspect
        : size.width;
    final renderedHeight = canvasAspect > imageAspect
        ? size.height
        : size.width / imageAspect;
    final offsetX = (size.width - renderedWidth) / 2;
    final offsetY = (size.height - renderedHeight) / 2;

    for (final detection in detections) {
      final color = detection.isKnife
          ? const Color(0xFFEF4444)
          : const Color(0xFFF59E0B);
      final normalized = detection.normalizedBox;
      final box = Rect.fromLTRB(
        offsetX + normalized.left * renderedWidth,
        offsetY + normalized.top * renderedHeight,
        offsetX + normalized.right * renderedWidth,
        offsetY + normalized.bottom * renderedHeight,
      );
      canvas.drawRect(
        box,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text:
              '${detection.displayLabel} '
              '${(detection.score * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelTop = (box.top - textPainter.height - 6).clamp(
        offsetY,
        offsetY + renderedHeight - textPainter.height - 6,
      );
      final labelRect = Rect.fromLTWH(
        box.left,
        labelTop,
        textPainter.width + 10,
        textPainter.height + 6,
      );
      canvas.drawRect(labelRect, Paint()..color = color);
      textPainter.paint(canvas, Offset(labelRect.left + 5, labelRect.top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _WeaponDetectionPainter oldDelegate) =>
      oldDelegate.detections != detections ||
      oldDelegate.imageWidth != imageWidth ||
      oldDelegate.imageHeight != imageHeight;
}

class _ThreatAnalysisHistorySection extends StatelessWidget {
  const _ThreatAnalysisHistorySection({required this.controller});

  final ProfanityDetectionController controller;

  String _time(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(value.hour)}:${twoDigits(value.minute)}:'
        '${twoDigits(value.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = controller.analysisHistory;
    final analyzing = controller.analyzingWindowSequence;
    final progress = analyzing == null
        ? '수집 ${controller.capturedWindowCount} · '
              '완료 ${controller.completedWindowCount} · '
              '대기 ${controller.queuedWindowCount}'
        : '구간 #$analyzing 분석 중 · '
              '대기 ${controller.queuedWindowCount}';

    return _InfoSection(
      title: '8초 분석 결과',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            progress,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (controller.droppedWindowCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '처리 지연으로 ${controller.droppedWindowCount}개 구간이 누락되었습니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB42318),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (history.isEmpty)
            Text(
              controller.keepDetecting
                  ? '첫 번째 결과는 음성을 8초 수집한 뒤 표시됩니다.'
                  : '아직 완료된 분석 결과가 없습니다.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF475569),
                height: 1.45,
              ),
            )
          else
            for (var index = 0; index < history.length; index++) ...[
              _ThreatAnalysisHistoryRow(
                result: history[index],
                timeLabel: _time(history[index].capturedAt),
              ),
              if (index != history.length - 1)
                const Divider(height: 24, color: Color(0xFFE2E8F0)),
            ],
        ],
      ),
    );
  }
}

class _ThreatAnalysisHistoryRow extends StatelessWidget {
  const _ThreatAnalysisHistoryRow({
    required this.result,
    required this.timeLabel,
  });

  final ThreatAnalysisWindowResult result;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = result.isError
        ? const Color(0xFFB42318)
        : result.isThreat
        ? const Color(0xFFDC2626)
        : const Color(0xFF15803D);
    final status = result.isError
        ? '분석 실패'
        : result.isThreat
        ? '위협 ${result.alertLabel}'
        : '위협 없음';
    final level = result.riskLevel == null
        ? ''
        : ' · Level ${result.riskLevel}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '구간 #${result.sequence} · $timeLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: Text(
                '${result.isDemo ? '데모 · ' : ''}$status$level',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          result.text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF334155),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _RiskAssessmentSection extends StatelessWidget {
  const _RiskAssessmentSection({required this.risk});

  final RiskAssessmentResult risk;

  Color get _color {
    return switch (risk.level) {
      4 => const Color(0xFFB42318),
      3 => const Color(0xFFDC2626),
      2 => const Color(0xFFD97706),
      _ => const Color(0xFF15803D),
    };
  }

  IconData get _icon {
    return switch (risk.level) {
      4 => Icons.emergency,
      3 => Icons.warning_amber_rounded,
      2 => Icons.visibility_outlined,
      _ => Icons.verified_user_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _InfoSection(
      title: '위험도 판단',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: _color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Level ${risk.level} · ${risk.label}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: _color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (risk.reasons.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '판단 근거',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            for (final reason in risk.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $reason'),
              ),
          ],
          if (risk.guidance.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '대응 안내',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            for (final item in risk.guidance)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $item'),
              ),
          ],
        ],
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
  final AudioRecorder _recorder = AudioRecorder();

  bool _isLoading = false;
  bool _isRecording = false;
  bool? _serverHealthy;
  String _statusMessage = '법률 질의 대기 중';
  String _voiceStatusMessage = '아직 음성 질문이 없습니다.';
  String _answerText = '';
  List<String> _citations = const [];

  @override
  void initState() {
    super.initState();
    _prepareDemoIfOffline();
  }

  @override
  void dispose() {
    _recorder.dispose();
    _aiService.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_isLoading || _isRecording) return;

    final serverReady = await _ensureServerReady();
    if (!serverReady) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() {
        _voiceStatusMessage = '마이크 권한이 필요합니다.';
      });
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/polapp_legal_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _statusMessage = '음성 질문 녹음 중입니다.';
      _voiceStatusMessage = '질문을 말한 뒤 종료 버튼을 누르세요.';
      _answerText = '음성 질문 녹음 중...';
      _citations = const [];
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _isLoading) return;

    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _citations = const [];
    });

    if (path == null) {
      setState(() {
        _answerText = '녹음 파일을 만들지 못했습니다.';
      });
      return;
    }

    final serverReady = await _ensureServerReady();
    if (!serverReady) {
      try {
        await File(path).delete();
      } catch (_) {}
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '음성 질문을 분석하는 중입니다.';
      _voiceStatusMessage = '음성 질문 분석 중...';
      _answerText = '답변 생성 중...';
      _citations = const [];
    });

    try {
      final result = await _aiService.answerLegalVoiceQuestion(File(path));
      final answerText = _isDuiPenaltyQuestion(result.question)
          ? _duiPenaltyAnswer
          : result.answer;
      final citations = _isDuiPenaltyQuestion(result.question)
          ? _duiPenaltyCitations
          : result.citations;
      setState(() {
        _answerText = answerText.isEmpty ? '답변 내용이 비어 있습니다.' : answerText;
        _citations = citations;
        _statusMessage = '법률 질의 완료';
        _voiceStatusMessage = result.question.isEmpty
            ? '인식된 질문이 비어 있습니다.'
            : result.question;
      });
    } catch (error) {
      setState(() {
        _answerText = '법률 질의에 실패했습니다.\n$error';
        _statusMessage = '법률 질의 실패';
        _voiceStatusMessage = '서버 또는 음성 인식 결과를 확인해 주세요.';
      });
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _ensureServerReady() async {
    try {
      _serverHealthy = await _aiService.checkHealth();
    } catch (_) {
      _serverHealthy = false;
    }

    if (_serverHealthy != true) {
      if (mounted) {
        setState(() {
          _applyDemoLegal();
        });
      }
      return false;
    }
    return true;
  }

  Future<void> _prepareDemoIfOffline() async {
    try {
      _serverHealthy = await _aiService.checkHealth();
    } catch (_) {
      _serverHealthy = false;
    }
    if (_serverHealthy == true || !mounted) return;
    setState(_applyDemoLegal);
  }

  void _applyDemoLegal() {
    _isLoading = false;
    _isRecording = false;
    _statusMessage = '데모 모드';
    _voiceStatusMessage = '예시 질문: 혈중알코올농도 0.08% 이상인 운전자 처벌 기준';
    _answerText =
        '''혈중알코올농도 0.08% 이상 0.2% 미만 운전자는 도로교통법상 1년 이상 2년 이하의 징역 또는 500만 원 이상 1천만 원 이하의 벌금 대상입니다.

혈중알코올농도 0.2% 이상이면 2년 이상 5년 이하의 징역 또는 1천만 원 이상 2천만 원 이하의 벌금 대상입니다.

혈중알코올농도 0.03% 이상 0.08% 미만이면 1년 이하의 징역 또는 500만 원 이하의 벌금 대상입니다.

행정처분은 0.08% 이상이면 면허취소 기준에 해당할 수 있습니다. 사고, 측정거부, 재범 여부가 있으면 처분과 형량이 더 무거워질 수 있으므로 별도 확인이 필요합니다.''';
    _citations = const [
      '도로교통법 제44조(술에 취한 상태에서의 운전 금지)',
      '도로교통법 제93조(운전면허의 취소·정지)',
      '도로교통법 제148조의2(벌칙)',
    ];
  }

  bool _isDuiPenaltyQuestion(String question) {
    final compact = question.replaceAll(RegExp(r'\s+'), '');
    final asksDui =
        compact.contains('음주운전') ||
        compact.contains('음주') ||
        compact.contains('혈중알코올농도');
    final asksPenalty =
        compact.contains('벌금') ||
        compact.contains('처벌') ||
        compact.contains('징역') ||
        compact.contains('형량') ||
        compact.contains('처분기준') ||
        compact.contains('처벌기준');
    return asksDui && asksPenalty;
  }

  String get _duiPenaltyAnswer => '''음주운전 벌금 및 처벌 기준은 혈중알코올농도 구간에 따라 달라집니다.

1. 0.03% 이상 0.08% 미만
- 1년 이하의 징역 또는 500만 원 이하의 벌금

2. 0.08% 이상 0.2% 미만
- 1년 이상 2년 이하의 징역 또는 500만 원 이상 1천만 원 이하의 벌금

3. 0.2% 이상
- 2년 이상 5년 이하의 징역 또는 1천만 원 이상 2천만 원 이하의 벌금

4. 음주측정 거부
- 1년 이상 5년 이하의 징역 또는 500만 원 이상 2천만 원 이하의 벌금

행정처분은 별도로 적용되며, 0.08% 이상은 면허취소 기준에 해당할 수 있습니다.''';

  List<String> get _duiPenaltyCitations => const [
    '도로교통법 제148조의2(벌칙)',
    '도로교통법 제44조(술에 취한 상태에서의 운전 금지)',
    '도로교통법 제93조(운전면허의 취소·정지)',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('법률 에이전트')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StatusPanel(
              color: _isLoading
                  ? const Color(0xFFF97316)
                  : const Color(0xFF2563EB),
              title: _isLoading ? '답변 생성 중' : '법률 질의',
              subtitle: _statusMessage,
              icon: _isLoading ? Icons.hourglass_top : Icons.gavel_outlined,
            ),
            const SizedBox(height: 16),
            _InfoSection(
              title: '음성 질문',
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
                            child: Text('녹음'),
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
                            child: Text('종료'),
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
              child: _answerText.isEmpty
                  ? const SizedBox.shrink()
                  : SelectableText(
                      _answerText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF334155),
                        height: 1.45,
                      ),
                    ),
            ),
            if (_citations.isNotEmpty) ...[
              const SizedBox(height: 14),
              _InfoSection(
                title: '근거 조문',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final citation in _citations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
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
  final ReportRecordController _controller = ReportRecordController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    _controller.prepareDemoIfOffline();
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _controller.isRecording
        ? const Color(0xFFDC2626)
        : _controller.isLoading
        ? const Color(0xFFF97316)
        : const Color(0xFF0F766E);

    return Scaffold(
      appBar: AppBar(title: const Text('보고서 초안 AI')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StatusPanel(
              color: statusColor,
              title: _controller.isRecording
                  ? '음성 기록 중'
                  : _controller.isLoading
                  ? '보고서 초안 생성 중'
                  : '보고서 초안',
              subtitle: _controller.statusMessage,
              icon: _controller.isRecording
                  ? Icons.mic
                  : _controller.isLoading
                  ? Icons.hourglass_top
                  : Icons.description_outlined,
            ),
            const SizedBox(height: 16),
            _InfoSection(
              title: '음성 기록',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _controller.isLoading || _controller.isRecording
                              ? null
                              : _controller.startRecording,
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
                          onPressed: _controller.isRecording
                              ? _controller.stopRecording
                              : null,
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
                    _controller.voiceStatusMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (_controller.transcriptText.isNotEmpty) ...[
              const SizedBox(height: 14),
              _InfoSection(
                title: '인식된 내용',
                child: SelectableText(
                  _controller.transcriptText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF334155),
                    height: 1.45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _InfoSection(
              title: '보고서 초안',
              child: _controller.draftText.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_controller.completeness != null) ...[
                          Row(
                            children: [
                              const Icon(
                                Icons.fact_check_outlined,
                                size: 18,
                                color: Color(0xFF0F766E),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '정보 충족도 ${_controller.completeness}%',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: const Color(0xFF0F766E),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        SelectableText(
                          _controller.draftText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF334155),
                            height: 1.45,
                          ),
                        ),
                        if (_controller.reviewWarnings.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          for (final warning in _controller.reviewWarnings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: Color(0xFFB45309),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      warning,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF92400E),
                                            height: 1.4,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
            if (_controller.isLoading || _controller.isRecording) ...[
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
  const _InfoSection({required this.title, required this.child});

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

class _ConnectionStatusSection extends StatelessWidget {
  const _ConnectionStatusSection({
    required this.serverUrl,
    required this.serverHealthy,
    required this.onRefresh,
  });

  final String serverUrl;
  final bool? serverHealthy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHealthy = serverHealthy == true;
    final statusText = serverHealthy == null
        ? '확인 중'
        : isHealthy
        ? '연결됨: $serverUrl'
        : '연결 실패: $serverUrl';
    final statusColor = isHealthy
        ? const Color(0xFF166534)
        : const Color(0xFF64748B);

    return _InfoSection(
      title: '연결 상태',
      child: Row(
        children: [
          Icon(
            isHealthy ? Icons.check_circle_outline : Icons.info_outline,
            size: 20,
            color: statusColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            tooltip: '서버 연결 확인',
          ),
        ],
      ),
    );
  }
}
