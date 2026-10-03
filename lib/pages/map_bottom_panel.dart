import 'package:flutter/material.dart';

import '../models/officer_profile.dart';
import '../models/police_facility.dart';
import '../models/report.dart';
import '../models/safety_status.dart';

// 하단 패널 구현 페이지

class MapBottomPanel extends StatelessWidget {
  const MapBottomPanel({
    super.key,
    required this.scrollController,
    required this.officerProfile,
    required this.status,
    required this.onNavigateToReport,
    this.selectedFacility,
    this.selectedReport,
  });

  final ScrollController scrollController;
  final OfficerProfile officerProfile;
  final SafetyStatus status;
  final ValueChanged<Report> onNavigateToReport;
  final PoliceFacility? selectedFacility;
  final Report? selectedReport;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4D9E2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              // 근무 정보
              const SizedBox(height: 20),
              const Text(
                '근무 정보',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: status.color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.local_police_outlined,
                            color: status.color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                officerProfile.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                officerProfile.rank,
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: status.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            status.icon,
                            color: status.color,
                            size: 18,
                          ),
                          // 현재 상태 변경 시 하단 패널 정보 반영
                          const SizedBox(width: 8),
                          Text(
                            '현재 상태: ${status.label}',
                            style: TextStyle(
                              color: status.color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 관할 시설 부분
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: selectedReport != null
                    ? _SelectedReportCard(
                        report: selectedReport!,
                        onNavigate: onNavigateToReport,
                      )
                    : selectedFacility == null
                    ? const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '관할 시설',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '지도에서 경찰 시설 마커를 선택하면 여기서 정보를 볼 수 있습니다.',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              height: 1.4,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '선택된 시설',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE8EEF9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.local_police,
                                  color: Color(0xFF2457C5),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  selectedFacility!.name,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '위도: ${selectedFacility!.position.latitude}',
                            style: const TextStyle(color: Color(0xFF4B5563)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '경도: ${selectedFacility!.position.longitude}',
                            style: const TextStyle(color: Color(0xFF4B5563)),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedReportCard extends StatelessWidget {
  const _SelectedReportCard({
    required this.report,
    required this.onNavigate,
  });

  final Report report;
  final ValueChanged<Report> onNavigate;

  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor(report.severity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '선택한 사건',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: severityColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_rounded, color: severityColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                report.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          report.description.isEmpty ? '상세 설명이 없습니다.' : report.description,
          style: const TextStyle(color: Color(0xFF4B5563), height: 1.4),
        ),
        const SizedBox(height: 12),
        _ReportInfoRow(label: '긴급도', value: report.severity),
        _ReportInfoRow(label: '상태', value: report.status.name.toUpperCase()),
        _ReportInfoRow(label: '접수 시각', value: _formatDateTime(report.createdAt)),
        _ReportInfoRow(label: '위도', value: report.lat.toStringAsFixed(6)),
        _ReportInfoRow(label: '경도', value: report.lng.toStringAsFixed(6)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => onNavigate(report),
            icon: const Icon(Icons.navigation),
            label: const Text('16(출발)'),
          ),
        ),
      ],
    );
  }

  static Color _severityColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return Colors.red;
      case 'HIGH':
        return Colors.deepOrange;
      case 'MEDIUM':
        return Colors.amber.shade700;
      default:
        return Colors.green;
    }
  }

  static String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _ReportInfoRow extends StatelessWidget {
  const _ReportInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Color(0xFF4B5563)),
      ),
    );
  }
}
