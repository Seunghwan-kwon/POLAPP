import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'pages/app_entry_page.dart';

// Naver Map SDK 초기화에 사용하는 클라이언트 ID
const String _naverMapClientId = '9nh2znn5h7';

Future<void> main() async {
  // runApp 전에 SDK 초기화가 필요하므로 Flutter 바인딩을 먼저 준비한다.
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterNaverMap().init(
    clientId: _naverMapClientId,
    onAuthFailed: (ex) {
      debugPrint('Naver Map auth failed: $ex');
    },
  );

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
      home: const AppEntryPage(),
    );
  }
}
