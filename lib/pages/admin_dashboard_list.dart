import 'package:flutter/material.dart';

import '../models/report.dart';

// 사건 목록 패널 위젯: 사건 목록을 표시하고, 각 사건을 클릭하면 상세 패널이 열리도록 하는 역할
class AdminDashboardList extends StatelessWidget {
  const AdminDashboardList({
    super.key,
    required this.onClose,
    required this.reports,
    required this.onReportTap,
  });
  // 
  final VoidCallback onClose;
  final List<Report> reports;
  final ValueChanged<String> onReportTap;

  @override
  Widget build(BuildContext context) {
    final sortedReports = [...reports]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
                  tooltip: '닫기',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: sortedReports.isEmpty
                ? const Center(
                    child: Text(
                      '접수된 사건이 없습니다.',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: sortedReports.length,
                    separatorBuilder: (_, __) => const Divider(height: 20),
                    itemBuilder: (context, index) {
                      final report = sortedReports[index];
                      final isClosed = report.status == ReportStatus.closed;

                      // 목록 항목도 상세 패널과 같은 사건 id를 사용한다.
                      // 그래서 항목을 누르면 마커 클릭과 동일하게 우측 상세 패널이 열린다.
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        leading: Icon(
                          isClosed ? Icons.task_alt : Icons.crisis_alert,
                          color: isClosed ? Colors.grey : _severityColor(report.severity),
                        ),
                        title: Text(
                          report.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isClosed ? Colors.grey.shade700 : const Color(0xFF111827),
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '상태: ${isClosed ? '종결' : '접수'}\n'
                            '위치: ${report.lat.toStringAsFixed(6)}, ${report.lng.toStringAsFixed(6)}',
                          ),
                        ),
                        trailing: _ReportStatusChip(isClosed: isClosed),
                        onTap: () => onReportTap(report.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'URGENT':
        return Colors.red;
      case 'HIGH':
        return Colors.deepOrange;
      case 'MEDIUM':
        return Colors.orange;
      case 'LOW':
      default:
        return Colors.blueGrey;
    }
  }
}

class _ReportStatusChip extends StatelessWidget {
  const _ReportStatusChip({
    required this.isClosed,
  });

  final bool isClosed;

  @override
  Widget build(BuildContext context) {
    final color = isClosed ? Colors.grey : Colors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        isClosed ? '종결' : '접수',
        style: TextStyle(
          color: isClosed ? Colors.grey.shade700 : Colors.green.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
