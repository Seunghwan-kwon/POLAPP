import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'map_home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/server_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _officerIdController = TextEditingController();
  final TextEditingController _matchingCodeController = TextEditingController();
  bool _isLoading = false;

  void _performLogin() async {
    if (_isLoading) return;

    final String officerId = _officerIdController.text.trim();
    final String matchingCode = _matchingCodeController.text.trim();

    if (officerId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('사번(예: P-1001)을 입력해 주세요.')));
      return;
    }
    if (matchingCode.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('발급받은 매칭 코드를 입력해 주세요.')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String apiUrl = apiEndpoint('/login');

      debugPrint('[Auth] 로그인 시도 - URL: $apiUrl, ID: $officerId');

      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: <String, String>{
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: jsonEncode(<String, String>{
              'officerId': officerId,
              'matchingCode': matchingCode,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('로그인 응답 형식이 올바르지 않습니다.');
        }
        final token = decoded['token']?.toString().trim() ?? '';
        if (token.isEmpty) {
          throw const FormatException('로그인 응답에 인증 토큰이 없습니다.');
        }
        final validatedId = decoded['officerId']?.toString() ?? officerId;
        final name = decoded['name']?.toString() ?? '이름 미상';
        final rank = decoded['rank']?.toString() ?? '계급 미상';
        final region = decoded['region']?.toString() ?? 'UNKNOWN_REGION';
        final affiliation = decoded['affiliation']?.toString() ?? '소속 미상';
        final role = decoded['role']?.toString() ?? 'USER';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('officerId', validatedId);
        await prefs.setString('authToken', token);
        await prefs.setString('officerName', name);
        await prefs.setString('officerRank', rank);
        await prefs.setString('officerRegion', region);
        await prefs.setString('officerAffiliation', affiliation);
        await prefs.setString('officerRole', role);

        debugPrint('[Auth] 로그인 성공! 사번: $validatedId, $rank $name');

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MapHomePage()),
          );
        }
      } else {
        debugPrint('[Auth] 로그인 실패 - 상태코드: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('사번 또는 코드가 일치하지 않습니다.')));
        }
      }
    } catch (e) {
      debugPrint('[Auth Error] 예외 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서버와 통신할 수 없습니다. 네트워크를 확인해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            children: [
              const SizedBox(height: 50),

              Column(
                children: [
                  Image.asset('assets/icons/police_logo.png', height: 180),
                  const SizedBox(height: 5),
                  const Text(
                    'POL APP',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B3B6F),
                      letterSpacing: 3,
                    ),
                  ),
                  const Text(
                    '현장 지원 시스템',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 60),

              TextField(
                controller: _officerIdController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.badge_outlined),
                  labelText: '사번',
                  hintText: 'P-1001',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.visiblePassword,
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _matchingCodeController,
                obscureText: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.key),
                  labelText: '발급받은 코드 입력',
                  hintText: '5자리 코드 입력',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _performLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B3B6F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '접 속',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                '문제 발생 시 상황실로 문의하세요.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
