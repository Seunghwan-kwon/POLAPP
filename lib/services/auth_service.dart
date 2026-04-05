
// 예시용 로그인 상태 관리 클래스

class AuthService {
  // 실제 인증 연동 전까지 사용할 임시 로그인 상태값
  static bool _loggedIn = false;

  static Future<bool> isLoggedIn() async {
    return _loggedIn;
  }

  static Future<void> login() async {
    _loggedIn = true;
  }

  static Future<void> logout() async {
    _loggedIn = false;
  }
}
