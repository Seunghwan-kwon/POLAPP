import 'dart:convert';

import 'package:http/browser_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_config.dart';

class AdminThreatAlertService {
  AdminThreatAlertService({BrowserClient? client})
    : _client = client ?? (BrowserClient()..withCredentials = true);

  final BrowserClient _client;

  Future<List<Map<String, dynamic>>> fetch({int limit = 50}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final headers = {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final uri = Uri.parse(
      apiEndpoint('/threat-alerts'),
    ).replace(queryParameters: {'limit': '$limit'});
    final response = await _client.get(uri, headers: headers);
    final body = jsonDecode(response.body);
    if (response.statusCode != 200 || body is! Map || body['code'] != 0) {
      throw const AdminThreatAlertException('위협 알림 목록을 불러오지 못했습니다.');
    }
    final result = body['result'];
    if (result is! List) {
      throw const AdminThreatAlertException('위협 알림 응답 형식이 올바르지 않습니다.');
    }
    return result
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class AdminThreatAlertException implements Exception {
  const AdminThreatAlertException(this.message);

  final String message;

  @override
  String toString() => message;
}
