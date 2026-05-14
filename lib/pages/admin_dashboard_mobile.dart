import 'package:flutter/material.dart';

// 모바일 빌더가 에러를 발생시키지 않게 해주는 가짜 클래스
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('이 페이지는 웹 환경에서만 지원됩니다.'),
      ),
    );
  }
}
