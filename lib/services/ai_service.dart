import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const String _defaultAiServerUrl = 'http://10.0.2.2:8765';
const String _aiServerUrl = String.fromEnvironment(
  'AI_SERVER_URL',
  defaultValue: _defaultAiServerUrl,
);

class ProfanityAnalysisResult {
  const ProfanityAnalysisResult({
    required this.text,
    required this.isProfanity,
    required this.score,
    required this.matched,
  });

  final String text;
  final bool isProfanity;
  final double score;
  final List<String> matched;

  factory ProfanityAnalysisResult.fromJson(Map<String, dynamic> json) {
    return ProfanityAnalysisResult(
      text: json['text']?.toString() ?? '',
      isProfanity: json['is_profanity'] == true,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      matched: (json['matched'] as List<dynamic>? ?? const [])
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
  });

  final String transcript;
  final String draft;

  factory ReportDraftResult.fromJson(Map<String, dynamic> json) {
    return ReportDraftResult(
      transcript: json['transcript']?.toString() ?? '',
      draft: json['draft']?.toString() ?? '',
    );
  }
}

class AiService {
  AiService({
    http.Client? client,
    String? serverUrl,
  })  : _client = client ?? http.Client(),
        _serverUrl = (serverUrl ?? _aiServerUrl).replaceFirst(
          RegExp(r'/$'),
          '',
        );

  final http.Client _client;
  final String _serverUrl;

  String get serverUrl => _serverUrl;

  Future<bool> checkHealth() async {
    final response = await _client
        .get(Uri.parse('$_serverUrl/health'))
        .timeout(const Duration(seconds: 3));
    return response.statusCode == 200;
  }

  Future<ProfanityAnalysisResult> analyzeProfanity(File wavFile) async {
    final bytes = await wavFile.readAsBytes();
    final response = await _client
        .post(
          Uri.parse('$_serverUrl/profanity/analyze'),
          headers: const {
            'Content-Type': 'audio/wav',
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 60));

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] ?? decoded['error'] ?? 'AI server error'
          : 'AI server error';
      throw AiServiceException(message.toString());
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('Invalid AI server response');
    }
    return ProfanityAnalysisResult.fromJson(decoded);
  }

  Future<LegalAnswerResult> answerLegalQuestion(String question) async {
    final response = await _client
        .post(
          Uri.parse('$_serverUrl/legal/answer'),
          headers: const {
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({'question': question}),
        )
        .timeout(const Duration(seconds: 90));

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] ?? decoded['error'] ?? 'AI server error'
          : 'AI server error';
      throw AiServiceException(message.toString());
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('Invalid AI server response');
    }
    return LegalAnswerResult.fromJson(decoded);
  }

  Future<LegalAnswerResult> answerLegalVoiceQuestion(File wavFile) async {
    final bytes = await wavFile.readAsBytes();
    final response = await _client
        .post(
          Uri.parse('$_serverUrl/legal/voice-answer'),
          headers: const {
            'Content-Type': 'audio/wav',
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 120));

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] ?? decoded['error'] ?? 'AI server error'
          : 'AI server error';
      throw AiServiceException(message.toString());
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('Invalid AI server response');
    }
    return LegalAnswerResult.fromJson(decoded);
  }

  Future<ReportDraftResult> draftReport(String transcript) async {
    final response = await _client
        .post(
          Uri.parse('$_serverUrl/report/draft'),
          headers: const {
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({'transcript': transcript}),
        )
        .timeout(const Duration(seconds: 90));

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] ?? decoded['error'] ?? 'AI server error'
          : 'AI server error';
      throw AiServiceException(message.toString());
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('Invalid AI server response');
    }
    return ReportDraftResult.fromJson(decoded);
  }

  Future<ReportDraftResult> draftReportFromVoice(File wavFile) async {
    final bytes = await wavFile.readAsBytes();
    final response = await _client
        .post(
          Uri.parse('$_serverUrl/report/voice-draft'),
          headers: const {
            'Content-Type': 'audio/wav',
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 120));

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] ?? decoded['error'] ?? 'AI server error'
          : 'AI server error';
      throw AiServiceException(message.toString());
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('Invalid AI server response');
    }
    return ReportDraftResult.fromJson(decoded);
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
