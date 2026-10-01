import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'camera_stream_service.dart';
import 'profanity_detection_controller.dart';
import 'threat_alert_service.dart';

class WeaponDetection {
  const WeaponDetection({
    required this.label,
    required this.score,
    required this.normalizedBox,
  });

  final String label;
  final double score;
  final Rect normalizedBox;

  bool get isKnife => label == 'knife';
  bool get isBottle => label == 'bottle';
  String get displayLabel => isKnife ? '칼' : '병';

  Map<String, dynamic> toJson() => {
    'label': label,
    'displayLabel': displayLabel,
    'score': score,
    'box': [
      normalizedBox.left,
      normalizedBox.top,
      normalizedBox.right,
      normalizedBox.bottom,
    ],
  };
}

class CameraThreatController extends ChangeNotifier
    with WidgetsBindingObserver {
  CameraThreatController._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final CameraThreatController instance = CameraThreatController._();

  static const String _modelAsset =
      'assets/models/weapon_detector_finetuned.onnx';
  static const String _thresholdsAsset = 'assets/models/thresholds.json';
  static const Duration _frameInterval = Duration(milliseconds: 1100);
  static const Duration _alertCooldown = Duration(seconds: 15);

  final CameraStreamService _streamService = CameraStreamService();
  final ThreatAlertService _threatAlertService = ThreatAlertService();

  CameraController? _cameraController;
  OrtSession? _session;
  Map<String, double> _thresholds = const {'bottle': 0.4, 'knife': 0.4};
  List<WeaponDetection> _detections = const [];
  Uint8List? _latestFrameJpeg;
  DateTime? _lastFrameAt;
  DateTime? _lastAlertAt;
  String _lastAlertSignature = '';
  String _sessionId = '';
  String _statusMessage = '카메라 감지 대기 중';
  String _remoteStatusMessage = '관리자 영상 연결 대기 중';
  int _frameWidth = 16;
  int _frameHeight = 9;
  int? _lastInferenceMilliseconds;
  bool _enabled = false;
  bool _initializing = false;
  bool _processing = false;
  bool _uploading = false;
  bool _remoteConnected = false;

  CameraController? get cameraController => _cameraController;
  bool get enabled => _enabled;
  bool get initializing => _initializing;
  bool get processing => _processing;
  String get statusMessage => _statusMessage;
  String get remoteStatusMessage => _remoteStatusMessage;
  bool get remoteConnected => _remoteConnected;
  List<WeaponDetection> get detections => List.unmodifiable(_detections);
  Uint8List? get latestFrameJpeg => _latestFrameJpeg;
  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  int? get lastInferenceMilliseconds => _lastInferenceMilliseconds;

  Future<void> start() async {
    if (_enabled || _initializing) return;
    _initializing = true;
    _statusMessage = '카메라와 탐지 모델 준비 중';
    notifyListeners();

    try {
      await _ensureModelLoaded();
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('CameraNotFound', '사용 가능한 카메라가 없습니다.');
      }
      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();

      _cameraController = controller;
      _sessionId = 'camera-${DateTime.now().microsecondsSinceEpoch}';
      _enabled = true;
      _statusMessage = '카메라 위험 물체 감지 중';
      _detections = const [];
      _latestFrameJpeg = null;
      _lastFrameAt = null;
      _remoteConnected = false;
      _remoteStatusMessage = '관리자 영상 연결 중';
      notifyListeners();

      await _notifyStreamStatus(true);
      await controller.startImageStream(_handleCameraImage);
    } on CameraException catch (error) {
      _statusMessage = error.code == 'CameraAccessDenied'
          ? '카메라 권한이 필요합니다.'
          : '카메라 시작 실패: ${error.description ?? error.code}';
      await _releaseCamera();
    } catch (error) {
      _statusMessage = '카메라 시작 실패: $error';
      await _releaseCamera();
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (!_enabled && !_initializing && _cameraController == null) return;
    final sessionId = _sessionId;
    _enabled = false;
    _initializing = false;
    _statusMessage = '카메라 감지 중지';
    _remoteConnected = false;
    _remoteStatusMessage = '관리자 영상 전송 중지';
    _detections = const [];
    notifyListeners();

    await _releaseCamera();
    if (sessionId.isNotEmpty) {
      try {
        await _streamService.setEnabled(enabled: false, sessionId: sessionId);
      } catch (error) {
        debugPrint('[Camera Stream] 종료 상태 전송 실패: $error');
      }
    }
  }

  Future<void> toggle(bool value) => value ? start() : stop();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_enabled &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      unawaited(stop());
    }
  }

  Future<void> _ensureModelLoaded() async {
    if (_session != null) return;
    OrtEnv.instance.init();
    final modelData = await rootBundle.load(_modelAsset);
    final options = OrtSessionOptions();
    try {
      _session = OrtSession.fromBuffer(modelData.buffer.asUint8List(), options);
    } finally {
      options.release();
    }

    final rawThresholds = jsonDecode(
      await rootBundle.loadString(_thresholdsAsset),
    );
    if (rawThresholds is Map) {
      _thresholds = {
        for (final entry in rawThresholds.entries)
          if (entry.value is num)
            entry.key.toString(): (entry.value as num).toDouble(),
      };
    }
  }

  void _handleCameraImage(CameraImage image) {
    if (!_enabled || _processing) return;
    final now = DateTime.now();
    if (_lastFrameAt != null &&
        now.difference(_lastFrameAt!) < _frameInterval) {
      return;
    }
    _lastFrameAt = now;
    _processing = true;

    final payload = <String, Object>{
      'width': image.width,
      'height': image.height,
      'format': image.format.group == ImageFormatGroup.bgra8888
          ? 'bgra8888'
          : 'yuv420',
      'orientation': _cameraController?.description.sensorOrientation ?? 0,
      'planes': image.planes
          .map(
            (plane) => <String, Object>{
              'bytes': Uint8List.fromList(plane.bytes),
              'bytesPerRow': plane.bytesPerRow,
              'bytesPerPixel': plane.bytesPerPixel ?? 1,
            },
          )
          .toList(),
    };
    unawaited(_processFrame(payload));
  }

  Future<void> _processFrame(Map<String, Object> payload) async {
    final stopwatch = Stopwatch()..start();
    try {
      final prepared = await compute(_prepareCameraFrame, payload);
      if (!_enabled) return;
      final input = prepared['input']! as Float32List;
      final inputTensor = OrtValueTensor.createTensorWithDataList(input, const [
        1,
        3,
        320,
        320,
      ]);
      final runOptions = OrtRunOptions();
      List<OrtValue?>? outputs;
      try {
        final future = _session?.runAsync(runOptions, {'image': inputTensor});
        outputs = future == null ? null : await future;
      } finally {
        inputTensor.release();
        runOptions.release();
      }
      if (outputs == null || outputs.length < 3) return;

      late final List<WeaponDetection> detections;
      try {
        if (!_enabled) return;
        detections = _parseDetections(outputs);
      } finally {
        for (final output in outputs) {
          output?.release();
        }
      }

      _latestFrameJpeg = prepared['jpeg']! as Uint8List;
      _frameWidth = prepared['width']! as int;
      _frameHeight = prepared['height']! as int;
      _detections = detections;
      _lastInferenceMilliseconds = stopwatch.elapsedMilliseconds;
      _statusMessage = detections.isEmpty
          ? '카메라 분석 중 · 위험 물체 없음'
          : '카메라 감지: ${detections.map((item) => item.displayLabel).toSet().join(', ')}';
      notifyListeners();

      unawaited(_uploadLatestFrame());
      unawaited(_publishCameraThreat(detections));
    } catch (error, stackTrace) {
      debugPrint('[Camera AI] 프레임 분석 실패: $error\n$stackTrace');
      if (_enabled) {
        _statusMessage = '카메라 분석 오류';
        notifyListeners();
      }
    } finally {
      _processing = false;
    }
  }

  List<WeaponDetection> _parseDetections(List<OrtValue?> outputs) {
    final boxes = _flattenNumbers(outputs[0]?.value);
    final scores = _flattenNumbers(outputs[1]?.value);
    final labels = _flattenNumbers(outputs[2]?.value);
    final count = math.min(
      math.min(scores.length, labels.length),
      boxes.length ~/ 4,
    );
    final detections = <WeaponDetection>[];

    for (var index = 0; index < count; index++) {
      final labelId = labels[index].toInt();
      final label = switch (labelId) {
        1 => 'bottle',
        2 => 'knife',
        _ => '',
      };
      if (label.isEmpty) continue;
      final score = scores[index].toDouble();
      if (score < (_thresholds[label] ?? 0.4)) continue;
      final offset = index * 4;
      final left = (boxes[offset] / 320).clamp(0.0, 1.0).toDouble();
      final top = (boxes[offset + 1] / 320).clamp(0.0, 1.0).toDouble();
      final right = (boxes[offset + 2] / 320).clamp(0.0, 1.0).toDouble();
      final bottom = (boxes[offset + 3] / 320).clamp(0.0, 1.0).toDouble();
      if (right <= left || bottom <= top) continue;
      detections.add(
        WeaponDetection(
          label: label,
          score: score,
          normalizedBox: Rect.fromLTRB(left, top, right, bottom),
        ),
      );
      if (detections.length >= 8) break;
    }
    return detections;
  }

  List<num> _flattenNumbers(Object? value) {
    final result = <num>[];
    void collect(Object? item) {
      if (item is num) {
        result.add(item);
      } else if (item is List) {
        for (final child in item) {
          collect(child);
        }
      }
    }

    collect(value);
    return result;
  }

  Future<void> _uploadLatestFrame() async {
    if (_uploading || !_enabled || _latestFrameJpeg == null) return;
    _uploading = true;
    try {
      await _streamService.uploadFrame(
        jpegBytes: _latestFrameJpeg!,
        sessionId: _sessionId,
        detections: _detections.map((item) => item.toJson()).toList(),
      );
      _setRemoteState(true, '관리자 화면으로 영상 전송 중');
    } catch (error) {
      debugPrint('[Camera Stream] 화면 전송 실패: $error');
      _setRemoteState(false, error.toString());
    } finally {
      _uploading = false;
    }
  }

  Future<void> _publishCameraThreat(List<WeaponDetection> detections) async {
    if (detections.isEmpty) return;
    final knife = detections.where((item) => item.isKnife).firstOrNull;
    final bottle = detections.where((item) => item.isBottle).firstOrNull;
    final audioRisk = ProfanityDetectionController.instance.lastResult?.risk;
    final hasRealAudioRisk =
        audioRisk != null &&
        audioRisk.algorithm != 'demo' &&
        audioRisk.level >= 2;

    String category;
    String label;
    int level;
    double evidenceIndex;
    List<String> reasons;

    if (knife != null) {
      category = 'camera_weapon';
      label = '흉기';
      level = math.max(3, hasRealAudioRisk ? audioRisk.level : 1);
      evidenceIndex = math.max(
        knife.score * 100,
        hasRealAudioRisk ? audioRisk.evidenceIndex : 0,
      );
      reasons = [
        '카메라에서 칼로 추정되는 물체 감지',
        if (hasRealAudioRisk) ...audioRisk.reasons,
      ];
    } else if (bottle != null && hasRealAudioRisk) {
      category = 'camera_context';
      label = audioRisk.alertLabel.isEmpty ? '위험 물체' : audioRisk.alertLabel;
      level = math.max(2, audioRisk.level);
      evidenceIndex = math.max(bottle.score * 70, audioRisk.evidenceIndex);
      reasons = [
        '카메라 분석: 병 감지 (${(bottle.score * 100).toStringAsFixed(0)}%)',
        ...audioRisk.reasons,
      ];
    } else {
      return;
    }

    final signature = '$category-$level';
    final now = DateTime.now();
    if (_lastAlertAt != null &&
        signature == _lastAlertSignature &&
        now.difference(_lastAlertAt!) < _alertCooldown) {
      return;
    }
    try {
      await _threatAlertService.publish(
        eventId: '$_sessionId-${now.microsecondsSinceEpoch}',
        sessionId: _sessionId,
        category: category,
        alertLabel: label,
        riskLevel: level.clamp(1, 4),
        evidenceIndex: evidenceIndex.clamp(0, 100),
        reasons: reasons.take(8).toList(),
        occurredAt: now,
      );
      _lastAlertAt = now;
      _lastAlertSignature = signature;
    } catch (error) {
      debugPrint('[Camera AI] 위험 알림 전송 실패: $error');
      _setRemoteState(false, error.toString());
    }
  }

  Future<void> _notifyStreamStatus(bool enabled) async {
    try {
      await _streamService.setEnabled(enabled: enabled, sessionId: _sessionId);
      if (enabled) {
        _setRemoteState(true, '관리자 연결됨 · 첫 화면 전송 대기');
      }
    } catch (error) {
      debugPrint('[Camera Stream] 상태 전송 실패: $error');
      _setRemoteState(false, error.toString());
    }
  }

  void _setRemoteState(bool connected, String message) {
    if (_remoteConnected == connected && _remoteStatusMessage == message) {
      return;
    }
    _remoteConnected = connected;
    _remoteStatusMessage = message;
    notifyListeners();
  }

  Future<void> _releaseCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
      await controller.dispose();
    }
    _processing = false;
  }
}

