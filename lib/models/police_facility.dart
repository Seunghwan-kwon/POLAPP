import 'package:flutter_naver_map/flutter_naver_map.dart';

class PoliceFacility {
  const PoliceFacility({
    required this.id,
    required this.name,
    required this.position,
  });

  final String id;
  final String name;
  final NLatLng position;
}
