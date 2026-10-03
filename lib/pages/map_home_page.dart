import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';

import '../models/officer_profile.dart';
import '../models/police_facility.dart';
import '../models/report.dart';
import '../models/safety_status.dart';
import '../services/mobile_report_service.dart';
import '../services/police_marker_service.dart';
import '../services/report_marker_service.dart';
import '../services/server_config.dart';
import 'ai_feature_page.dart';
import 'map_bottom_panel.dart';
import 'setting_page.dart';

const NLatLng _defaultTarget = NLatLng(37.6194, 127.0598);

class MapHomePage extends StatefulWidget {
  const MapHomePage({super.key});

  @override
  State<MapHomePage> createState() => _MapHomePageState();
}

class RadioMessage {
  final String officerId;
  final String region;
  final String message;
  final DateTime timestamp;

  RadioMessage({
    required this.officerId,
    required this.region,
    required this.message,
    required this.timestamp,
  });

  factory RadioMessage.fromJson(Map<String, dynamic> json) {
    return RadioMessage(
      officerId: json['officerId'],
      region: json['region'] ?? 'UNKNOWN',
      message: json['message'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class _MapHomePageState extends State<MapHomePage> {
  static const NCameraPosition _initialCameraPosition = NCameraPosition(
    target: _defaultTarget,
    zoom: 15,
  );

  bool _isMapLoaded = false;
  bool _isBriefingVisible = false;
  bool _isVoiceRecognitionEnabled = false;
  bool _isRadioDialogOpen = false;
  bool _isSafetyHeatmapVisible = false;
  final List<NOverlayInfo> _safetyHeatmapOverlayInfos = [];
  SafetyStatus _safetyStatus = SafetyStatus.waiting;
  PoliceFacility? _selectedFacility;
  Report? _selectedReport;

  OfficerProfile _officerProfile = const OfficerProfile(
    name: '로딩 중...',
    rank: '',
  );

  NaverMapController? _mapController;
  StreamSubscription<Position>? _positionStream;
  NMarker? _myLocationMarker;

  io.Socket? _socket;
  String _myOfficerId = '';
  String _myRegion = '';
  final Map<String, NMarker> _colleagueMarkers = {};
  final Map<String, Map<String, String>> _colleagueProfiles = {};
  final PoliceMarkerService _policeMarkerService = PoliceMarkerService();
  final MobileReportService _mobileReportService = MobileReportService();
  final ReportMarkerService _reportMarkerService = ReportMarkerService();

  final List<RadioMessage> _radioLogs = [];

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myOfficerId = prefs.getString('officerId') ?? 'UNKNOWN';
      _myRegion = prefs.getString('officerRegion') ?? 'SEOUL_NOWON';
      final String myName = prefs.getString('officerName') ?? '이름 미상';
      final String myRank = prefs.getString('officerRank') ?? '계급 미상';

      _officerProfile = OfficerProfile(name: myName, rank: myRank);
    });

    debugPrint('접속된 사번: $_myOfficerId');

    _startLocationTracking();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _policeMarkerService.dispose();
    _mobileReportService.close();
    super.dispose();
  }

  void _connectWebSocket() {
    const String serverUrl = wsServerUrl;

    _socket = io.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
    });

    _socket?.onConnect((_) {
      debugPrint('WebSocket connected');

      _socket?.emit('join', {'officerId': _myOfficerId});

      if (_myLocationMarker != null) {
        _socket!.emit('sendMyLocation', {
          'officerId': _myOfficerId,
          'latitude': _myLocationMarker!.position.latitude,
          'longitude': _myLocationMarker!.position.longitude,
        });
        debugPrint('[Debug] 초기 위치 1회 강제 전송 완료');
      }
    });

    _socket?.onConnectError(
      (error) => debugPrint('WebSocket connect error: $error'),
    );

    _socket?.on('updateColleagueLocation', (data) {
      final String officerId = data['officerId'].toString();
      final double lat = (data['latitude'] as num).toDouble();
      final double lng = (data['longitude'] as num).toDouble();

      if (!_colleagueProfiles.containsKey(officerId) &&
          data.containsKey('name')) {
        _colleagueProfiles[officerId] = {
          'name': data['name'] ?? '이름 미상',
          'rank': data['rank'] ?? '계급 미상',
          'affiliation': data['affiliation'] ?? '소속 미상',
        };
      }

      _updateColleagueMarker(officerId, NLatLng(lat, lng));
    });

