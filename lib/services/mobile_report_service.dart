import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/report.dart';
import 'auth_service.dart';

class MobileReportService {
  MobileReportService({
    String? baseUrl,
    http.Client? client,
  })  : _baseUrl = _normalizeBaseUrl(
          baseUrl ??
              const String.fromEnvironment(
                'API_SERVER_URL',
                defaultValue: 'https://polapp.duckdns.org:444',
              ),
        ),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Future<List<Report>> fetchReports({String status = 'ALL'}) async {
    final token = await AuthService.getAuthToken();
    if (token == null || token.isEmpty) {
      throw const MobileReportException('로그인 토큰이 없습니다.');
    }

    final uri = Uri.parse('$_baseUrl/reports').replace(
      queryParameters: {'status': status},
    );
    final response = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final result = _decodeResult(response.body);

    if (result is! List) {
      throw const MobileReportException('사건 목록 응답 형식이 올바르지 않습니다.');
    }

    return result
        .whereType<Map>()
        .map((item) => Report.fromJson(Map<String, dynamic>.from(item)))
        .map(fixSuspiciousCoordinates)
        .toList();
  }

  Report parseReport(Object? data) {
    if (data is! Map) {
      throw const MobileReportException('사건 이벤트 형식이 올바르지 않습니다.');
    }
    return fixSuspiciousCoordinates(
      Report.fromJson(Map<String, dynamic>.from(data)),
    );
  }

  void close() {
    _client.close();
  }

  static Report fixSuspiciousCoordinates(Report report) {
    final latitudeLooksWrong = report.lat.abs() > 90;
    final longitudeLooksLikeLatitude = report.lng.abs() <= 90;
    if (!latitudeLooksWrong || !longitudeLooksLikeLatitude) return report;

    return Report(
      id: report.id,
      title: report.title,
      description: report.description,
      severity: report.severity,
      lat: report.lng,
      lng: report.lat,
      createdAt: report.createdAt,
      closedAt: report.closedAt,
      createdBy: report.createdBy,
      closedBy: report.closedBy,
      status: report.status,
    );
  }

  Object? _decodeResult(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const MobileReportException('서버 응답 형식이 올바르지 않습니다.');
    }

    final code = decoded['code'];
    if (code != 0) {
      throw MobileReportException('사건 목록 요청 실패(code: $code)');
    }

    return decoded['result'];
  }

  static String _normalizeBaseUrl(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
}

class MobileReportException implements Exception {
  const MobileReportException(this.message);

  final String message;

  @override
  String toString() => message;
}
