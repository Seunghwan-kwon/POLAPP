import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/browser_client.dart';

import 'admin_dashboard_page.dart'; 

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final TextEditingController _adminIdController = TextEditingController(); // 관리자 ID (사번) 입력
  final TextEditingController _matchingCodeController = TextEditingController(); // 매칭 코드 입력
  bool _isLoading = false;

  void _performWebLogin() async {
    if (_isLoading) return;

    final String adminId = _adminIdController.text.trim();
    final String matchingCode = _matchingCodeController.text.trim();

    if (adminId.isEmpty) {
      _showSnackBar('관리자 사번(ID)을 입력해 주세요.');
      return;
    }
    if (matchingCode.isEmpty) {
      _showSnackBar('발급받은 매칭 코드를 입력해 주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String apiUrl = 'https://polapp.duckdns.org:444/login';
      debugPrint('[Web Auth] 로그인 시도 - ID: $adminId');

      // 백엔드 /reports API는 express-session 쿠키로 사용자를 식별한다.
      // 따라서 로그인 요청도 credentials를 포함해 보내야 브라우저가 세션 쿠키를 저장하고 이후 /reports 요청에 다시 실어 보낸다.
      final client = BrowserClient()..withCredentials = true;
      final response = await client.post(
        Uri.parse(apiUrl),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'officerId': adminId,
          'matchingCode': matchingCode,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        final String validatedId = data['officerId'] ?? adminId;
        final String token = data['token'] ?? 'web-temp-token';
        final String role = data['role'] ?? 'ADMIN';

        // 웹 브라우저 로컬 스토리지에 인증 정보 저장
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('officerId', validatedId);
        await prefs.setString('authToken', token);
        await prefs.setString('officerRole', role);

        debugPrint('[Web Auth] 로그인 성공: $validatedId');

        if (mounted) {
          // 로그인 성공 시 웹 관리자 전용 대시보드로 이동
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const AdminDashboardPage()),
          );
        }
      } else {
        debugPrint('[Web Auth] 로그인 실패 - 상태코드: ${response.statusCode}');
        _showSnackBar('사번 또는 매칭 코드가 일치하지 않습니다.');
      }
    } catch (e) {
      debugPrint('[Web Auth Error] 예외 발생: $e');
      _showSnackBar('서버와 통신할 수 없습니다. 네트워크 상태를 확인해 주세요.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        width: 400, // 웹 화면에서 스낵바가 너무 길어지지 않도록 고정폭 설정
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6), 
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              // PC 화면에서 레이아웃이 깨지지 않도록 가로 길이를 제한한 핵심 카드 컨테이너
              width: 460,
              padding: const EdgeInsets.all(40.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단 헤더 (로고 가로 배치로 웹 스타일 폰트 밸런스 유지)
                  Row(
                    children: [
                      Image.asset(
                        'assets/icons/police_logo.png', // 경찰 로고
                        height: 110,
                      ),
                      const SizedBox(width: 16),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'POL APP ADMIN',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B3B6F),
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            '종합 상황실 시스템',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  
                  const Text(
                    '시스템 로그인',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '인가된 사번과 발급받은 매칭 코드를 입력하세요.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 32),

                  // 사번 입력 필드
                  const Text(
                    '관리자 사번 (ID)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _adminIdController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.account_box_outlined),
                      hintText: 'ADMIN-001',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    ),
                    onSubmitted: (_) => _performWebLogin(), // 엔터키 지원
                  ),
                  const SizedBox(height: 24),

                  // 매칭 코드 입력 필드
                  const Text(
                    '매칭 코드 (PIN)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _matchingCodeController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.lock_outline),
                      hintText: '발급된 보안 코드 입력',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    ),
                    onSubmitted: (_) => _performWebLogin(), // 엔터키 지원
                  ),
                  const SizedBox(height: 40),

                  // 접속 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _performWebLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B3B6F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              '시스템 접속',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 하단 안내 영역
                  const Center(
                    child: Text(
                      '본 시스템은 보안 구역으로 승인되지 않은 접근을 엄격히 금합니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
