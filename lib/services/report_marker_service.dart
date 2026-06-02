import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../models/report.dart';

class ReportMarkerService {
  static const NOverlayImage _reportIcon = NOverlayImage.fromAssetImage(
    'assets/icons/siren_icon.png',
  );

  final Map<String, NMarker> _markers = {};
  double _currentMarkerSize = _markerSizeForZoom(15);

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
      icon: _reportIcon,
      size: Size.square(_currentMarkerSize),
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

  void updateMarkerSizes(double zoom) {
    final markerSize = _markerSizeForZoom(zoom);
    if (markerSize == _currentMarkerSize) return;

    _currentMarkerSize = markerSize;
    for (final marker in _markers.values) {
      marker.setSize(Size.square(markerSize));
    }
  }

  static double _markerSizeForZoom(double zoom) {
    if (zoom <= 12) return 24;
    if (zoom <= 14) return 32;
    if (zoom <= 16) return 42;
    return 52;
  }
}
