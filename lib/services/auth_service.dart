import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _officerIdKey = 'officerId';
  static const String _authTokenKey = 'authToken';

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authTokenKey);

    return token != null && token.isNotEmpty;
  }

  static Future<void> login({
    required String officerId,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_officerIdKey, officerId);
    await prefs.setString(_authTokenKey, token);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_officerIdKey);
    await prefs.remove(_authTokenKey);
  }

  static Future<String?> getOfficerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_officerIdKey);
  }

  static Future<String?> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authTokenKey);
  }
}