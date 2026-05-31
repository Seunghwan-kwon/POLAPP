import 'dart:convert';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

import '../models/report.dart';

// 백엔드 /reports API는 로그인 세션 쿠키를 기준으로 권한을 확인한다.
// Flutter Web에서는 withCredentials를 켜야 브라우저가 세션 쿠키를 함께 보낸다.
class ReportApiService {
  ReportApiService({
    String? baseUrl,
    BrowserClient? client,
  })  : _baseUrl = _normalizeBaseUrl(
          baseUrl ??
              const String.fromEnvironment('API_SERVER_URL',
                  defaultValue: String.fromEnvironment(
                    'WS_SERVER_URL',
                    defaultValue: 'https://polapp.duckdns.org:444',
                  )),
        ),
        _client = client ?? (BrowserClient()..withCredentials = true);

  final String _baseUrl;
  final BrowserClient _client;

  Future<List<Report>> fetchReports({String status = 'ALL'}) async {
    final uri = Uri.parse('$_baseUrl/reports').replace(
      queryParameters: {'status': status},
    );
    final response = await _client.get(uri).onError<http.ClientException>((error, stackTrace) {
      throw const ReportApiException(
        '브라우저가 사건 목록 요청을 차단했습니다. 백엔드 CORS/세션 쿠키 설정을 확인해야 합니다.',
      );
    });
    final result = _decodeResult(response.body);

    if (result is! List) {
      throw const ReportApiException('사건 목록 응답 형식이 올바르지 않습니다.');
    }

    return result
        .whereType<Map>()
        .map((item) => Report.fromJson(Map<String, dynamic>.from(item)))
        .map(_fixSuspiciousCoordinates)
        .toList();
  }

  Future<Report> createReport({
    required String title,
    required String description,
    required String severity,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/reports'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'description': description,
        'severity': severity,
        'latitude': latitude,
        'longitude': longitude,
      }),
    ).onError<http.ClientException>((error, stackTrace) {
      // 브라우저에서 "Failed to fetch"가 발생하면 대개 서버 CORS 설정이 쿠키 포함 요청을 막은 것이다.
      // 백엔드는 Access-Control-Allow-Credentials: true와 적절한 SameSite/Secure 쿠키 설정이 필요하다.
      throw const ReportApiException(
        '브라우저가 사건 생성 요청을 차단했습니다. 백엔드 CORS/세션 쿠키 설정을 확인해야 합니다.',
      );
    });

    final result = _decodeResult(response.body);
    if (result is! Map) {
      throw const ReportApiException('사건 생성 응답 형식이 올바르지 않습니다.');
    }

    return _fixSuspiciousCoordinates(
      Report.fromJson(Map<String, dynamic>.from(result)),
    );
  }

  Future<void> closeReport(String reportId) async {
    final response = await _client
        .patch(Uri.parse('$_baseUrl/reports/$reportId/close'))
        .onError<http.ClientException>((error, stackTrace) {
      throw const ReportApiException(
        '브라우저가 사건 종료 요청을 차단했습니다. 백엔드 CORS/세션 쿠키 설정을 확인해야 합니다.',
      );
    });
    _decodeResult(response.body);
  }

  Object? _decodeResult(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const ReportApiException('서버 응답 형식이 올바르지 않습니다.');
    }

    final code = decoded['code'];
    if (code != 0) {
      throw ReportApiException('서버 요청 실패(code: $code)');
    }

    return decoded['result'];
  }

  static String _normalizeBaseUrl(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  // 현재 백엔드 커밋의 GET 조회 경로에는 latitude/longitude가 뒤집혀 반환될 수 있는 코드가 있다.
  // 위도 범위를 벗어난 값이 오면 프론트에서 한 번 보정해 지도 밖으로 마커가 사라지는 것을 막는다.
  static Report _fixSuspiciousCoordinates(Report report) {
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
}

class ReportApiException implements Exception {
  const ReportApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
