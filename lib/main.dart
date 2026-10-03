import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import 'services/app_alert_service.dart';

import 'pages/platform_home_page_mobile.dart'
    if (dart.library.js_interop) 'pages/platform_home_page_web.dart';

const String _naverMapClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    if (_naverMapClientId.isEmpty) {
      throw StateError(
        'NAVER_MAP_CLIENT_ID가 필요합니다. '
        '--dart-define=NAVER_MAP_CLIENT_ID=... 로 실행하세요.',
      );
    }
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
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'POL APP',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00C73C)),
        useMaterial3: true,
      ),
      home: buildPlatformHomePage(),
    );
  }
}
