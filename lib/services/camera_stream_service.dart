import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'server_config.dart';

class CameraStreamService {
  CameraStreamService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> setEnabled({
    required bool enabled,
    required String sessionId,
  }) async {
    final token = await AuthService.getAuthToken();
    if (token == null || token.isEmpty) {
      throw const CameraStreamException('로그인 정보가 없어 관리자 화면에 연결할 수 없습니다.');
    }

    final response = await _client
        .post(
          Uri.parse(apiEndpoint('/camera-stream/status')),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({'enabled': enabled, 'sessionId': sessionId}),
        )
        .timeout(const Duration(seconds: 4));

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const CameraStreamException('로그인이 만료되었습니다. 다시 로그인해 주세요.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CameraStreamException('카메라 상태 전송 실패(code: ${response.statusCode})');
    }
  }

  Future<void> uploadFrame({
    required Uint8List jpegBytes,
    required String sessionId,
    required List<Map<String, dynamic>> detections,
  }) async {
    final token = await AuthService.getAuthToken();
    if (token == null || token.isEmpty) {
      throw const CameraStreamException('로그인 정보가 없어 관리자 화면에 연결할 수 없습니다.');
    }

    final uri = Uri.parse(apiEndpoint('/camera-stream/frame')).replace(
      queryParameters: {
        'sessionId': sessionId,
        'detections': jsonEncode(detections),
      },
    );
    final response = await _client
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'image/jpeg',
          },
          body: jpegBytes,
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const CameraStreamException('로그인이 만료되었습니다. 다시 로그인해 주세요.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CameraStreamException('카메라 화면 전송 실패(code: ${response.statusCode})');
    }
  }

  void dispose() => _client.close();
}

class CameraStreamException implements Exception {
  const CameraStreamException(this.message);

  final String message;

  @override
  String toString() => message;
}
