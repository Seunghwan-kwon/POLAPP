import 'package:flutter/material.dart';

// 사건 목록 리스트 페이지
// 백엔드 연동 필요
class AdminDashboardList extends StatelessWidget {
  const AdminDashboardList({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1B3B6F),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.list_alt, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '사건 목록',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          // 아래 내용들은 더미 데이터로 사건 접수 구현 시 백엔드와 연동해서 내용 표시
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                ListTile(
                  leading: Icon(Icons.crisis_alert, color: Colors.redAccent),
                  title: Text('신고 접수 #001'),
                  subtitle: Text('위치: 광운대역 인근\n상태: 접수 대기'),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.warning_amber, color: Colors.orange),
                  title: Text('위험 감지 #002'),
                  subtitle: Text('위치: 월계동 골목\n상태: 확인 중'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
