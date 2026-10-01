import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'server_config.dart';

class ThreatAlertService {
  ThreatAlertService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> publish({
    required String eventId,
    required String sessionId,
    required String category,
    required String alertLabel,
    required int riskLevel,
    required double evidenceIndex,
    required List<String> reasons,
    required DateTime occurredAt,
  }) async {
    final token = await AuthService.getAuthToken();
    if (token == null || token.isEmpty) {
      throw const ThreatAlertException('로그인 정보가 없어 관리자 알림을 전송할 수 없습니다.');
    }

    final response = await _client
        .post(
          Uri.parse(apiEndpoint('/threat-alerts')),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'eventId': eventId,
            'sessionId': sessionId,
            'category': category,
            'alertLabel': alertLabel,
            'riskLevel': riskLevel,
            'evidenceIndex': evidenceIndex,
            'reasons': reasons,
            'occurredAt': occurredAt.toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 3));

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ThreatAlertException('로그인이 만료되었습니다. 다시 로그인해 주세요.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ThreatAlertException('위협 알림 전송 실패(code: ${response.statusCode})');
    }
  }
}

class ThreatAlertException implements Exception {
  const ThreatAlertException(this.message);

  final String message;

  @override
  String toString() => message;
}
