import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const String _defaultAiServerUrl = 'http://127.0.0.1:8765';
const String _aiServerUrl = String.fromEnvironment(
  'AI_SERVER_URL',
  defaultValue: _defaultAiServerUrl,
);
const String _aiServerToken = String.fromEnvironment('AI_SERVER_TOKEN');

class ProfanityAnalysisResult {
  const ProfanityAnalysisResult({
    required this.text,
    required this.isProfanity,
    required this.score,
    required this.matched,
    required this.category,
    required this.categoryLabel,
    this.risk,
  });

  final String text;
  final bool isProfanity;
  final double score;
  final List<String> matched;
  final String category;
  final String categoryLabel;
  final RiskAssessmentResult? risk;

  String get alertLabel {
    if (categoryLabel.isNotEmpty) return categoryLabel;
    if (risk?.alertLabel.isNotEmpty == true) return risk!.alertLabel;
    return '위협';
  }

  factory ProfanityAnalysisResult.fromJson(Map<String, dynamic> json) {
    return ProfanityAnalysisResult(
      text: json['text']?.toString() ?? '',
      isProfanity: json['is_threat'] == true || json['is_profanity'] == true,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      matched: (json['matched'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      category: json['category']?.toString() ?? 'none',
      categoryLabel: json['category_label']?.toString() ?? '',
      risk: json['risk'] is Map<String, dynamic>
          ? RiskAssessmentResult.fromJson(json['risk'] as Map<String, dynamic>)
          : null,
    );
  }
}

class RiskAssessmentResult {
  const RiskAssessmentResult({
    required this.algorithm,
    required this.level,
    required this.label,
    required this.alertLabel,
    required this.evidenceIndex,
    required this.guidance,
    required this.reasons,
    required this.signals,
    required this.baselineReady,
    required this.limitations,
  });

  final String algorithm;
  final int level;
  final String label;
  final String alertLabel;
  final double evidenceIndex;
  final List<String> guidance;
  final List<String> reasons;
  final Map<String, double> signals;
  final bool baselineReady;
  final List<String> limitations;

  factory RiskAssessmentResult.fromJson(Map<String, dynamic> json) {
    final rawSignals = json['signals'];
    return RiskAssessmentResult(
      algorithm: json['algorithm']?.toString() ?? '',
      level: (json['level'] as num?)?.toInt() ?? 1,
      label: json['label']?.toString() ?? '일반 대응',
      alertLabel: json['alert_label']?.toString() ?? '',
      evidenceIndex: (json['evidence_index'] as num?)?.toDouble() ?? 0,
      guidance: (json['guidance'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      reasons: (json['reasons'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      signals: rawSignals is Map<String, dynamic>
          ? rawSignals.map(
              (key, value) =>
                  MapEntry(key, value is num ? value.toDouble() : 0),
            )
          : const {},
      baselineReady: json['baseline_ready'] == true,
      limitations: (json['limitations'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class LegalAnswerResult {
  const LegalAnswerResult({
    required this.question,
    required this.answer,
    required this.citations,
    required this.usedModel,
  });

  final String question;
  final String answer;
  final List<String> citations;
  final bool usedModel;

  factory LegalAnswerResult.fromJson(Map<String, dynamic> json) {
    return LegalAnswerResult(
      question: json['question']?.toString() ?? '',
      answer: json['answer']?.toString() ?? '',
      citations: (json['citations'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      usedModel: json['used_model'] == true,
    );
  }
}

class ReportDraftResult {
  const ReportDraftResult({
    required this.transcript,
    required this.draft,
    required this.warnings,
    required this.completeness,
    required this.reviewRequired,
    required this.usedModel,
    required this.durationSeconds,
  });

  final String transcript;
  final String draft;
  final List<String> warnings;
  final int completeness;
  final bool reviewRequired;
  final bool usedModel;
  final double durationSeconds;

  factory ReportDraftResult.fromJson(Map<String, dynamic> json) {
    return ReportDraftResult(
      transcript: json['transcript']?.toString() ?? '',
      draft: json['draft']?.toString() ?? '',
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      completeness: (json['completeness'] as num?)?.toInt() ?? 0,
      reviewRequired: json['review_required'] != false,
      usedModel: json['used_model'] == true,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AiService {
  AiService({http.Client? client, String? serverUrl})
    : _client = client ?? http.Client(),
      _serverUrl = (serverUrl ?? _aiServerUrl).replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _serverUrl;

  String get serverUrl => _serverUrl;

  Map<String, String> _headers({String? contentType}) {
    final headers = <String, String>{};
    if (contentType != null) headers['Content-Type'] = contentType;
    if (_aiServerToken.isNotEmpty) {
      headers['X-AI-Server-Token'] = _aiServerToken;
    }
    return headers;
  }

  Future<bool> checkHealth() async {
    final response = await _client
        .get(Uri.parse('$_serverUrl/health'), headers: _headers())
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return false;
    final decoded = _decodeResponse(response);
    return decoded['ready'] is bool
        ? decoded['ready'] == true
        : decoded['status'] == 'ok';
  }

  Future<ProfanityAnalysisResult> analyzeThreatBytes(
    Uint8List wavBytes, {
    String? sessionId,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_serverUrl/threat/analyze'),
          headers: {
            ..._headers(contentType: 'audio/wav'),
            'X-Guardian-Session': ?sessionId,
          },
          body: wavBytes,
        )
        .timeout(const Duration(seconds: 60));

    final decoded = _decodeResponse(response);
    return ProfanityAnalysisResult.fromJson(decoded);
  }

  Future<LegalAnswerResult> answerLegalQuestion(String question) async {
    final response = await _client
        .post(
          Uri.parse('$_serverUrl/legal/answer'),
          headers: _headers(contentType: 'application/json; charset=utf-8'),
          body: jsonEncode({'question': question}),
        )
        .timeout(const Duration(seconds: 90));

    final decoded = _decodeResponse(response);
    return LegalAnswerResult.fromJson(decoded);
  }

  Future<LegalAnswerResult> answerLegalVoiceQuestion(File wavFile) async {
    final bytes = await wavFile.readAsBytes();
    final response = await _client
        .post(
          Uri.parse('$_serverUrl/legal/voice-answer'),
          headers: _headers(contentType: 'audio/wav'),
          body: bytes,
        )
        .timeout(const Duration(seconds: 120));

    final decoded = _decodeResponse(response);
    return LegalAnswerResult.fromJson(decoded);
  }

  Future<ReportDraftResult> draftReportFromVoice(File wavFile) async {
    final bytes = await wavFile.readAsBytes();
    final response = await _client
        .post(
          Uri.parse('$_serverUrl/report/voice-draft'),
          headers: _headers(contentType: 'audio/wav'),
          body: bytes,
        )
        .timeout(const Duration(minutes: 5));

    final decoded = _decodeResponse(response);
    return ReportDraftResult.fromJson(decoded);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw AiServiceException(
        'AI server returned an invalid response (${response.statusCode})',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('Invalid AI server response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          decoded['message'] ?? decoded['error'] ?? 'AI server error';
      throw AiServiceException(message.toString());
    }
    return decoded;
  }

  void dispose() {
    _client.close();
  }
}

class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