Map<String, Object> _prepareCameraFrame(Map<String, Object> payload) {
  final width = payload['width']! as int;
  final height = payload['height']! as int;
  final format = payload['format']! as String;
  final orientation = payload['orientation']! as int;
  final planes = (payload['planes']! as List).cast<Map>();
  var image = img.Image(width: width, height: height);

  if (format == 'bgra8888') {
    final plane = planes.first;
    final bytes = plane['bytes']! as Uint8List;
    final bytesPerRow = plane['bytesPerRow']! as int;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * bytesPerRow + x * 4;
        image.setPixelRgba(
          x,
          y,
          bytes[index + 2],
          bytes[index + 1],
          bytes[index],
          bytes[index + 3],
        );
      }
    }
  } else {
    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];
    final yBytes = yPlane['bytes']! as Uint8List;
    final uBytes = uPlane['bytes']! as Uint8List;
    final vBytes = vPlane['bytes']! as Uint8List;
    final yRowStride = yPlane['bytesPerRow']! as int;
    final uvRowStride = uPlane['bytesPerRow']! as int;
    final uvPixelStride = uPlane['bytesPerPixel']! as int;

    for (var y = 0; y < height; y++) {
      final uvRow = (y >> 1) * uvRowStride;
      for (var x = 0; x < width; x++) {
        final yValue = yBytes[y * yRowStride + x].toDouble();
        final uvIndex = uvRow + (x >> 1) * uvPixelStride;
        final u = uBytes[uvIndex].toDouble() - 128;
        final v = vBytes[uvIndex].toDouble() - 128;
        final r = (yValue + 1.402 * v).round().clamp(0, 255);
        final g = (yValue - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
        final b = (yValue + 1.772 * u).round().clamp(0, 255);
        image.setPixelRgb(x, y, r, g, b);
      }
    }
  }

  if (orientation == 90 || orientation == 180 || orientation == 270) {
    image = img.copyRotate(image, angle: orientation);
  }
  final frameWidth = image.width;
  final frameHeight = image.height;
  final modelImage = img.copyResize(
    image,
    width: 320,
    height: 320,
    interpolation: img.Interpolation.linear,
  );
  final input = Float32List(3 * 320 * 320);
  const channelSize = 320 * 320;
  for (var y = 0; y < 320; y++) {
    for (var x = 0; x < 320; x++) {
      final pixel = modelImage.getPixel(x, y);
      final index = y * 320 + x;
      input[index] = pixel.r.toDouble() / 255;
      input[channelSize + index] = pixel.g.toDouble() / 255;
      input[channelSize * 2 + index] = pixel.b.toDouble() / 255;
    }
  }

  final streamImage = image.width > 640
      ? img.copyResize(
          image,
          width: 640,
          interpolation: img.Interpolation.linear,
        )
      : image;
  final jpeg = Uint8List.fromList(img.encodeJpg(streamImage, quality: 68));
  return {
    'input': input,
    'jpeg': jpeg,
    'width': frameWidth,
    'height': frameHeight,
  };
}
