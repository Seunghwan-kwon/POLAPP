import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../models/report.dart';

class ReportMarkerService {
  final Map<String, NMarker> _markers = {};

  Future<void> replaceReports({
    required NaverMapController controller,
    required Iterable<Report> reports,
    required ValueChanged<Report> onReportTap,
  }) async {
    await clear(controller);
    for (final report in reports) {
      await upsertReport(
        controller: controller,
        report: report,
        onReportTap: onReportTap,
      );
    }
  }

  Future<void> upsertReport({
    required NaverMapController controller,
    required Report report,
    required ValueChanged<Report> onReportTap,
  }) async {
    await removeReport(controller: controller, reportId: report.id);
    if (report.status == ReportStatus.closed) return;

    final marker = NMarker(
      id: 'report-${report.id}',
      position: NLatLng(report.lat, report.lng),
      iconTintColor: _markerColor(report.severity),
      caption: NOverlayCaption(text: report.title),
    );
    marker.setOnTapListener((overlay) {
      onReportTap(report);
    });
    _markers[report.id] = marker;
    await controller.addOverlay(marker);
  }

  Future<void> removeReport({
    required NaverMapController controller,
    required String reportId,
  }) async {
    final marker = _markers.remove(reportId);
    if (marker == null) return;

    await controller.deleteOverlay(
      NOverlayInfo(type: NOverlayType.marker, id: 'report-$reportId'),
    );
  }

  Future<void> clear(NaverMapController controller) async {
    final reportIds = _markers.keys.toList();
    _markers.clear();
    for (final reportId in reportIds) {
      await controller.deleteOverlay(
        NOverlayInfo(type: NOverlayType.marker, id: 'report-$reportId'),
      );
    }
  }

  static Color _markerColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return Colors.red;
      case 'HIGH':
        return Colors.deepOrange;
      case 'MEDIUM':
        return Colors.amber;
      default:
        return Colors.green;
    }
  }
}
