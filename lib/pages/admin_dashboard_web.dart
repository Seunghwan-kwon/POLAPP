import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:web/web.dart' as web;
import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;
import 'admin_dashboard_list.dart';
import '../models/report.dart';
import '../services/report_api_service.dart';
import '../services/admin_threat_alert_service.dart';
import '../services/admin_camera_stream_service.dart';
import '../services/server_config.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final String _viewId = 'naver-map-web-view';
  io.Socket? _socket;
  final Map<String, js.JSObject> _officerMarkers = {};
  final Set<String> _connectedRegions = {};
  final Map<String, String> _officerRegions = {};
  bool _isReportListOpen = false;
  final Map<String, js.JSObject> _reportMarkers = {};
  final Map<String, Report> _reports = {};
  final ReportApiService _reportApi = ReportApiService();
  final AdminThreatAlertService _threatAlertApi = AdminThreatAlertService();
  final AdminCameraStreamService _cameraStreamApi = AdminCameraStreamService();
  final List<Map<String, dynamic>> _threatAlerts = [];
  List<AdminCameraStream> _cameraStreams = const [];
  Timer? _cameraRefreshTimer;
  Uint8List? _cameraFrame;
  String? _selectedCameraOfficerId;
  String? _cameraStreamError;
  bool _isCameraPanelOpen = false;
  bool _isCameraRefreshBusy = false;
  bool _isThreatHistoryOpen = false;
  String _threatOfficerFilter = 'ALL';
  String _threatCategoryFilter = 'ALL';
  String _threatTimeFilter = 'ALL';
  js.JSObject? _threatFocusMarker;
  String? _selectedReportId;
  final List<js.JSAny> _mapEventHandlers = [];
  bool _isCreateReportDialogOpen = false;
  bool _isWaitingForReportLocation = false;
  String _myOfficerId = '';

  DateTime? _lastMapDragEndedAt;
  static const Duration _dialogClickIgnoreDuration = Duration(
    milliseconds: 500,
  );

  bool _isMapDragging = false;
  DateTime? _ignoreMapClicksUntil;
  static const Duration _mapDragClickIgnoreDuration = Duration(
    milliseconds: 250,
  );

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    unawaited(_loadThreatAlerts());
    unawaited(_refreshCameraStreams());
    _cameraRefreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshCameraStreams()),
    );

    if (kIsWeb) {
      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        final web.HTMLDivElement div = web.HTMLDivElement()
          ..id = 'map'
          ..style.width = '100%'
          ..style.height = '100%';

        _injectNaverMapScript(div);

        return div;
      });
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myOfficerId = prefs.getString('officerId') ?? 'UNKNOWN_ADMIN';
    });
  }

  Future<void> _loadThreatAlerts() async {
    try {
      final alerts = await _threatAlertApi.fetch(limit: 200);
      if (!mounted) return;
      setState(() {
        _threatAlerts
          ..clear()
          ..addAll(alerts);
      });
    } catch (error) {
      debugPrint('[Threat Alert] 목록 조회 실패: $error');
    }
  }

  Future<void> _refreshCameraStreams() async {
    if (_isCameraRefreshBusy) return;
    _isCameraRefreshBusy = true;
    try {
      final streams = await _cameraStreamApi.fetchStreams();
      var selectedOfficerId = _selectedCameraOfficerId;
      if (selectedOfficerId == null ||
          !streams.any((stream) => stream.officerId == selectedOfficerId)) {
        selectedOfficerId = streams.isEmpty ? null : streams.first.officerId;
      }

      Uint8List? frame = _cameraFrame;
      if (_isCameraPanelOpen && selectedOfficerId != null) {
        frame = await _cameraStreamApi.fetchFrame(selectedOfficerId);
      } else if (selectedOfficerId == null) {
        frame = null;
      }
      if (!mounted) return;
      setState(() {
        _cameraStreams = streams;
        _selectedCameraOfficerId = selectedOfficerId;
        _cameraFrame = frame;
        _cameraStreamError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraStreamError = error.toString();
      });
    } finally {
      _isCameraRefreshBusy = false;
    }
  }

  void _toggleCameraPanel() {
    setState(() {
      _isCameraPanelOpen = !_isCameraPanelOpen;
      if (_isCameraPanelOpen) {
        _selectedReportId = null;
        _isReportListOpen = false;
        _isThreatHistoryOpen = false;
      }
    });
    if (_isCameraPanelOpen) unawaited(_refreshCameraStreams());
  }

  void _injectNaverMapScript(web.HTMLDivElement div) {
    final String clientId = const String.fromEnvironment(
      'NAVER_MAP_WEB_CLIENT_ID',
    );

    if (js.globalContext['naver'] != null) {
      _waitForMapDivAndInitialize(div);
      return;
    }

    final script =
        web.document.createElement('script') as web.HTMLScriptElement;

    script.src =
        'https://openapi.map.naver.com/openapi/v3/maps.js?ncpKeyId=$clientId';
    script.type = 'text/javascript';
    script.async = true;

    script.onload = () {
      if (mounted) {
        _waitForMapDivAndInitialize(div);
      }
    }.toJS;

    web.document.head?.appendChild(script);
  }

  void _waitForMapDivAndInitialize(web.HTMLDivElement div) {
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final element = web.document.getElementById('map');

      if (element != null) {
        timer.cancel();
        _initializeNaverMap(div);
        unawaited(_connectWebSocket());
      }
    });
  }

  void _initializeNaverMap(web.HTMLDivElement div) {
    final naver = js.globalContext['naver'] as js.JSObject?;

    if (naver != null) {
      final maps = naver['maps'] as js.JSObject;

      final center = maps.callMethod(
        'LatLng'.toJS,
        37.6194.toJS,
        127.0598.toJS,
      );

      final mapOptions = {'center': center, 'zoom': 13.toJS}.jsify();

      final mapConstructor = maps['Map'] as js.JSFunction;
      final mapInstance = mapConstructor.callAsConstructor(
        div as js.JSAny,
        mapOptions as js.JSAny,
      );

      js.globalContext['adminMap'] = mapInstance;

      _attachMapClickListener(mapInstance as js.JSObject);
      _loadReportsFromServer();
    } else {
      debugPrint('⚠️ [Error] 네이버 지도 스크립트 로드 실패');
    }
  }

  void _attachMapClickListener(js.JSObject mapInstance) {
    final naver = js.globalContext['naver'] as js.JSObject?;

    if (naver == null) {
      debugPrint('⚠️ [Error] 네이버 지도 객체가 없어 클릭 이벤트를 등록할 수 없습니다.');
      return;
    }

    final maps = naver['maps'] as js.JSObject;
    final event = maps['Event'] as js.JSObject;
    debugPrint('[Debug] 지도 이벤트 리스너 등록 시작');

    final dragStartHandler = (() {
      _isMapDragging = true;
    }).toJS;

    final dragEndHandler = (() {
      _lastMapDragEndedAt = DateTime.now();

      Future.delayed(_mapDragClickIgnoreDuration, () {
        if (!mounted) return;
        _isMapDragging = false;
      });
    }).toJS;

    final clickHandler = ((js.JSObject e) {
      debugPrint('[Debug] 지도 click 이벤트 수신');

      if (_shouldIgnoreMapClick()) {
        debugPrint('[Debug] 지도 click 이벤트 무시');
        return;
      }

      final coord = e['coord'] as js.JSObject;
      final lat = (coord.callMethod('lat'.toJS) as js.JSNumber).toDartDouble;
      final lng = (coord.callMethod('lng'.toJS) as js.JSNumber).toDartDouble;

      debugPrint('[Debug] 지도 클릭 좌표: ($lat, $lng)');
      _handleMapClick(lat, lng);
    }).toJS;

    final zoomChangedHandler = (() {
      _updateReportMarkerSizes(maps, mapInstance);
    }).toJS;

    _mapEventHandlers.addAll([
      dragStartHandler,
      dragEndHandler,
      clickHandler,
      zoomChangedHandler,
    ]);

    event.callMethod(
      'addListener'.toJS,
      mapInstance,
      'dragstart'.toJS,
      dragStartHandler,
    );

    event.callMethod(
      'addListener'.toJS,
      mapInstance,
      'dragend'.toJS,
      dragEndHandler,
    );

    event.callMethod(
      'addListener'.toJS,
      mapInstance,
      'click'.toJS,
      clickHandler,
    );

    event.callMethod(
      'addListener'.toJS,
      mapInstance,
      'zoom_changed'.toJS,
      zoomChangedHandler,
    );

    debugPrint('[Debug] 지도 이벤트 리스너 등록 완료');
  }

  bool _shouldIgnoreMapClick() {
    final ignoreUntil = _ignoreMapClicksUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
      return true;
    }

    if (_isMapDragging) return true;

    final lastDragEndedAt = _lastMapDragEndedAt;
    if (lastDragEndedAt == null) return false;

    return DateTime.now().difference(lastDragEndedAt) <
        _mapDragClickIgnoreDuration;
  }

  Future<void> _handleMapClick(double lat, double lng) async {
    if (!_isWaitingForReportLocation || _isCreateReportDialogOpen) return;

    _isCreateReportDialogOpen = true;
    try {
      await _showCreateReportDialog(lat, lng);
    } finally {
      _isCreateReportDialogOpen = false;
    }
  }

  Future<void> _connectWebSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final officerId = prefs.getString('officerId')?.trim() ?? '';
    if (officerId.isEmpty) {
      debugPrint('[Debug] 로그인한 관리자 정보가 없어 웹소켓 연결을 생략함');
      return;
    }
    const String serverUrl = wsServerUrl;
    debugPrint('[Debug] 서버 연결 시도 주소: $serverUrl');

    _socket = io.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    _socket?.onConnect((_) {
      debugPrint('[Debug] 웹소켓 연결 성공! (세션 ID: ${_socket?.id})');

      _socket?.emit('join', {'officerId': officerId});
      debugPrint('[Debug] Join 이벤트 전송 완료 (Role: ADMIN)');
    });

    _socket?.onConnectError((error) {
      debugPrint('[Debug] 연결 에러 발생: $error');
    });

    _socket?.on('updateColleagueLocation', (data) {
      debugPrint('[Debug] 위치 데이터 수신함: $data');

      try {
        final String officerId = data['officerId'].toString();
        final double lat = (data['latitude'] as num).toDouble();
        final double lng = (data['longitude'] as num).toDouble();
        final String? regionCode = data['region']?.toString();

        String? regionName;
        if (regionCode == 'SEOUL_NOWON') {
          regionName = '노원구';
        } else if (regionCode == 'SEOUL_DOBONG') {
          regionName = '도봉구';
        } else if (regionCode != null) {
          regionName = regionCode;
        }

        _updateOfficerMarkerJS(officerId, lat, lng);

        setState(() {
          if (regionName != null) {
            _officerRegions[officerId] = regionName;
            _connectedRegions.add(regionName);
          }
        });
      } catch (e) {
        debugPrint('[Debug] 데이터 파싱 에러: $e');
      }
    });

    _socket?.on('removeColleagueLocation', (data) {
      debugPrint('[Debug] 연결 해제 데이터 수신함: $data');
      try {
        final String officerId = data['officerId'].toString();

        _removeOfficerMarkerJS(officerId);
      } catch (e) {
        debugPrint('[Debug] 연결 해제 처리 에러: $e');
      }
    });

    _socket?.on('reportCreated', (data) {
      debugPrint('[Debug] 사건 생성 이벤트 수신함: $data');
      try {
        final report = Report.fromJson(Map<String, dynamic>.from(data as Map));
        _upsertReport(report);
      } catch (e) {
        debugPrint('[Debug] 사건 생성 이벤트 처리 에러: $e');
      }
    });

    _socket?.on('reportClosed', (data) {
      debugPrint('[Debug] 사건 종료 이벤트 수신함: $data');
      try {
        final payload = Map<String, dynamic>.from(data as Map);
        final reportId = payload['id'].toString();
        _markReportClosed(
          reportId,
          closedAt: DateTime.tryParse(payload['closedAt']?.toString() ?? ''),
          closedBy: payload['closedBy'] is num
              ? (payload['closedBy'] as num).toInt()
              : null,
        );
      } catch (e) {
        debugPrint('[Debug] 사건 종료 이벤트 처리 에러: $e');
      }
    });

    _socket?.on('threatDetected', (data) {
      if (!mounted || data is! Map) return;
      final alert = Map<String, dynamic>.from(data);
      final eventId = alert['eventId']?.toString();
      setState(() {
        if (eventId != null) {
          _threatAlerts.removeWhere(
            (item) => item['eventId']?.toString() == eventId,
          );
        }
        _threatAlerts.insert(0, alert);
        if (_threatAlerts.length > 50) _threatAlerts.removeLast();
      });
      final label = alert['alertLabel']?.toString() ?? '위협';
      final level = _threatLevel(alert);
      if (level < 3) return;

      _focusThreatAlert(alert);
      final severityColor = _threatColor(level);
      final officer = _threatOfficer(alert);
      final region = _localizedRegion(alert['region']);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF111827),
          duration: const Duration(seconds: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          content: Row(
            children: [
              Container(width: 4, height: 54, color: severityColor),
              const SizedBox(width: 14),
              Icon(Icons.warning_amber_rounded, color: severityColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_threatSeverity(level)} 위험 알림 · $label',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$officer${region.isEmpty ? '' : ' · $region'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFD1D5DB),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: '확인',
            textColor: severityColor,
            onPressed: () => _focusThreatAlert(alert),
          ),
        ),
      );
    });

    _socket?.on('cameraStreamUpdated', (_) {
      unawaited(_refreshCameraStreams());
    });
    _socket?.on('cameraStreamStopped', (_) {
      unawaited(_refreshCameraStreams());
    });

    _socket?.connect();
  }

  void _updateOfficerMarkerJS(String officerId, double lat, double lng) {
    final naver = js.globalContext['naver'] as js.JSObject?;
    final adminMap = js.globalContext['adminMap'] as js.JSObject?;

    if (naver == null || adminMap == null) {
      debugPrint('[Error] 지도 객체가 초기화되지 않았습니다.');
      return;
    }

    final maps = naver['maps'] as js.JSObject;

    final position = maps.callMethod('LatLng'.toJS, lat.toJS, lng.toJS);

    if (_officerMarkers.containsKey(officerId)) {
      debugPrint('[Debug] 기존 마커 이동: $officerId ($lat, $lng)');
      final existingMarker = _officerMarkers[officerId]!;

      existingMarker.callMethod('setPosition'.toJS, position);
    } else {
      debugPrint('[Debug] 새 마커 생성: $officerId ($lat, $lng)');

      final markerOptions = {
        'position': position,
        'map': adminMap,
        'title': officerId,
      }.jsify();

      final markerConstructor = maps['Marker'] as js.JSFunction;
      final newMarker = markerConstructor.callAsConstructor(
        markerOptions as js.JSAny,
      );

      _officerMarkers[officerId] = newMarker as js.JSObject;

      setState(() {});
    }
  }

  double? _coordinate(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  void _clearThreatFocusMarker() {
    _threatFocusMarker?.callMethod('setMap'.toJS, null);
    _threatFocusMarker = null;
  }

  void _focusThreatAlert(Map<String, dynamic> alert) {
    final latitude = _coordinate(alert['latitude']);
    final longitude = _coordinate(alert['longitude']);
    if (latitude == null || longitude == null) return;

    final naver = js.globalContext['naver'] as js.JSObject?;
    final adminMap = js.globalContext['adminMap'] as js.JSObject?;
    if (naver == null || adminMap == null) return;

    final maps = naver['maps'] as js.JSObject;
    final position = maps.callMethod(
      'LatLng'.toJS,
      latitude.toJS,
      longitude.toJS,
    );
    adminMap.callMethod('setZoom'.toJS, 17.toJS);
    adminMap.callMethod('panTo'.toJS, position);

    _clearThreatFocusMarker();
    final anchor = maps.callMethod('Point'.toJS, 20.toJS, 20.toJS);
    final markerOptions = {
      'position': position,
      'map': adminMap,
      'zIndex': 10000,
      'title': '위험 상황 발생 위치',
      'icon': {
        'content':
            '<div style="width:40px;height:40px;border-radius:50%;background:rgba(220,38,38,.18);border:3px solid #dc2626;box-shadow:0 0 0 8px rgba(220,38,38,.14),0 4px 12px rgba(127,29,29,.38);display:flex;align-items:center;justify-content:center"><div style="width:12px;height:12px;border-radius:50%;background:#b91c1c;border:2px solid white"></div></div>',
        'anchor': anchor,
      },
    }.jsify();
    final markerConstructor = maps['Marker'] as js.JSFunction;
    _threatFocusMarker =
        markerConstructor.callAsConstructor(markerOptions as js.JSAny)
            as js.JSObject;
  }

  Future<void> _loadReportsFromServer() async {
    try {
      final reports = await _reportApi.fetchReports(status: 'ALL');
      if (!mounted) return;

      _clearReportMarkers();
      setState(() {
        _reports
          ..clear()
          ..addEntries(reports.map((report) => MapEntry(report.id, report)));
        _selectedReportId =
            _selectedReportId != null && _reports.containsKey(_selectedReportId)
            ? _selectedReportId
            : null;
      });

      for (final report in reports) {
        if (report.status == ReportStatus.open) {
          _createReportMarkerJS(report);
        }
      }
    } catch (e) {
      debugPrint('[Error] 사건 목록 조회 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('사건 목록을 불러오지 못했습니다. $e')));
    }
  }

  void _upsertReport(Report report, {bool select = false}) {
    setState(() {
      _reports[report.id] = report;
      if (select) {
        _selectedReportId = report.id;
        _isReportListOpen = false;
        _isThreatHistoryOpen = false;
        _isCameraPanelOpen = false;
      }
    });

    if (report.status == ReportStatus.open) {
      _createReportMarkerJS(report);
    } else {
      _removeReportMarkerJS(report.id);
    }
  }

  void _markReportClosed(String reportId, {DateTime? closedAt, int? closedBy}) {
    final report = _reports[reportId];
    if (report == null) return;

    _removeReportMarkerJS(reportId);
    setState(() {
      _reports[reportId] = report.copyWith(
        status: ReportStatus.closed,
        closedAt: closedAt ?? DateTime.now(),
        closedBy: closedBy,
      );
      _selectedReportId = reportId;
      _isThreatHistoryOpen = false;
      _isCameraPanelOpen = false;
    });
  }

  void _clearReportMarkers() {
    for (final marker in _reportMarkers.values) {
      marker.callMethod('setMap'.toJS, null);
    }
    _reportMarkers.clear();
  }

  void _removeReportMarkerJS(String reportId) {
    final marker = _reportMarkers.remove(reportId);
    if (marker == null) return;
    marker.callMethod('setMap'.toJS, null);
  }

  js.JSAny _createReportMarkerIcon(js.JSObject maps, js.JSObject adminMap) {
    final zoom =
        (adminMap.callMethod('getZoom'.toJS) as js.JSNumber).toDartDouble;
    final size = _reportMarkerSizeForZoom(zoom);
    final markerSize = maps.callMethod('Size'.toJS, size.toJS, size.toJS);
    final markerAnchor = maps.callMethod(
      'Point'.toJS,
      (size / 2).toJS,
      size.toJS,
    );

    return {
          'url': 'assets/assets/icons/siren_icon.png',
          'scaledSize': markerSize,
          'anchor': markerAnchor,
        }.jsify()
        as js.JSAny;
  }

  double _reportMarkerSizeForZoom(double zoom) {
    if (zoom <= 12) return 20;
    if (zoom <= 14) return 26;
    if (zoom <= 16) return 32;
    return 40;
  }

  void _updateReportMarkerSizes(js.JSObject maps, js.JSObject adminMap) {
    final markerIcon = _createReportMarkerIcon(maps, adminMap);

    for (final marker in _reportMarkers.values) {
      marker.callMethod('setIcon'.toJS, markerIcon);
    }
  }

  void _createReportMarkerJS(Report report) {
    final naver = js.globalContext['naver'] as js.JSObject?;
    final adminMap = js.globalContext['adminMap'] as js.JSObject?;

    if (naver == null || adminMap == null) {
      debugPrint('[Error] 지도 객체가 초기화되지 않아 사건 마커를 생성할 수 없습니다.');
      return;
    }

    final maps = naver['maps'] as js.JSObject;
    final event = maps['Event'] as js.JSObject;
    final position = maps.callMethod(
      'LatLng'.toJS,
      report.lat.toJS,
      report.lng.toJS,
    );

    _removeReportMarkerJS(report.id);

    final markerOptions = {
      'position': position,
      'map': adminMap,
      'title': report.title,
      'icon': _createReportMarkerIcon(maps, adminMap),
    }.jsify();

    final markerConstructor = maps['Marker'] as js.JSFunction;
    final newMarker = markerConstructor.callAsConstructor(
      markerOptions as js.JSAny,
    );
    (newMarker as js.JSObject).callMethod('setPosition'.toJS, position);

    final markerClickHandler = (() {
      if (!mounted) return;
      setState(() {
        _selectedReportId = report.id;
        _isReportListOpen = false;
        _isThreatHistoryOpen = false;
        _isCameraPanelOpen = false;
      });
    }).toJS;

    _mapEventHandlers.add(markerClickHandler);
    event.callMethod(
      'addListener'.toJS,
      newMarker,
      'click'.toJS,
      markerClickHandler,
    );

    setState(() {
      _reportMarkers[report.id] = newMarker;
    });

    debugPrint(
      '[Debug] 사건 마커 생성 완료: ${report.id} (${report.lat}, ${report.lng}, ${report.severity})',
    );
  }

  void _removeOfficerMarkerJS(String officerId) {
    if (_officerMarkers.containsKey(officerId)) {
      final existingMarker = _officerMarkers[officerId]!;

      existingMarker.callMethod('setMap'.toJS, null);

      setState(() {
        _officerMarkers.remove(officerId);
        _officerRegions.remove(officerId);

        _connectedRegions.clear();
        _connectedRegions.addAll(_officerRegions.values);
      });

      debugPrint('[Debug] 마커 제거 및 실시간 채널 현황 갱신 완료: $officerId');
    }
  }

  Future<void> _confirmCloseReport(String reportId) async {
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('사건 종료'),
          content: const Text('이 사건을 종료하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text('종료'),
            ),
          ],
        );
      },
    );

    if (shouldClose == true) {
      await _closeReport(reportId);
    }
  }

  Future<void> _closeReport(String reportId) async {
    final report = _reports[reportId];

    if (report == null || report.status == ReportStatus.closed) {
      return;
    }

    try {
      await _reportApi.closeReport(reportId);
      if (!mounted) return;

      _markReportClosed(reportId);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('사건을 종료했습니다.')));
    } catch (e) {
      debugPrint('[Error] 사건 종료 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('사건 종료에 실패했습니다. $e')));
    }
  }

  String _severityLabel(String severity) {
    switch (severity) {
      case 'URGENT':
        return '코드0 (긴급)';
      case 'HIGH':
        return '코드1';
      case 'MEDIUM':
        return '코드2';
      case 'LOW':
      default:
        return '코드3 (비긴급)';
    }
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

  Widget _buildReportDetailPanel(double width) {
    final selectedReportId = _selectedReportId;
    final report = selectedReportId == null ? null : _reports[selectedReportId];

    if (report == null) {
      return const SizedBox.shrink();
    }

    final severityColor = _severityColor(report.severity);
    final isClosed = report.status == ReportStatus.closed;

    return Material(
      elevation: 16,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF1B3B6F),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.crisis_alert, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '사건 상세',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _selectedReportId = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: severityColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: severityColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            _severityLabel(report.severity),
                            style: TextStyle(
                              color: severityColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isClosed
                                ? Colors.grey.withValues(alpha: 0.14)
                                : Colors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isClosed
                                  ? Colors.grey.withValues(alpha: 0.45)
                                  : Colors.green.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            isClosed ? '종결' : '접수',
                            style: TextStyle(
                              color: isClosed
                                  ? Colors.grey.shade700
                                  : Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            report.title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '상세 내용',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      report.description,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 16),
                    _buildReportInfoRow(
                      icon: Icons.place,
                      label: '위치',
                      value:
                          '${report.lat.toStringAsFixed(6)}, ${report.lng.toStringAsFixed(6)}',
                    ),
                    const SizedBox(height: 12),
                    _buildReportInfoRow(
                      icon: Icons.access_time,
                      label: '접수 시간',
                      value: _formatReportTime(report.createdAt),
                    ),
                    const SizedBox(height: 12),
                    if (report.closedAt != null) ...[
                      const SizedBox(height: 12),
                      _buildReportInfoRow(
                        icon: Icons.task_alt,
                        label: '종료 시간',
                        value: _formatReportTime(report.closedAt!),
                      ),
                    ],
                    _buildReportInfoRow(
                      icon: Icons.tag,
                      label: '사건 ID',
                      value: report.id,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedReportId = null;
                        });
                      },
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('패널 닫기'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isClosed
                          ? null
                          : () => _confirmCloseReport(report.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.task_alt),
                      label: const Text('사건 종료'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF4B5563)),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF4B5563),
            ),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(color: Color(0xFF111827))),
        ),
      ],
    );
  }

  String _formatReportTime(DateTime time) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${time.year}-${twoDigits(time.month)}-${twoDigits(time.day)} '
        '${twoDigits(time.hour)}:${twoDigits(time.minute)}';
  }

  void _showRadioDialog() {
    final TextEditingController messageController = TextEditingController();
    String selectedRegion = 'ALL';

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.campaign, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text(
                    '전체 메시지 전파',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '수신 관할 지역 선택',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  DropdownButtonFormField<String>(
                    initialValue: selectedRegion,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),

                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('서울 전 지역')),
                      DropdownMenuItem(
                        value: 'SEOUL_NOWON',
                        child: Text('서울 노원구'),
                      ),
                      DropdownMenuItem(
                        value: 'SEOUL_DOBONG',
                        child: Text('서울 도봉구'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          selectedRegion = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '메시지 내용 입력',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: messageController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '현장 경찰관들에게 전파할 지시 사항을 입력하세요.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('취소', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1B3B6F),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final String text = messageController.text.trim();
                    if (text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('전파할 지시 사항을 입력해 주세요.')),
                      );
                      return;
                    }

                    final String currentTimestamp = DateTime.now()
                        .toIso8601String();

                    if (_socket != null && _socket!.connected) {
                      _socket!.emit('sendRadioMessage', {
                        'officerId': _myOfficerId,
                        'region': selectedRegion,
                        'message': text,
                        'timestamp': currentTimestamp,
                      });

                      Navigator.of(context).pop();

                      final String resultText = selectedRegion == 'ALL'
                          ? '전체 관할 지역으로'
                          : '[$selectedRegion] 지역으로';

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$resultText 메시지가 전파되었습니다.')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('서버와 소켓 연결이 끊어져 있습니다.')),
                      );
                    }
                  },
                  child: const Text('전송'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateReportDialog(double lat, double lng) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedSeverity = 'LOW';
    bool isSubmitted = false;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 48,
                vertical: 32,
              ),
              title: const Text('사건 접수'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: '사건',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: descriptionController,
                        minLines: 6,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: '상세 사건 내용',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedSeverity,
                        decoration: const InputDecoration(
                          labelText: '사건코드',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'LOW',
                            child: Text('코드3 (비긴급)'),
                          ),
                          DropdownMenuItem(value: 'MEDIUM', child: Text('코드2')),
                          DropdownMenuItem(value: 'HIGH', child: Text('코드1')),
                          DropdownMenuItem(
                            value: 'URGENT',
                            child: Text('코드0 (긴급)'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            selectedSeverity = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '위치: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final title = titleController.text.trim();
                          final description = descriptionController.text.trim();

                          if (title.isEmpty || description.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text('사건 제목과 내용을 입력해 주세요.'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            final report = await _reportApi.createReport(
                              title: title,
                              description: description,
                              severity: selectedSeverity,
                              latitude: lat,
                              longitude: lng,
                            );

                            if (!mounted || !dialogContext.mounted) return;
                            _upsertReport(report, select: true);

                            isSubmitted = true;
                            setState(() {
                              _isWaitingForReportLocation = false;
                            });

                            Navigator.of(dialogContext).pop();
                          } catch (e) {
                            debugPrint('[Error] 사건 생성 실패: $e');
                            if (!mounted || !dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text('사건 접수에 실패했습니다. $e')),
                            );
                            setDialogState(() {
                              isSaving = false;
                            });
                          }
                        },
                  child: Text(isSaving ? '접수 중...' : '접수'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    descriptionController.dispose();

    if (mounted && !isSubmitted && _isWaitingForReportLocation) {
      setState(() {
        _isWaitingForReportLocation = false;
      });
    }
  }

  void _toggleReportList() {
    setState(() {
      _isReportListOpen = !_isReportListOpen;
      if (_isReportListOpen) {
        _selectedReportId = null;
        _isThreatHistoryOpen = false;
        _isCameraPanelOpen = false;
      }
    });
  }

  void _toggleThreatHistory() {
    setState(() {
      _isThreatHistoryOpen = !_isThreatHistoryOpen;
      if (_isThreatHistoryOpen) {
        _selectedReportId = null;
        _isReportListOpen = false;
        _isCameraPanelOpen = false;
      }
    });
  }

  Future<bool?> _showReportAlert() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('신고 접수'),
          content: const Text('신고 접수를 하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('접수'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startReportRegistrationMode() async {
    if (_isWaitingForReportLocation) {
      setState(() {
        _isWaitingForReportLocation = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('사건 접수 모드를 종료했습니다.')));
      return;
    }

    final result = await _showReportAlert();
    if (!mounted || result != true) return;

    setState(() {
      _isWaitingForReportLocation = true;
    });
    _ignoreMapClicksUntil = DateTime.now().add(_dialogClickIgnoreDuration);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('지도에서 사건 위치를 클릭해 주세요.')));
  }

  @override
  void dispose() {
    _cameraRefreshTimer?.cancel();
    _cameraStreamApi.dispose();
    _socket?.dispose();
    _clearThreatFocusMarker();
    super.dispose();
  }

  int _threatLevel(Map<String, dynamic> alert) {
    final value = alert['riskLevel'];
    if (value is num) return value.toInt().clamp(1, 4);
    return int.tryParse(value?.toString() ?? '')?.clamp(1, 4) ?? 1;
  }

  Color _threatColor(int level) {
    return switch (level) {
      4 => const Color(0xFFB91C1C),
      3 => const Color(0xFFDC2626),
      2 => const Color(0xFFD97706),
      _ => const Color(0xFF2563EB),
    };
  }

  Color _threatBackgroundColor(int level) {
    return switch (level) {
      4 => const Color(0xFFFEF2F2),
      3 => const Color(0xFFFFF7ED),
      2 => const Color(0xFFFFFBEB),
      _ => const Color(0xFFEFF6FF),
    };
  }

  String _threatSeverity(int level) {
    return switch (level) {
      4 => '긴급',
      3 => '고위험',
      2 => '주의',
      _ => '관찰',
    };
  }

  String _threatTime(Map<String, dynamic> alert) {
    final raw = alert['occurredAt']?.toString() ?? '';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return '시간 미확인';
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(parsed.hour)}:${twoDigits(parsed.minute)}:${twoDigits(parsed.second)}';
  }

  String _threatOfficer(Map<String, dynamic> alert) {
    final rank = alert['rank']?.toString().trim() ?? '';
    final name = alert['officerName']?.toString().trim() ?? '';
    final displayName = [
      rank,
      name,
    ].where((value) => value.isNotEmpty).join(' ');
    return displayName.isEmpty ? '현장 경찰관' : displayName;
  }

  String _localizedRegion(Object? value) {
    final region = value?.toString().trim() ?? '';
    const knownRegions = {
      'Seoul Nowon': '서울 노원구',
      'Seoul Nowon-gu': '서울 노원구',
      'SEOUL_NOWON': '서울 노원구',
      'Seoul Dobong': '서울 도봉구',
      'Seoul Dobong-gu': '서울 도봉구',
      'SEOUL_DOBONG': '서울 도봉구',
      'ALL': '전체 관할',
      'All': '전체 관할',
    };
    return knownRegions[region] ?? region;
  }

  List<String> _threatReasons(Map<String, dynamic> alert) {
    final reasons = alert['reasons'];
    if (reasons is List) {
      final values = reasons
          .map((reason) => reason.toString().trim())
          .where((reason) => reason.isNotEmpty)
          .map(_serviceThreatReason)
          .toList();
      if (values.isNotEmpty) return values;
    }
    return const ['세부 감지 근거 없음'];
  }

  String _serviceThreatReason(String reason) {
    const contextPrefix = '문맥 분류 모델:';
    if (reason.startsWith(contextPrefix)) {
      final situation = reason.substring(contextPrefix.length).trim();
      return situation.endsWith('감지') ? '$situation됨' : '$situation 상황 감지됨';
    }
    if (reason.startsWith('평소 대비 데시벨: 상승')) {
      final details = reason.substring('평소 대비 데시벨: 상승'.length);
      return '평소보다 큰 고성이 감지됨$details';
    }
    if (reason == '주변 소리: 여러 사람의 목소리 감지') {
      return '여러 사람의 목소리가 동시에 감지됨';
    }
    if (reason.startsWith('위험 소리:')) {
      final sound = reason.substring('위험 소리:'.length).trim();
      return sound.endsWith('감지') ? '$sound됨' : '$sound 소리가 감지됨';
    }
    if (reason.startsWith('반복 감지:')) {
      return '최근 30초 동안 위험 상황이 반복 감지됨';
    }
    return reason;
  }

  Widget _buildThreatAlertRow(Map<String, dynamic> alert) {
    final level = _threatLevel(alert);
    final color = _threatColor(level);
    final region = _localizedRegion(alert['region']);
    final latitude = alert['latitude'];
    final longitude = alert['longitude'];
    final hasLocation = latitude is num && longitude is num;

    return Container(
      decoration: BoxDecoration(
        color: _threatBackgroundColor(level),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  alert['alertLabel']?.toString() ?? '위협',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${_threatSeverity(level)} · Lv.$level',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _threatTime(alert),
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
              if (hasLocation) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => _focusThreatAlert(alert),
                  tooltip: '지도에서 위치 보기',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.my_location, size: 18, color: color),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Text(
            _threatOfficer(alert),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final reason in _threatReasons(alert).take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.circle,
                      size: 4,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      reason,
                      style: const TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 7),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 15,
                color: Color(0xFF6B7280),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  region.isNotEmpty
                      ? region
                      : hasLocation
                      ? '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
                      : '위치 정보 없음',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DateTime? _threatOccurredAt(Map<String, dynamic> alert) {
    return DateTime.tryParse(alert['occurredAt']?.toString() ?? '')?.toLocal();
  }

  String _threatDateTime(Map<String, dynamic> alert) {
    final value = _threatOccurredAt(alert);
    if (value == null) return '시간 미확인';
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(value.month)}.${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
  }

  double _threatEvidenceIndex(Map<String, dynamic> alert) {
    final value = alert['evidenceIndex'];
    if (value is num) return value.toDouble().clamp(0.0, 100.0);
    return (double.tryParse(value?.toString() ?? '') ?? 0.0).clamp(0.0, 100.0);
  }

  Map<String, String> _threatOfficerOptions() {
    final options = <String, String>{'ALL': '전체 경찰관'};
    for (final alert in _threatAlerts) {
      final key = alert['officerId']?.toString().trim() ?? '';
      if (key.isNotEmpty) options[key] = _threatOfficer(alert);
    }
    return options;
  }

  Map<String, String> _threatCategoryOptions() {
    final options = <String, String>{'ALL': '전체 위험 종류'};
    for (final alert in _threatAlerts) {
      final key = alert['category']?.toString().trim() ?? '';
      if (key.isNotEmpty) {
        options[key] = alert['alertLabel']?.toString() ?? '위험';
      }
    }
    return options;
  }

  bool _matchesThreatTime(Map<String, dynamic> alert) {
    if (_threatTimeFilter == 'ALL') return true;
    final occurredAt = _threatOccurredAt(alert);
    if (occurredAt == null) return false;
    final now = DateTime.now();
    return switch (_threatTimeFilter) {
      'TODAY' =>
        occurredAt.year == now.year &&
            occurredAt.month == now.month &&
            occurredAt.day == now.day,
      '24H' => occurredAt.isAfter(now.subtract(const Duration(hours: 24))),
      '7D' => occurredAt.isAfter(now.subtract(const Duration(days: 7))),
      _ => true,
    };
  }

  List<Map<String, dynamic>> _filteredThreatAlerts() {
    return _threatAlerts.where((alert) {
      final officerMatches =
          _threatOfficerFilter == 'ALL' ||
          alert['officerId']?.toString() == _threatOfficerFilter;
      final categoryMatches =
          _threatCategoryFilter == 'ALL' ||
          alert['category']?.toString() == _threatCategoryFilter;
      return officerMatches && categoryMatches && _matchesThreatTime(alert);
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> _groupThreatAlerts(
    List<Map<String, dynamic>> alerts,
  ) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final alert in alerts) {
      final sessionId = alert['sessionId']?.toString().trim();
      final eventId = alert['eventId']?.toString() ?? '${groups.length}';
      final key = sessionId == null || sessionId.isEmpty
          ? 'event:$eventId'
          : sessionId;
      groups.putIfAbsent(key, () => []).add(alert);
    }
    return groups;
  }

  Widget _buildThreatFilter({
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    final selected = options.containsKey(value) ? value : 'ALL';
    return SizedBox(
      width: 142,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
          ),
          const SizedBox(height: 5),
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected,
                isExpanded: true,
                icon: const Icon(Icons.expand_more, size: 18),
                style: const TextStyle(color: Color(0xFF374151), fontSize: 12),
                items: options.entries
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (newValue) {
                  if (newValue != null) onChanged(newValue);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreatHistoryEvent(Map<String, dynamic> alert) {
    final level = _threatLevel(alert);
    final color = _threatColor(level);
    final latitude = _coordinate(alert['latitude']);
    final longitude = _coordinate(alert['longitude']);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  alert['alertLabel']?.toString() ?? '위험 상황',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${_threatSeverity(level)} · Lv.$level',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (latitude != null && longitude != null)
                IconButton(
                  onPressed: () => _focusThreatAlert(alert),
                  tooltip: '지도에서 위치 보기',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.my_location, size: 18, color: color),
                ),
            ],
          ),
          Text(
            '${_threatDateTime(alert)} · 위험 지수 ${_threatEvidenceIndex(alert).toStringAsFixed(1)}',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
          const SizedBox(height: 9),
          for (final reason in _threatReasons(alert))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.check, size: 14, color: color),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      reason,
                      style: const TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThreatSessionGroup(
    List<Map<String, dynamic>> alerts, {
    required bool initiallyExpanded,
  }) {
    final latest = alerts.first;
    var maxLevel = 1;
    for (final alert in alerts) {
      final level = _threatLevel(alert);
      if (level > maxLevel) maxLevel = level;
    }
    final color = _threatColor(maxLevel);
    final chronological = alerts.reversed.toList();
    final region = _localizedRegion(latest['region']);

    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      childrenPadding: EdgeInsets.zero,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _threatBackgroundColor(maxLevel),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.warning_amber_rounded, color: color, size: 20),
      ),
      title: Text(
        '${latest['alertLabel'] ?? '위험 상황'} · ${_threatSeverity(maxLevel)}',
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '${_threatOfficer(latest)}${region.isEmpty ? '' : ' · $region'} · ${alerts.length}건',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
      ),
      children: [
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '최근 위험 지수 변화',
                style: TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 110,
                width: double.infinity,
                child: CustomPaint(painter: _ThreatTrendPainter(chronological)),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '시작',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10),
                  ),
                  Text(
                    '최근',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final alert in alerts) _buildThreatHistoryEvent(alert),
      ],
    );
  }

  Widget _buildThreatHistoryPanel() {
    final filteredAlerts = _filteredThreatAlerts();
    final groups = _groupThreatAlerts(filteredAlerts).values.toList();
    final officerOptions = _threatOfficerOptions();
    final categoryOptions = _threatCategoryOptions();

    return Material(
      elevation: 12,
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 500,
        child: Column(
          children: [
            Container(
              color: const Color(0xFF1B3B6F),
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '위험 상황 기록',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loadThreatAlerts,
                    tooltip: '기록 새로고침',
                    icon: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    onPressed: _toggleThreatHistory,
                    tooltip: '닫기',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildThreatFilter(
                    label: '경찰관',
                    value: _threatOfficerFilter,
                    options: officerOptions,
                    onChanged: (value) =>
                        setState(() => _threatOfficerFilter = value),
                  ),
                  _buildThreatFilter(
                    label: '위험 종류',
                    value: _threatCategoryFilter,
                    options: categoryOptions,
                    onChanged: (value) =>
                        setState(() => _threatCategoryFilter = value),
                  ),
                  _buildThreatFilter(
                    label: '발생 시간',
                    value: _threatTimeFilter,
                    options: const {
                      'ALL': '전체 기간',
                      'TODAY': '오늘',
                      '24H': '최근 24시간',
                      '7D': '최근 7일',
                    },
                    onChanged: (value) =>
                        setState(() => _threatTimeFilter = value),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE5E7EB)),
                  bottom: BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
              child: Text(
                '출동 세션 ${groups.length}건 · 위험 알림 ${filteredAlerts.length}건',
                style: const TextStyle(color: Color(0xFF4B5563), fontSize: 12),
              ),
            ),
            Expanded(
              child: groups.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 34,
                            color: Color(0xFF9CA3AF),
                          ),
                          SizedBox(height: 10),
                          Text(
                            '조건에 맞는 위험 기록이 없습니다.',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: groups.length,
                      itemBuilder: (context, index) => _buildThreatSessionGroup(
                        groups[index],
                        initiallyExpanded: index == 0,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  AdminCameraStream? _selectedCameraStream() {
    for (final stream in _cameraStreams) {
      if (stream.officerId == _selectedCameraOfficerId) return stream;
    }
    return null;
  }

  String _cameraUpdatedTime(DateTime? value) {
    if (value == null) return '화면 대기 중';
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(local.hour)}:${twoDigits(local.minute)}:'
        '${twoDigits(local.second)} 기준';
  }

  Widget _buildCameraPanel() {
    final selected = _selectedCameraStream();
    return Material(
      elevation: 12,
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: const Color(0xFF1B3B6F),
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
              child: Row(
                children: [
                  const Icon(Icons.videocam_outlined, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '현장 카메라',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.circle, color: Color(0xFF4ADE80), size: 9),
                  const SizedBox(width: 5),
                  Text(
                    '${_cameraStreams.length}명 연결',
                    style: const TextStyle(
                      color: Color(0xFFD1FAE5),
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    onPressed: _refreshCameraStreams,
                    tooltip: '현장 화면 새로고침',
                    icon: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    onPressed: _toggleCameraPanel,
                    tooltip: '닫기',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            if (_cameraStreams.isNotEmpty)
              Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCameraOfficerId,
                    isExpanded: true,
                    icon: const Icon(Icons.expand_more),
                    items: _cameraStreams
                        .map(
                          (stream) => DropdownMenuItem<String>(
                            value: stream.officerId,
                            child: Text(
                              '${stream.officerLabel} · '
                              '${_localizedRegion(stream.region)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (officerId) {
                      if (officerId == null) return;
                      setState(() {
                        _selectedCameraOfficerId = officerId;
                        _cameraFrame = null;
                      });
                      unawaited(_refreshCameraStreams());
                    },
                  ),
                ),
              ),
            Expanded(
              child: _cameraStreams.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam_off_outlined,
                            color: Color(0xFF94A3B8),
                            size: 42,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _cameraStreamError == null
                                ? '카메라를 켠 현장 경찰관이 없습니다.'
                                : '현장 화면 연결을 확인할 수 없습니다.',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      color: const Color(0xFF111827),
                      alignment: Alignment.center,
                      child: _cameraFrame == null
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Image.memory(
                              _cameraFrame!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                    ),
            ),
            if (selected != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selected.officerLabel,
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          _cameraUpdatedTime(selected.updatedAt),
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    if (selected.detections.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: selected.detections.map((detection) {
                          final isKnife = detection['label'] == 'knife';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isKnife
                                  ? const Color(0xFFFEE2E2)
                                  : const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${isKnife ? '칼' : '병'} 감지',
                              style: TextStyle(
                                color: isKnife
                                    ? const Color(0xFFB91C1C)
                                    : const Color(0xFFC2410C),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationsPanel() {
    final recentAlerts = _threatAlerts.take(1).toList();

    return Material(
      elevation: 8,
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: Color(0xFF1B3B6F),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '실시간 현장 관제',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.circle, size: 9, color: Color(0xFF16A34A)),
                  const SizedBox(width: 5),
                  const Text(
                    '실시간',
                    style: TextStyle(color: Color(0xFF15803D), fontSize: 12),
                  ),
                  IconButton(
                    onPressed: _loadThreatAlerts,
                    tooltip: '위험 알림 새로고침',
                    icon: const Icon(Icons.refresh, size: 20),
                    color: const Color(0xFF4B5563),
                  ),
                ],
              ),
            ),
            Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatusMetric(
                      Icons.local_police_outlined,
                      '활동 경찰관',
                      '${_officerMarkers.length}명',
                      const Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(height: 38, child: VerticalDivider(width: 24)),
                  Expanded(
                    child: _buildStatusMetric(
                      Icons.warning_amber_rounded,
                      '위험 알림',
                      '${_threatAlerts.length}건',
                      _threatAlerts.isEmpty
                          ? const Color(0xFF64748B)
                          : _threatColor(_threatLevel(_threatAlerts.first)),
                    ),
                  ),
                  const SizedBox(height: 38, child: VerticalDivider(width: 24)),
                  Expanded(
                    child: _buildStatusMetric(
                      Icons.hub_outlined,
                      '연결 채널',
                      '${_connectedRegions.length}개',
                      const Color(0xFF0F766E),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '최근 위험 알림',
                      style: TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    recentAlerts.isEmpty ? '정상' : '최신 알림',
                    style: TextStyle(
                      color: recentAlerts.isEmpty
                          ? const Color(0xFF15803D)
                          : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (recentAlerts.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 8, 18, 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF16A34A),
                      size: 20,
                    ),
                    SizedBox(width: 9),
                    Text(
                      '현재 수신된 위험 알림이 없습니다.',
                      style: TextStyle(color: Color(0xFF4B5563), fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              ...recentAlerts.map(_buildThreatAlertRow),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMetric(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reportDetailWidth = (MediaQuery.of(context).size.width * 0.46)
        .clamp(360.0, 720.0)
        .toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'POLWEB - 종합 상황실 대시보드',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        backgroundColor: const Color(0xFF1B3B6F),
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          Tooltip(
            message: '카메라를 켠 현장 경찰관의 화면을 확인합니다.',
            child: TextButton.icon(
              onPressed: _toggleCameraPanel,
              icon: Icon(
                _cameraStreams.isEmpty
                    ? Icons.videocam_off_outlined
                    : Icons.videocam,
                color: _cameraStreams.isEmpty
                    ? const Color(0xFFCBD5E1)
                    : const Color(0xFF4ADE80),
              ),
              label: Text(
                '현장 영상 ${_cameraStreams.length}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          Tooltip(
            message: '위험 상황 기록을 조회합니다.',
            child: TextButton.icon(
              onPressed: _toggleThreatHistory,
              icon: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFFBBF24),
              ),
              label: const Text('위험 기록', style: TextStyle(color: Colors.white)),
            ),
          ),
          Tooltip(
            message: '클릭한 위치에 신고를 접수합니다.',
            child: TextButton.icon(
              onPressed: _startReportRegistrationMode,
              style: TextButton.styleFrom(
                backgroundColor: _isWaitingForReportLocation
                    ? Colors.redAccent
                    : Colors.transparent,
                foregroundColor: Colors.white,
              ),
              icon: Icon(
                Icons.crisis_alert,
                color: _isWaitingForReportLocation
                    ? Colors.white
                    : Colors.redAccent,
              ),
              label: const Text('신고 접수', style: TextStyle(color: Colors.white)),
            ),
          ),
          Tooltip(
            message: '발생한 사건 내역을 확인합니다.',
            child: TextButton.icon(
              onPressed: _toggleReportList,
              icon: const Icon(Icons.list_alt, color: Colors.white),
              label: const Text(
                '사건 목록 조회',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          Tooltip(
            message: '관할 지역 경찰관들에게 메세지를 전파합니다.',
            child: TextButton.icon(
              onPressed: _showRadioDialog,
              icon: const Icon(Icons.campaign, color: Colors.redAccent),
              label: const Text(
                '전체 메시지 전파',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
            tooltip: '시스템 설정',
          ),
          const SizedBox(width: 16),
        ],
      ),

      body: Stack(
        children: [
          Positioned.fill(
            child: kIsWeb
                ? HtmlElementView(viewType: _viewId)
                : const Center(child: Text('이 페이지는 웹 환경에서만 지원됩니다.')),
          ),

          Positioned(top: 24, left: 24, child: _buildOperationsPanel()),
          if (_selectedReportId != null)
            Positioned(
              top: 24,
              right: 24,
              bottom: 24,
              child: _buildReportDetailPanel(reportDetailWidth),
            ),
          if (_isReportListOpen)
            Positioned(
              top: 24,
              right: 24,
              bottom: 24,
              width: 360,
              child: AdminDashboardList(
                onClose: _toggleReportList,
                reports: _reports.values.toList(),
                onReportTap: (reportId) {
                  setState(() {
                    _selectedReportId = reportId;
                    _isReportListOpen = false;
                    _isThreatHistoryOpen = false;
                    _isCameraPanelOpen = false;
                  });
                },
              ),
            ),
          if (_isThreatHistoryOpen)
            Positioned(
              top: 24,
              right: 24,
              bottom: 24,
              child: _buildThreatHistoryPanel(),
            ),
          if (_isCameraPanelOpen)
            Positioned(
              top: 24,
              right: 24,
              bottom: 24,
              child: _buildCameraPanel(),
            ),
        ],
      ),
    );
  }
}

class _ThreatTrendPainter extends CustomPainter {
  const _ThreatTrendPainter(this.alerts);

  final List<Map<String, dynamic>> alerts;

  double _score(Map<String, dynamic> alert) {
    final value = alert['evidenceIndex'];
    if (value is num) return value.toDouble().clamp(0.0, 100.0);
    return (double.tryParse(value?.toString() ?? '') ?? 0.0).clamp(0.0, 100.0);
  }

  int _level(Map<String, dynamic> alert) {
    final value = alert['riskLevel'];
    if (value is num) return value.toInt().clamp(1, 4);
    return int.tryParse(value?.toString() ?? '')?.clamp(1, 4) ?? 1;
  }

  Color _color(int level) {
    return switch (level) {
      4 => const Color(0xFFB91C1C),
      3 => const Color(0xFFDC2626),
      2 => const Color(0xFFD97706),
      _ => const Color(0xFF2563EB),
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (alerts.isEmpty || size.width <= 20 || size.height <= 20) return;
    final chart = Rect.fromLTWH(8, 6, size.width - 16, size.height - 16);
    final gridPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = chart.top + chart.height * index / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    final points = <Offset>[];
    for (var index = 0; index < alerts.length; index++) {
      final x = alerts.length == 1
          ? chart.right
          : chart.left + chart.width * index / (alerts.length - 1);
      final y = chart.bottom - chart.height * _score(alerts[index]) / 100.0;
      points.add(Offset(x, y));
    }

    if (points.length > 1) {
      final fillPath = Path()
        ..moveTo(points.first.dx, chart.bottom)
        ..lineTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        fillPath.lineTo(point.dx, point.dy);
      }
      fillPath
        ..lineTo(points.last.dx, chart.bottom)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()..color = const Color(0xFFDC2626).withValues(alpha: 0.08),
      );

      final linePath = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        linePath.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        linePath,
        Paint()
          ..color = const Color(0xFF991B1B)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var index = 0; index < points.length; index++) {
      canvas.drawCircle(points[index], 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(
        points[index],
        3.2,
        Paint()..color = _color(_level(alerts[index])),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ThreatTrendPainter oldDelegate) {
    return oldDelegate.alerts != alerts;
  }
}
