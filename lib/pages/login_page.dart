import 'dart:convert'; // JSON 파싱을 위해 추가
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:http/http.dart' as http; // HTTP 통신 패키지 임포트
import 'map_home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 컨트롤러 이름과 텍스트를 직관적으로 변경
  final TextEditingController _officerIdController = TextEditingController(); // 사번 입력
  final TextEditingController _matchingCodeController = TextEditingController(); // 매칭 코드 입력
  bool _isLoading = false; // 로그인 중 로딩 상태 표시

  /// 사번과 매칭 코드를 백엔드로 보내 검증하고 토큰을 받아오는 함수
  void _performLogin() async {
    if (_isLoading) return; // 이미 로딩 중이라면 터치 중복 방지

    final String officerId = _officerIdController.text.trim();
    final String matchingCode = _matchingCodeController.text.trim();

    // 간단한 유효성 검사 (입력칸이 비어있는지)
    if (officerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사번(예: P-1001)을 입력해 주세요.')),
      );
      return;
    }
    if (matchingCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('발급받은 매칭 코드를 입력해 주세요.')),
      );
      return;
    }

    setState(() {
      _isLoading = true; // 로딩 시작 (화면에 인디케이터 표시)
    });

    try {
      final String apiUrl = 'https://polapp.duckdns.org:444/login';

      debugPrint('[Auth] 로그인 시도 - URL: $apiUrl, ID: $officerId');

      // HTTP POST 요청 발송
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          // 백엔드 요청 스펙에 맞게 데이터 전송
          'officerId': officerId, 
          'matchingCode': matchingCode,
        }),
      ).timeout(const Duration(seconds: 5)); // 5초 타임아웃 설정

      // 서버 응답 확인
      if (response.statusCode == 200) {
        // 백엔드 인증 성공
        final dynamic data = jsonDecode(response.body);
        final String validatedId = data['officerId'] ?? officerId; 
        final String token = data['token'] ?? 'temp-token'; // 백엔드에서 아직 token을 안 준다면 임시값 사용

        // 휴대폰 내부 금고(SharedPreferences)에 인증 정보를 안전하게 저장합니다.
        await AuthService.login(
          officerId: validatedId,
          token: token,
        );

        debugPrint('[Auth] 로그인 성공! 사번: $validatedId');

        // 성공 시 지도 화면으로 이동
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MapHomePage()),
          );
        }
      } else {
        // 백엔드 인증 실패 (예: 코드 불일치 등)
        debugPrint('[Auth] 로그인 실패 - 상태코드: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사번 또는 코드가 일치하지 않습니다.')),
          );
        }
      }
    } catch (e) {
      // 네트워크 에러 등 예외 처리
      debugPrint('[Auth Error] 예외 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서버와 통신할 수 없습니다. 네트워크를 확인해 주세요.')),
        );
      }
    } finally {
      // 성공이든 실패든 로그인 시도가 끝나면 로딩 상태 해제
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
              // 로고 섹션
              Column(
                children: [
                  Image.asset(
                    'assets/icons/police_logo.png', // 경찰 로고
                    height: 180,
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'POL APP',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B3B6F), // 남색 계열
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
              
              // 사번(Officer ID) 입력 필드
              TextField(
                controller: _officerIdController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.badge_outlined), // 사번 느낌 아이콘
                  labelText: '사번',
                  hintText: 'P-1001', // 예시 추가
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.visiblePassword, // 사번 형식에 맞게
              ),
              const SizedBox(height: 20),
              
              // 매칭 코드 입력 필드
              TextField(
                controller: _matchingCodeController,
                obscureText: true, // 코드 입력 시 마스킹 처리 (보안)
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.key), // 열쇠 모양 아이콘
                  labelText: '발급받은 코드 입력',
                  hintText: '5자리 코드 입력',
                  border: OutlineInputBorder(),
                ),
              ),
              
              const SizedBox(height: 40),
              
              // 로그인 버튼
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
                      ? const CircularProgressIndicator(color: Colors.white) // 로딩 중 표시
                      : const Text(
                          '접 속',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              
              const SizedBox(height: 20),
              const Text(
                '문제 발생 시 상황실로 문의하세요.', // 안내 문구
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
