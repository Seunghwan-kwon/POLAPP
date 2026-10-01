import 'dart:convert';
import 'dart:typed_data';

import 'package:http/browser_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_config.dart';

class AdminCameraStream {
  const AdminCameraStream({
    required this.officerId,
    required this.officerName,
    required this.rank,
    required this.region,
    required this.sessionId,
    required this.updatedAt,
    required this.detections,
  });

  final String officerId;
  final String officerName;
  final String rank;
  final String region;
  final String sessionId;
  final DateTime? updatedAt;
  final List<Map<String, dynamic>> detections;

  String get officerLabel {
    final name = [
      rank,
      officerName,
    ].where((value) => value.trim().isNotEmpty).join(' ');
    return name.isEmpty ? '현장 경찰관' : name;
  }

  factory AdminCameraStream.fromJson(Map<String, dynamic> json) {
    final rawDetections = json['detections'];
    return AdminCameraStream(
      officerId: json['officerId']?.toString() ?? '',
      officerName: json['officerName']?.toString() ?? '',
      rank: json['rank']?.toString() ?? '',
      region: json['region']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      detections: rawDetections is List
          ? rawDetections
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const [],
    );
  }
}

class AdminCameraStreamService {
  AdminCameraStreamService({BrowserClient? client})
    : _client = client ?? (BrowserClient()..withCredentials = true);

  final BrowserClient _client;

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    return {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<AdminCameraStream>> fetchStreams() async {
    final headers = await _authHeaders();
    final response = await _client
        .get(Uri.parse(apiEndpoint('/camera-streams')), headers: headers)
        .timeout(const Duration(seconds: 4));
    final body = jsonDecode(response.body);
    if (response.statusCode != 200 || body is! Map || body['code'] != 0) {
      throw const AdminCameraStreamException('카메라 목록을 불러오지 못했습니다.');
    }
    final result = body['result'];
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map(
          (item) => AdminCameraStream.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((stream) => stream.officerId.isNotEmpty)
        .toList();
  }

  Future<Uint8List> fetchFrame(String officerId) async {
    final headers = await _authHeaders();
    final encodedOfficerId = Uri.encodeComponent(officerId);
    final uri =
        Uri.parse(
          apiEndpoint('/camera-streams/$encodedOfficerId/frame'),
        ).replace(
          queryParameters: {
            't': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        );
    final response = await _client
        .get(uri, headers: {...headers, 'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw const AdminCameraStreamException('현장 화면을 불러오지 못했습니다.');
    }
    return response.bodyBytes;
  }

  void dispose() => _client.close();
}

class AdminCameraStreamException implements Exception {
  const AdminCameraStreamException(this.message);

  final String message;

  @override
  String toString() => message;
}