    _socket?.on('receiveRadioMessage', (data) {
      if (!mounted) return;

      final newMessage = RadioMessage.fromJson(data);

      setState(() {
        _radioLogs.insert(0, newMessage);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "[${newMessage.region}] ${newMessage.officerId}: ${newMessage.message}",
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 100, left: 20, right: 20),
        ),
      );
    });

    _socket?.on('removeColleagueLocation', (data) {
      debugPrint('[Debug] 연결 해제 이벤트 수신함: $data');

      if (!mounted) return;

      try {
        final String officerId = data['officerId'].toString();
        _removeColleagueMarker(officerId);
      } catch (e) {
        debugPrint('[Error] 퇴장 데이터 파싱 에러: $e');
      }
    });

    _socket?.on('reportCreated', (data) async {
      final controller = _mapController;
      if (controller == null) return;

      try {
        final report = _mobileReportService.parseReport(data);
        await _reportMarkerService.upsertReport(
          controller: controller,
          report: report,
          onReportTap: _onReportTap,
        );
      } catch (e) {
        debugPrint('[Report] 사건 생성 이벤트 처리 실패: $e');
      }
    });

    _socket?.on('reportClosed', (data) async {
      final controller = _mapController;
      if (controller == null || data is! Map) return;

      final reportId = data['id']?.toString();
      if (reportId == null || reportId.isEmpty) return;

      await _reportMarkerService.removeReport(
        controller: controller,
        reportId: reportId,
      );
      if (_selectedReport?.id == reportId && mounted) {
        setState(() {
          _selectedReport = null;
        });
      }
    });

    _socket?.onDisconnect((_) => debugPrint('WebSocket disconnected'));

    _socket?.connect();
  }

  void _updateColleagueMarker(String officerId, NLatLng latLng) {
    if (_mapController == null || officerId == _myOfficerId) return;

    setState(() {
      if (_colleagueMarkers.containsKey(officerId)) {
        _colleagueMarkers[officerId]!.setPosition(latLng);
      } else {
        final profile = _colleagueProfiles[officerId];
        final name = profile?['name'] ?? officerId;
        final rank = profile?['rank'] ?? '';
        final affiliation = profile?['affiliation'] ?? '';

        final newMarker = NMarker(
          id: officerId,
          position: latLng,
          iconTintColor: Colors.blue,
          caption: NOverlayCaption(text: name),
        );

        newMarker.setOnTapListener((overlay) {
          _showColleagueInfoBottomSheet(
            name: name,
            rank: rank,
            affiliation: affiliation,
          );
        });

        _colleagueMarkers[officerId] = newMarker;
        _mapController!.addOverlay(newMarker);
      }
    });
  }

  void _showColleagueInfoBottomSheet({
    required String name,
    required String rank,
    required String affiliation,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '현장 경찰관 정보',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B3B6F),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE5E7EB),
                  child: Icon(Icons.person, color: Colors.black54),
                ),
                title: Text(
                  '$rank $name',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(affiliation),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B3B6F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '확인',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _removeColleagueMarker(String officerId) {
    if (_mapController == null) return;

    setState(() {
      if (_colleagueMarkers.containsKey(officerId)) {
        final info = NOverlayInfo(type: NOverlayType.marker, id: officerId);
        _mapController!.deleteOverlay(info);

        _colleagueMarkers.remove(officerId);

        debugPrint('[Debug] 동료 마커 삭제 및 화면 갱신 완료: $officerId');
      } else {
        debugPrint('[Debug] 지우려는 마커가 목록에 없습니다: $officerId');
      }
    });
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    final Position? initialPosition = await Geolocator.getLastKnownPosition();
    if (initialPosition != null) {
      _updateMyLocationOnMap(initialPosition, isInitial: true);
    }

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((Position position) {
          _updateMyLocationOnMap(position, isInitial: false);
        });
  }

  void _updateMyLocationOnMap(Position position, {required bool isInitial}) {
    if (_mapController == null) return;

    final latLng = NLatLng(position.latitude, position.longitude);

    if (_myLocationMarker == null) {
      _myLocationMarker = NMarker(id: 'my-location', position: latLng);
      _mapController!.addOverlay(_myLocationMarker!);
    } else {
      _myLocationMarker!.setPosition(latLng);
    }

    final cameraUpdate = NCameraUpdate.withParams(target: latLng);

    cameraUpdate.setAnimation(
      animation: isInitial ? NCameraAnimation.none : NCameraAnimation.easing,
      duration: isInitial ? Duration.zero : const Duration(milliseconds: 300),
    );

    if (_socket != null && _socket!.connected) {
      _socket!.emit('sendMyLocation', {
        'officerId': _myOfficerId,
        'latitude': position.latitude,
        'longitude': position.longitude,
      });
    }

    _mapController!.updateCamera(cameraUpdate);
  }

  void _sendRadioMessage(String text) {
    if (text.trim().isEmpty) return;

    if (_socket != null && _socket!.connected) {
      final messageData = {
        'officerId': _myOfficerId,
        'region': _myRegion,
        'message': text,
        'timestamp': DateTime.now().toIso8601String(),
      };

      _socket!.emit('sendRadioMessage', messageData);
      debugPrint('메시지 전송 완료: $text');
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('서버와 연결되어 있지 않습니다.')));
    }
  }

  void _showRadioDialog() {
    setState(() {
      _isRadioDialogOpen = true;
    });

    final TextEditingController messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.campaign, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                '전체 메시지 전파',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: TextField(
            controller: messageController,
            decoration: const InputDecoration(
              hintText: '전파할 내용을 입력하세요.',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                _sendRadioMessage(messageController.text);
                Navigator.pop(context);
              },
              child: const Text('전파하기', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ).then((_) {
      setState(() {
        _isRadioDialogOpen = false;
      });
    });
  }

  void _zoomIn() {
    _mapController?.updateCamera(NCameraUpdate.zoomIn());
  }

  void _zoomOut() {
    _mapController?.updateCamera(NCameraUpdate.zoomOut());
  }

  void _nextSafetyStatus() {
    setState(() {
      _safetyStatus = _safetyStatus.next;
    });
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SettingPage()));
  }

  void _openAiFeatures() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const AiFeaturePage()));
  }

  void _toggleVoiceRecognition() {
    setState(() {
      _isVoiceRecognitionEnabled = !_isVoiceRecognitionEnabled;
    });
  }

  void _toggleBriefingVisibility() {
    setState(() {
      _isBriefingVisible = !_isBriefingVisible;
    });
  }

  Future<void> _toggleSafetyHeatmap() async {
    if (_isSafetyHeatmapVisible) {
      await _removeSafetyHeatmap();
      if (!mounted) return;
      setState(() {
        _isSafetyHeatmapVisible = false;
      });
      return;
    }

    await _showSafetyHeatmap();
    if (!mounted) return;
    setState(() {
      _isSafetyHeatmapVisible = true;
    });
  }

  Future<void> _showSafetyHeatmap() async {
    final controller = _mapController;
    if (controller == null) return;

    await _removeSafetyHeatmap();

    final raw = await rootBundle.loadString(
      'assets/data/nowon_safety_heatmap.json',
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final features = decoded['features'] as List<dynamic>? ?? const [];
    final overlays = <NAddableOverlay>{};

    for (var featureIndex = 0; featureIndex < features.length; featureIndex++) {
      final feature = features[featureIndex] as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>? ?? const {};
      final properties =
          feature['properties'] as Map<String, dynamic>? ?? const {};
      final color = _parseHeatColor(
        properties['fill_color']?.toString() ?? '#E5E7EB',
      );

      final polygons = _extractPolygonCoordinateSets(geometry);
      for (
        var polygonIndex = 0;
        polygonIndex < polygons.length;
        polygonIndex++
      ) {
        final rings = polygons[polygonIndex];
        if (rings.isEmpty || rings.first.length < 4) continue;

        final overlay = NPolygonOverlay(
          id: 'nowon-safety-$featureIndex-$polygonIndex',
          coords: rings.first,
          holes: rings.length > 1 ? rings.skip(1).toList() : const [],
          color: color.withValues(alpha: 0.30),
          outlineColor: Colors.black.withValues(alpha: 0.42),
          outlineWidth: 1.4,
        );
        overlays.add(overlay);
        _safetyHeatmapOverlayInfos.add(overlay.info);
      }
    }

    if (overlays.isNotEmpty) {
      await controller.addOverlayAll(overlays);
    }
  }

  Future<void> _removeSafetyHeatmap() async {
    final controller = _mapController;
    if (controller == null || _safetyHeatmapOverlayInfos.isEmpty) return;

    final overlayInfos = List<NOverlayInfo>.from(_safetyHeatmapOverlayInfos);
    _safetyHeatmapOverlayInfos.clear();
    for (final info in overlayInfos) {
      await controller.deleteOverlay(info);
    }
  }

  List<List<List<NLatLng>>> _extractPolygonCoordinateSets(
    Map<String, dynamic> geometry,
  ) {
    final type = geometry['type']?.toString();
    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return const [];

    if (type == 'Polygon') {
      return [_convertPolygonRings(coordinates)];
    }
    if (type == 'MultiPolygon') {
      return coordinates
          .whereType<List<dynamic>>()
          .map(_convertPolygonRings)
          .where((rings) => rings.isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<List<NLatLng>> _convertPolygonRings(List<dynamic> polygon) {
    return polygon
        .whereType<List<dynamic>>()
        .map(_convertRing)
        .where((ring) => ring.length >= 4)
        .toList();
  }

  List<NLatLng> _convertRing(List<dynamic> ring) {
    return ring
        .whereType<List<dynamic>>()
        .where((point) => point.length >= 2)
        .map(
          (point) => NLatLng(
            (point[1] as num).toDouble(),
            (point[0] as num).toDouble(),
          ),
        )
        .toList();
  }

  Color _parseHeatColor(String hex) {
    final value = hex.replaceFirst('#', '');
    if (value.length != 6) {
      return const Color(0xFFE5E7EB);
    }
    return Color(int.parse('FF$value', radix: 16));
  }

  Future<void> _onMapReady(NaverMapController controller) async {
    await _policeMarkerService.addPoliceFacilityMarkers(
      context: context,
      controller: controller,
      onFacilityTap: _onPoliceFacilityTap,
    );
    await _loadReportMarkers(controller);
    if (_isSafetyHeatmapVisible) {
      await _showSafetyHeatmap();
    }
  }

  Future<void> _loadReportMarkers(NaverMapController controller) async {
    try {
      final reports = await _mobileReportService.fetchReports();
      await _reportMarkerService.replaceReports(
        controller: controller,
        reports: reports,
        onReportTap: _onReportTap,
      );
    } catch (e) {
      debugPrint('[Report] 사건 목록 조회 실패: $e');
    }
  }

  Future<void> _updateReportMarkerSizes() async {
    final controller = _mapController;
    if (controller == null) return;

    final cameraPosition = await controller.getCameraPosition();
    if (!mounted || controller != _mapController) return;
    _reportMarkerService.updateMarkerSizes(cameraPosition.zoom);
  }

  void _onPoliceFacilityTap(PoliceFacility facility) {
    setState(() {
      _selectedFacility = facility;
      _selectedReport = null;
      _isBriefingVisible = true;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${facility.name} 선택됨'),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  void _onReportTap(Report report) {
    setState(() {
      _selectedReport = report;
      _selectedFacility = null;
      _isBriefingVisible = true;
    });
  }

  Future<void> _onNavigateToReport(Report report) async {
    if (!_isValidNavigationTarget(report)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('사건 위치 좌표가 올바르지 않습니다.')));
      return;
    }

    final navigationUri = Uri(
      scheme: 'nmap',
      host: 'navigation',
      queryParameters: {
        'dlat': report.lat.toString(),
        'dlng': report.lng.toString(),
        'dname': report.title,
        'appname': 'com.polapp.pol_app',
      },
    );

    debugPrint('[Navigation] 네이버 지도 앱 호출: $navigationUri');

    try {
      final launched = await launchUrl(
        navigationUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched || !mounted) return;
    } catch (error) {
      debugPrint('[Navigation] 네이버 지도 앱 실행 실패: $error');
      if (!mounted) return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('네이버 지도 앱을 실행할 수 없습니다. 설치 여부를 확인해 주세요.')),
      );
  }

  bool _isValidNavigationTarget(Report report) {
    return report.lat >= 31.43 &&
        report.lat <= 44.35 &&
        report.lng >= 122.37 &&
        report.lng <= 132.00;
  }

  @override
  Widget build(BuildContext context) {
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: NaverMap(
              options: const NaverMapViewOptions(
                mapType: NMapType.navi,
                nightModeEnable: true,
                initialCameraPosition: _initialCameraPosition,
                locationButtonEnable: true,
              ),
              onMapReady: (controller) {
                _mapController = controller;
                _onMapReady(controller);
              },
              onMapLoaded: () {
                if (!mounted) return;
                setState(() {
                  _isMapLoaded = true;
                });
              },
              onCameraIdle: _updateReportMarkerSizes,
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: GestureDetector(
                        onTap: _isMapLoaded ? _nextSafetyStatus : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (_isMapLoaded
                                        ? _safetyStatus.color
                                        : Colors.black)
                                    .withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isMapLoaded
                                    ? _safetyStatus.icon
                                    : Icons.map_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _isMapLoaded
                                      ? _safetyStatus.label
                                      : '지도를 불러오는 중...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: EdgeInsets.only(top: isLandscape ? 150 : 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'btn_settings',
                          onPressed: _openSettings,
                          backgroundColor: Colors.white,
                          child: const Icon(
                            Icons.settings,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'btn_voice_toggle',
                          onPressed: _toggleVoiceRecognition,
                          backgroundColor: _isVoiceRecognitionEnabled
                              ? Colors.redAccent
                              : Colors.white,
                          child: Icon(
                            _isVoiceRecognitionEnabled
                                ? Icons.mic
                                : Icons.mic_off,
                            color: _isVoiceRecognitionEnabled
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'btn_radio',
                          onPressed: _showRadioDialog,
                          backgroundColor: _isRadioDialogOpen
                              ? Colors.blueAccent
                              : Colors.white,
                          child: Icon(
                            Icons.campaign,
                            color: _isRadioDialogOpen
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'btn_ai_features',
                          onPressed: _openAiFeatures,
                          backgroundColor: Colors.white,
                          child: const Icon(
                            Icons.smart_toy_outlined,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'btn_safety_heatmap',
                          onPressed: _isMapLoaded ? _toggleSafetyHeatmap : null,
                          backgroundColor: _isSafetyHeatmapVisible
                              ? const Color(0xFFDC2626)
                              : Colors.white,
                          tooltip: '치안 히트맵',
                          child: Icon(
                            Icons.local_fire_department_outlined,
                            color: _isSafetyHeatmapVisible
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 72),
              child: Align(
                alignment: Alignment.topLeft,
                child: FloatingActionButton.small(
                  heroTag: 'btn_briefing_toggle',
                  onPressed: _toggleBriefingVisibility,
                  backgroundColor: _isBriefingVisible
                      ? const Color(0xFF2563EB)
                      : Colors.white,
                  child: Icon(
                    _isBriefingVisible ? Icons.layers : Icons.layers_clear,
                    color: _isBriefingVisible ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 220,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'btn_zoom_in',
                  onPressed: _zoomIn,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.add, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'btn_zoom_out',
                  onPressed: _zoomOut,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.remove, color: Colors.black87),
                ),
              ],
            ),
          ),

          if (_isBriefingVisible)
            DraggableScrollableSheet(
              initialChildSize: 0.18,
              minChildSize: 0.12,
              maxChildSize: 0.78,
              snap: true,
              snapSizes: const [0.18, 0.42, 0.78],
              builder: (context, scrollController) {
                return MapBottomPanel(
                  scrollController: scrollController,
                  officerProfile: _officerProfile,
                  status: _safetyStatus,
                  selectedFacility: _selectedFacility,
                  selectedReport: _selectedReport,
                  onNavigateToReport: _onNavigateToReport,
                );
              },
            ),
        ],
      ),
    );
  }
}
