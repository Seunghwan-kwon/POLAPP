import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pol_app/services/ai_service.dart';

void main() {
  test('health uses the backend readiness flag', () async {
    final service = AiService(
      serverUrl: 'http://localhost:8765',
      client: MockClient(
        (_) async => http.Response('{"status":"degraded","ready":false}', 200),
      ),
    );

    expect(await service.checkHealth(), isFalse);
    service.dispose();
  });

  test('legacy health response remains compatible', () async {
    final service = AiService(
      serverUrl: 'http://localhost:8765',
      client: MockClient((_) async => http.Response('{"status":"ok"}', 200)),
    );

    expect(await service.checkHealth(), isTrue);
    service.dispose();
  });

  test('invalid backend payload becomes an AI service error', () async {
    final service = AiService(
      serverUrl: 'http://localhost:8765',
      client: MockClient((_) async => http.Response('<html>error</html>', 200)),
    );

    expect(service.checkHealth(), throwsA(isA<AiServiceException>()));
    service.dispose();
  });

  test('report result parses review metadata', () {
    final result = ReportDraftResult.fromJson({
      'transcript': '현장에서 대상자가 칼을 들고 있는 것을 확인함.',
      'draft': '1. 사건 유형: 흉기 관련',
      'warnings': ['발생 일시 확인 필요'],
      'completeness': 67,
      'review_required': true,
      'used_model': true,
      'duration_seconds': 42.5,
    });

    expect(result.transcript, contains('칼'));
    expect(result.draft, contains('흉기 관련'));
    expect(result.warnings, ['발생 일시 확인 필요']);
    expect(result.completeness, 67);
    expect(result.reviewRequired, isTrue);
    expect(result.usedModel, isTrue);
    expect(result.durationSeconds, 42.5);
  });
}
