import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter/foundation.dart'; // kIsWeb을 사용하기 위해 추가

import 'pages/app_entry_page.dart'; 
import 'pages/admin_dashboard_stub.dart'
    if (dart.library.js_interop) 'pages/admin_dashboard_page.dart';

const String _naverMapClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID'); // 네이버 맵 앱 전용 클라이언트 ID

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 모바일 기기에서만 네이버 지도 모바일 SDK를 초기화
  if (!kIsWeb) {
    await FlutterNaverMap().init(
      clientId: _naverMapClientId,
      onAuthFailed: (ex) {
        debugPrint('Naver Map auth failed: $ex');
      },
    );
  }

  runApp(const PolApp());
}

class PolApp extends StatelessWidget {
  const PolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'POL APP',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00C73C)),
        useMaterial3: true,
      ),
      // 접속 환경에 따라 앱 또는 웹 페이지 출력
      // 웹 접속 : 관리자 페이지
      // 앱 접속 : 로그인 페이지
      home: kIsWeb ? const AdminDashboardPage() : const AppEntryPage(),
    );
  }
}
