import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../data/police_facilities_list.dart';
import '../models/police_facility.dart';

class PoliceMarkerService {
  final Map<String, NMarker> _policeFacilityMarkers = {};
  Timer? _policeFacilityPulseTimer;

  Future<void> addPoliceFacilityMarkers({
    required BuildContext context,
    required NaverMapController controller,
    required ValueChanged<PoliceFacility> onFacilityTap,
  }) async {
    final policeFacilityIcon = await _buildPoliceFacilityIcon(context);
    _policeFacilityMarkers.clear();

    for (final facility in policeFacilities) {
      final marker = NMarker(
        id: facility.id,
        position: facility.position,
        icon: policeFacilityIcon,
        size: const Size(30, 30),
      );
      marker.setOnTapListener((overlay) {
        pulseFacilityMarker(facility.id);
        onFacilityTap(facility);
      });
      _policeFacilityMarkers[facility.id] = marker;
      await controller.addOverlay(marker);
    }
  }

  Future<NOverlayImage> _buildPoliceFacilityIcon(BuildContext context) {
    return NOverlayImage.fromWidget(
      context: context,
      size: const Size(52, 52),
      widget: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF1D4ED8),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.local_police_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  void pulseFacilityMarker(String facilityId) {
    _policeFacilityPulseTimer?.cancel();

    final activeMarker = _policeFacilityMarkers[facilityId];
    if (activeMarker == null) return;

    var pulseStep = 0;
    activeMarker.setAlpha(1.0);
    activeMarker.setSize(const Size(30, 30));

    _policeFacilityPulseTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (timer) {
        if (pulseStep == 0) {
          activeMarker.setAlpha(0.9);
          activeMarker.setSize(const Size(38, 38));
        } else {
          activeMarker.setAlpha(1.0);
          activeMarker.setSize(const Size(30, 30));
          timer.cancel();
        }
        pulseStep++;
      },
    );
  }

  void dispose() {
    _policeFacilityPulseTimer?.cancel();
  }
}
