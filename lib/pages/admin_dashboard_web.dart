import 'dart:async'; // Timer 기능을 사용하기 위해 추가
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kIsWeb을 사용하기 위해 추가

import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:web/web.dart' as web; // 브라우저의 HTML DOM(div 등)을 조작하기 위해 추가
import 'dart:js_interop' as js; // Dart 코드에서 JavaScript 변수나 함수를 직접 호출하기 위해 추가
import 'dart:js_interop_unsafe'; // JS 객체의 속성에 동적으로 접근하기 위해 추가
import 'dart:ui_web' as ui_web; // 플러터 웹 화면 안에 HTML 요소를 등록하기 위해 추가
import 'admin_dashboard_list.dart'; // 사건 내용 리스트
import '../models/report.dart';
import '../services/report_api_service.dart';

// 사건 마커는 지도에 표시되는 JS 객체이고, 상세 내용은 Dart 상태로 따로 보관

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final String _viewId = 'naver-map-web-view'; // HtmlElementView와 실제 생성할 HTML div 요소를 연결해주는 고유 식별자(ID)
  io.Socket? _socket;
  final Map<String, js.JSObject> _officerMarkers = {}; // 경찰관 ID를 Key로, 자바스크립트 마커 객체를 Value로 저장하는 딕셔너리
  final Set<String> _connectedRegions = {}; // 현재 접속 중인 지역 채널들을 중복 없이 저장하는 Set
  final Map<String, String> _officerRegions = {}; // 퇴장 시 채널 목록을 동적으로 계산하기 위해 경찰관 ID별 지역을 저장하는 Map
  bool _isReportListOpen = false; // 상태 관리 플래그
  final Map<String, js.JSObject> _reportMarkers = {}; // 사건 마커 저장용 MAP
  final Map<String, Report> _reports = {}; // 사건 상세 내용을 id 기준으로 보관하는 로컬 상태
  final ReportApiService _reportApi = ReportApiService(); // DB에 저장되는 사건 데이터를 HTTP API로 조회/생성/종료하기 위한 서비스
  String? _selectedReportId; // 우측 상세 패널에 표시할 현재 선택 사건 id
  final List<js.JSAny> _mapEventHandlers = [];
  bool _isCreateReportDialogOpen = false; // 사건 입력창이 이미 열려 있는지 확인하여 중복 표시를 방지
  bool _isWaitingForReportLocation = false; // 사건 접수 확인 후, 지도에서 사건 위치 클릭을 기다리는 상태

  // 확인창 버튼 클릭이 지도 클릭으로 이어지는 것을 막기 위해 일정 시간 클릭 무시
  DateTime? _lastMapDragEndedAt;
  static const Duration _dialogClickIgnoreDuration = Duration(milliseconds: 500);

  // 지도 드래그 중이거나 드래그 직후 발생하는 클릭 이벤트를 무시하기 위한 상태
  bool _isMapDragging = false;
  DateTime? _ignoreMapClicksUntil;
  static const Duration _mapDragClickIgnoreDuration = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    
    // 현재 환경이 웹일 경우에만 HTML 요소를 생성하고 등록
    if (kIsWeb) {
      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        
        // 브라우저 화면에 지도를 담을 빈 HTML <div> 태그를 생성
        final web.HTMLDivElement div = web.HTMLDivElement()
          ..id = 'map' // 나중에 JS에서 이 요소를 찾기 위해 id를 'map'으로 지정
          ..style.width = '100%' // 화면 너비 100%
          ..style.height = '100%'; // 화면 높이 100%

        // 네이버 API 키 노출을 막기 위해 스크립트를 동적으로 삽입
        _injectNaverMapScript(div);

        // 생성된 div 요소를 플러터 프레임워크에 반환하여 렌더링
        return div;
      });
    }
  }

  // launch.json의 환경 변수를 읽어 HTML에 네이버 지도 스크립트를 동적으로 삽입
  void _injectNaverMapScript(web.HTMLDivElement div) {
    // 환경 변수에서 웹 전용 클라이언트 ID 로드 (깃허브 노출 방지)
    final String clientId = const String.fromEnvironment('NAVER_MAP_WEB_CLIENT_ID');
    
    // 이미 스크립트가 로드되어 window.naver 객체가 존재한다면 중복 삽입 방지
    if (js.globalContext['naver'] != null) {
      _waitForMapDivAndInitialize(div);
      return;
    }

    // HTML의 <script> 태그 객체를 동적으로 생성
    final script = web.document.createElement('script') as web.HTMLScriptElement;
    
    // 최신 네이버 지도 사양에 맞춘 ncpKeyId 파라미터 적용
    script.src = 'https://openapi.map.naver.com/openapi/v3/maps.js?ncpKeyId=$clientId';
    script.type = 'text/javascript';
    script.async = true;

    // 자바스크립트 스크립트 파일이 네트워크를 통해 완전히 다운로드 및 로드가 완료되었을 때 실행할 콜백
    script.onload = () {
      if (mounted) {
        _waitForMapDivAndInitialize(div);
      }
    }.toJS; // dart:js_interop과 호환되도록 자바스크립트 함수 형태로 변환

    // HTML의 <head> 태그 내부에 위에서 만든 <script> 태그를 자식 요소로 넣음
    web.document.head?.appendChild(script);
  }

  /// HTML 요소 렌더링 대기 (경쟁 상태 방지)
  /// 컴퓨터 성능이나 네트워크에 따라 HTML div가 화면에 그려지는 속도가 다를 수 있음
  void _waitForMapDivAndInitialize(web.HTMLDivElement div) {
    // 0.05초(50ms) 간격으로 화면을 계속 확인
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      // 브라우저 문서 전체에서 id가 'map'인 요소를 찾음
      final element = web.document.getElementById('map');

      // 요소가 찾아졌다면 (화면에 div가 성공적으로 그려졌다면)
      if (element != null) {
        timer.cancel(); // 더 이상의 확인 작업(타이머)을 중지
        _initializeNaverMap(div); // 지도 초기화
        _connectWebSocket(); // 소켓 연결
      }
    });
  }

  /// 네이버 지도 객체 생성 및 JS 연동
  void _initializeNaverMap(web.HTMLDivElement div) {
    final naver = js.globalContext['naver'] as js.JSObject?;
    
    if (naver != null) {
      final maps = naver['maps'] as js.JSObject;

      // 중심 좌표 설정 (광운대학교)
      final center = maps.callMethod('LatLng'.toJS, 37.6194.toJS, 127.0598.toJS);
      
      final mapOptions = {
        'center': center,
        'zoom': 13.toJS,
      }.jsify();

      final mapConstructor = maps['Map'] as js.JSFunction;
      final mapInstance = mapConstructor.callAsConstructor(div as js.JSAny, mapOptions as js.JSAny);

      js.globalContext['adminMap'] = mapInstance;

      _attachMapClickListener(mapInstance as js.JSObject);
      _loadReportsFromServer();
    } else {
      debugPrint('⚠️ [Error] 네이버 지도 스크립트 로드 실패');
    }
  }

  // 네이버 지도에 드래그/클릭 이벤트를 등록하여 사건 위치 선택을 처리
  void _attachMapClickListener(js.JSObject mapInstance) {
    final naver = js.globalContext['naver'] as js.JSObject?;
    // 예외 처리
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

    // 지도 클릭 확인용 Debug 출력
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

    _mapEventHandlers.addAll([
      dragStartHandler,
      dragEndHandler,
      clickHandler,
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

    debugPrint('[Debug] 지도 이벤트 리스너 등록 완료');
  }

  // 확인창 클릭 또는 지도 드래그로 인해 발생한 의도치 않은 클릭인지 검사
  bool _shouldIgnoreMapClick() {
    final ignoreUntil = _ignoreMapClicksUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) return true;

    if (_isMapDragging) return true;

    final lastDragEndedAt = _lastMapDragEndedAt;
    if (lastDragEndedAt == null) return false;

    return DateTime.now().difference(lastDragEndedAt) < _mapDragClickIgnoreDuration;
  }

  // 위치 선택 모드에서 지도 클릭 시 사건 입력창을 표시
  Future<void> _handleMapClick(double lat, double lng) async {
    if (!_isWaitingForReportLocation || _isCreateReportDialogOpen) return;

    _isCreateReportDialogOpen = true;
    try {
      await _showCreateReportDialog(lat, lng);
    } finally {
      _isCreateReportDialogOpen = false;
    }
  }

  /// 웹소켓 연결을 초기화하고 실시간 이벤트 리스너를 설정하는 함수
  void _connectWebSocket() {
    // 환경변수(launch.json)에 등록된 백엔드 웹소켓 서버 URL을 로드
    final String serverUrl = const String.fromEnvironment('WS_SERVER_URL');
    debugPrint('[Debug] 서버 연결 시도 주소: $serverUrl');

    // Socket.IO 클라이언트 생성 (웹 환경에서의 호환성을 위해 websocket 전송방식을 강제 지정)
    _socket = io.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false, // 인스턴스 설정 후 명시적으로 connect()를 호출하기 위함
    });

    // 1. 서버와 소켓 핸드셰이크(연결)가 최종 성공했을 때 실행되는 콜백
    _socket?.onConnect((_) {
      debugPrint('[Debug] 웹소켓 연결 성공! (세션 ID: ${_socket?.id})');
      
      // 관리자(ADMIN) 권한으로 세션 방(Room)에 입장합니다.
      // role이 'ADMIN'일 경우, 서버는 특정 관할 구역에 국한되지 않고 모든 경찰관의 위치를 브로드캐스트
      _socket?.emit('join', {
        'officerId': 'ADMIN-001',
        'region': 'ALL', // ADMIN 권한이므로 서버에서 무시되지만 프로토콜 규격을 위해 전달
        'role': 'ADMIN'
      });
      debugPrint('[Debug] Join 이벤트 전송 완료 (Role: ADMIN)');
    });

    // 네트워크 불안정 등으로 인한 소켓 연결 실패 시 로그 출력
    _socket?.onConnectError((error) {
      debugPrint('[Debug] 연결 에러 발생: $error');
    });

    // 2. 서버로부터 현장 경찰관의 실시간 좌표 데이터를 수신했을 때 (updateColleagueLocation)
    _socket?.on('updateColleagueLocation', (data) {
      debugPrint('[Debug] 위치 데이터 수신함: $data');
      
      try {
        // 서버에서 받아온 JSON Object 보따리에서 개별 데이터 파싱
        final String officerId = data['officerId'].toString();
        final double lat = (data['latitude'] as num).toDouble();
        final double lng = (data['longitude'] as num).toDouble();
        final String? regionCode = data['region']?.toString();
        
        // 구역 코드를 UI에 보여줄 한글 지역명으로 변환
        String? regionName;
        if (regionCode == 'SEOUL_NOWON') {
          regionName = '노원구';
        } else if (regionCode == 'SEOUL_DOBONG') {
          regionName = '도봉구';
        } else if (regionCode != null) {
          regionName = regionCode;
        }

        // 파싱된 데이터를 기반으로 자바스크립트 지도 위에 마커를 투영하는 함수 호출
        _updateOfficerMarkerJS(officerId, lat, lng);

        // 지역 정보를 상태 변수에 등록하고 화면을 다시 그리도록 알림
        setState(() {
          if (regionName != null) {
            _officerRegions[officerId] = regionName; // 경찰관별 지역 매핑 저장
            _connectedRegions.add(regionName);      // 활성화된 채널 목록에 추가
          }
        });
      } catch (e) {
        debugPrint('[Debug] 데이터 파싱 에러: $e');
      }
    });

    // 서버로부터 특정 경찰관의 연결 해제(종료) 이벤트를 수신했을 때 처리
    _socket?.on('removeColleagueLocation', (data) {
      debugPrint('[Debug] 연결 해제 데이터 수신함: $data');
      try {
        final String officerId = data['officerId'].toString();
        
        // 지도에서 마커를 지우고 카운트를 빼는 함수 호출
        _removeOfficerMarkerJS(officerId);
      } catch (e) {
        debugPrint('[Debug] 연결 해제 처리 에러: $e');
      }
    });

    // 백엔드가 DB 저장 성공 후 reportCreated를 브로드캐스트하도록 확장되면 이 리스너가 다른 관리자 화면을 실시간 갱신한다.
    // 현재 확인한 백엔드 커밋에는 해당 emit이 없으므로, 지금은 POST 응답과 GET 복원 로직이 주 갱신 경로다.
    _socket?.on('reportCreated', (data) {
      debugPrint('[Debug] 사건 생성 이벤트 수신함: $data');
      try {
        final report = Report.fromJson(Map<String, dynamic>.from(data as Map));
        _upsertReport(report);
      } catch (e) {
        debugPrint('[Debug] 사건 생성 이벤트 처리 에러: $e');
      }
    });

    // 백엔드가 reportClosed 이벤트를 보내면 마커를 제거하고 목록의 상태를 CLOSED로 바꾼다.
    // 이벤트 payload가 부분 데이터일 수 있으므로 id/status 중심으로 방어적으로 처리한다.
    _socket?.on('reportClosed', (data) {
      debugPrint('[Debug] 사건 종료 이벤트 수신함: $data');
      try {
        final payload = Map<String, dynamic>.from(data as Map);
        final reportId = payload['id'].toString();
        _markReportClosed(
          reportId,
          closedAt: DateTime.tryParse(payload['closedAt']?.toString() ?? ''),
          closedBy: payload['closedBy'] is num ? (payload['closedBy'] as num).toInt() : null,
        );
      } catch (e) {
        debugPrint('[Debug] 사건 종료 이벤트 처리 에러: $e');
      }
    });

    // 설정된 리스너들을 바탕으로 실제 서버 연결 세션을 활성화
    _socket?.connect();
  }

  // dart:js_interop 기술을 활용하여 브라우저 런타임의 네이버 지도 JS 객체를 직접 제어하는 함수
  void _updateOfficerMarkerJS(String officerId, double lat, double lng) {
    // index.html 레이어에 로드된 window.naver 객체와 지도 초기화 시 저장해둔 window.adminMap 객체를 가져옴
    final naver = js.globalContext['naver'] as js.JSObject?;
    final adminMap = js.globalContext['adminMap'] as js.JSObject?;

    // 지도가 아직 화면에 그려지지 않았거나 스크립트 로딩이 누락되었다면 예외 처리
    if (naver == null || adminMap == null) {
      debugPrint('[Error] 지도 객체가 초기화되지 않았습니다.');
      return;
    }

    // 네이버 지도 라이브러리의 내부 네임스페이스 및 LatLng 생성자 함수 획득
    final maps = naver['maps'] as js.JSObject;
    
    // JS 문법의 [ new naver.maps.LatLng(lat, lng) ] 객체 생성을 상호운용성(Interop) 타입 변환(.toJS)을 통해 실행
    final position = maps.callMethod('LatLng'.toJS, lat.toJS, lng.toJS);

    // 이미 마커 딕셔너리(_officerMarkers)에 등록되어 관리 중인 경찰관인지 확인
    if (_officerMarkers.containsKey(officerId)) {
      // 3-A. 기존에 이미 존재하던 마커라면, 객체를 재생성하지 않고 좌표만 슬라이딩 이동 (렌더링 최적화 및 깜빡임 방지)
      debugPrint('[Debug] 기존 마커 이동: $officerId ($lat, $lng)');
      final existingMarker = _officerMarkers[officerId]!;
      
      // JS 문법의 [ marker.setPosition(position) ] 함수 호출
      existingMarker.callMethod('setPosition'.toJS, position);
    } else {
      // 3-B. 새롭게 접속한 경찰관이라면 자바스크립트 기반의 네이버 지도 마커 객체를 신규 생성
      debugPrint('[Debug] 새 마커 생성: $officerId ($lat, $lng)');
      
      // Dart의 Map 구조체를 자바스크립트가 읽을 수 있는 순수 Object 객체로 변환 (.jsify())
      final markerOptions = {
        'position': position,
        'map': adminMap,
        'title': officerId, // 마우스를 올렸을 때 경찰관 고유 ID 툴팁 노출
      }.jsify();

      // JS 문법의 [ new naver.maps.Marker(options) ] 생성자 함수 호출 및 인스턴스화
      final markerConstructor = maps['Marker'] as js.JSFunction;
      final newMarker = markerConstructor.callAsConstructor(markerOptions as js.JSAny);

      // 관리를 위해 딕셔너리에 경찰관 ID(Key)와 생성된 JS 마커 객체(Value)를 매핑하여 보관
      _officerMarkers[officerId] = newMarker as js.JSObject;

      // 새로운 마커가 추가되었으므로 인원수 UI 갱신을 위해 setState 호출
      setState(() {});
    }
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
        _selectedReportId = _selectedReportId != null && _reports.containsKey(_selectedReportId)
            ? _selectedReportId
            : null;
      });

      // DB가 원본이므로 페이지 재진입 시 서버 목록을 기준으로 OPEN 사건 마커만 복원한다.
      for (final report in reports) {
        if (report.status == ReportStatus.open) {
          _createReportMarkerJS(report);
        }
      }
    } catch (e) {
      debugPrint('[Error] 사건 목록 조회 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사건 목록을 불러오지 못했습니다. $e')),
      );
    }
  }

  void _upsertReport(Report report, {bool select = false}) {
    setState(() {
      _reports[report.id] = report;
      if (select) {
        _selectedReportId = report.id;
        _isReportListOpen = false;
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

  // 서버에서 받은 사건 데이터를 기준으로 지도 위에 JS 마커를 생성한다.
  void _createReportMarkerJS(Report report) {
    final naver = js.globalContext['naver'] as js.JSObject?;
    final adminMap = js.globalContext['adminMap'] as js.JSObject?;

    // 예외처리
    if (naver == null || adminMap == null) {
      debugPrint('[Error] 지도 객체가 초기화되지 않아 사건 마커를 생성할 수 없습니다.');
      return;
    }

    final maps = naver['maps'] as js.JSObject;
    final event = maps['Event'] as js.JSObject;
    final position = maps.callMethod('LatLng'.toJS, report.lat.toJS, report.lng.toJS);

    // 같은 id의 사건이 POST 응답과 웹소켓 이벤트로 중복 반영될 수 있으므로 기존 마커를 먼저 정리한다.
    _removeReportMarkerJS(report.id);

    final markerOptions = {
      'position': position,
      'map': adminMap,
      'title': report.title,
    }.jsify();

    final markerConstructor = maps['Marker'] as js.JSFunction;
    final newMarker = markerConstructor.callAsConstructor(markerOptions as js.JSAny);
    (newMarker as js.JSObject).callMethod('setPosition'.toJS, position);

    // 사건 마커를 클릭하면 지도 우측 상세 패널에 해당 사건 정보를 보여줌
    final markerClickHandler = (() {
      if (!mounted) return;
      setState(() {
        _selectedReportId = report.id;
        _isReportListOpen = false;
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

    debugPrint('[Debug] 사건 마커 생성 완료: ${report.id} (${report.lat}, ${report.lng}, ${report.severity})');
  }

  // 특정 경찰관의 연결 해제 시 지도에서 마커를 지우고 실시간 현황을 갱신하는 함수
  void _removeOfficerMarkerJS(String officerId) {
    if (_officerMarkers.containsKey(officerId)) {
      final existingMarker = _officerMarkers[officerId]!;
      
      // 네이버 지도 JavaScript API 스펙에 맞추어 마커를 지도 레이어에서 완전히 제거
      existingMarker.callMethod('setMap'.toJS, null);
      
      setState(() {
        // 딕셔너리에서 퇴장한 경찰관 데이터 삭제 (자동으로 카운트 감소)
        _officerMarkers.remove(officerId);
        _officerRegions.remove(officerId);
        
        // 현재 남아있는 다른 경찰관들의 지역 정보로 채널 목록을 동적 새로고침
        _connectedRegions.clear();
        _connectedRegions.addAll(_officerRegions.values);
      });
      
      debugPrint('[Debug] 마커 제거 및 실시간 채널 현황 갱신 완료: $officerId');
    }
  }

  // 사건 종료는 먼저 백엔드 PATCH API에 요청하고, 성공한 뒤 로컬 마커와 목록 상태를 갱신한다.
  // 현재 백엔드 응답에는 closedAt/closedBy가 없으므로 화면에서는 현재 시각으로 보정한다.
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사건을 종료했습니다.')),
      );
    } catch (e) {
      debugPrint('[Error] 사건 종료 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사건 종료에 실패했습니다. $e')),
      );
    }
  }

  // 긴급도 4가지 상태
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

  // 긴급도에 따른 색상
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

    // 긴급도에 따른 색상과 상태에 따른 스타일을 미리 계산하여 변수에 저장 (코드 가독성 및 중복 제거)
    final severityColor = _severityColor(report.severity);
    final isClosed = report.status == ReportStatus.closed;

    return Material(  // 패널 배경과 그림자 효과를 위해 Material 위젯으로 감싸줌
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
            Expanded( // 내용이 많을 수 있으므로 스크롤 가능하도록 감싸줌
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: severityColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: severityColor.withValues(alpha: 0.4)),
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                              color: isClosed ? Colors.grey.shade700 : Colors.green.shade700,
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
                      value: '${report.lat.toStringAsFixed(6)}, ${report.lng.toStringAsFixed(6)}',
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
                      onPressed: isClosed ? null : () => _confirmCloseReport(report.id),
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

  // 사건 상세 패널에서 각 정보 항목을 아이콘과 함께 일관된 스타일로 보여주는 재사용 가능한 위젯
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
          child: Text(
            value,
            style: const TextStyle(color: Color(0xFF111827)),
          ),
        ),
      ],
    );
  }

  // DateTime 객체를 'YYYY-MM-DD HH:MM' 형식의 문자열로 변환하는 함수
  String _formatReportTime(DateTime time) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${time.year}-${twoDigits(time.month)}-${twoDigits(time.day)} '
        '${twoDigits(time.hour)}:${twoDigits(time.minute)}';
  }

  // 전체 및 특정 관할 구역을 선택해 무전 메시지를 전파하는 팝업 다이얼로그
  void _showRadioDialog() {
    final TextEditingController messageController = TextEditingController();
    String selectedRegion = 'ALL'; // 기본 선택값을 'ALL'(전 지역)로 설정

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.campaign, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('전체 메시지 전파', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('수신 관할 지역 선택', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // 지역 선택 드롭다운 버튼
                  DropdownButtonFormField<String>(
                    initialValue: selectedRegion,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    // 💡 드롭다운 리스트에 '전 지역' 옵션 추가
                    items: const [
                      DropdownMenuItem(
                        value: 'ALL',
                        child: Text('서울 전 지역'),
                      ),
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
                  const Text('메시지 내용 입력', style: TextStyle(fontWeight: FontWeight.bold)),
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

                    final String currentTimestamp = DateTime.now().toIso8601String();

                    if (_socket != null && _socket!.connected) {
                      // 선택된 region 값('ALL' 또는 특정 지역명)을 그대로 서버에 전송
                      _socket!.emit('sendRadioMessage', {
                        'officerId': 'ADMIN-001',
                        'region': selectedRegion, 
                        'message': text,
                        'timestamp': currentTimestamp,
                      });
                      
                      Navigator.of(context).pop();

                      // 선택한 옵션에 따라 완료 스낵바 문구를 다르게 표시
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

  // 클릭한 지도 좌표를 기준으로 사건 정보 입력창 표시
  Future<void> _showCreateReportDialog(double lat, double lng) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedSeverity = 'LOW';
    bool isSubmitted = false;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
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
                          DropdownMenuItem(value: 'LOW', child: Text('코드3 (비긴급)')),
                          DropdownMenuItem(value: 'MEDIUM', child: Text('코드2')),
                          DropdownMenuItem(value: 'HIGH', child: Text('코드1')),
                          DropdownMenuItem(value: 'URGENT', child: Text('코드0 (긴급)')),
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
                  onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                    final title = titleController.text.trim();
                    final description = descriptionController.text.trim();

                    if (title.isEmpty || description.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('사건 제목과 내용을 입력해 주세요.')),
                      );
                      return;
                    }

                    setDialogState(() {
                      isSaving = true;
                    });

                    try {
                      // 사건의 원본은 DB이므로 로컬 마커를 바로 만들지 않고 POST /reports 성공 응답을 기준으로 반영한다.
                      final report = await _reportApi.createReport(
                        title: title,
                        description: description,
                        severity: selectedSeverity,
                        latitude: lat,
                        longitude: lng,
                      );

                      if (!mounted) return;
                      _upsertReport(report, select: true);

                      isSubmitted = true;
                      setState(() {
                        _isWaitingForReportLocation = false;
                      });

                      Navigator.of(context).pop();
                    } catch (e) {
                      debugPrint('[Error] 사건 생성 실패: $e');
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
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
      }
    });
  }

  // 신고 접수 버튼 클릭 시 사용자에게 확인을 받는 팝업 다이얼로그를 띄우는 함수
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사건 접수 모드를 종료했습니다.')),
      );
      return;
    }

    final result = await _showReportAlert();
    if (!mounted || result != true) return;

    setState(() {
      _isWaitingForReportLocation = true;
    });
    _ignoreMapClicksUntil = DateTime.now().add(_dialogClickIgnoreDuration);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('지도에서 사건 위치를 클릭해 주세요.')),
    );
  }

  /// 대시보드 페이지가 종료되거나 위젯이 해제될 때 호출되는 함수
  @override
  void dispose() {
    _socket?.dispose(); // 불필요한 웹소켓 커넥션을 명시적으로 차단하여 메모리 누수(Memory Leak) 방지
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 화면 크기에 따라 사건 상세 패널의 너비를 유동적으로 조절하되, 최소 360px에서 최대 720px 사이로 제한
    final reportDetailWidth =
        (MediaQuery.of(context).size.width * 0.46).clamp(360.0, 720.0).toDouble();

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
            message: '클릭한 위치에 신고를 접수합니다.',
            child: TextButton.icon(
              onPressed: _startReportRegistrationMode,
              style: TextButton.styleFrom(
                backgroundColor:
                    _isWaitingForReportLocation ? Colors.redAccent : Colors.transparent,
                foregroundColor: Colors.white, // 클릭 시 빨간색으로 강조
              ),
              icon : Icon(
                Icons.crisis_alert,
                color: _isWaitingForReportLocation ? Colors.white : Colors.redAccent, // 클릭 시 아이콘 색상도 변경
              ),
              label: const Text(
                '신고 접수',
                style : TextStyle(color: Colors.white),
              )
            ),
          ),
          Tooltip(
            message: '발생한 사건 내역을 확인합니다.',
            child: TextButton.icon(
            onPressed : _toggleReportList,
            icon: const Icon(Icons.list_alt, color: Colors.white),
            label: const Text('사건 목록 조회', style: TextStyle(color: Colors.white)),
            ),
          ),
          Tooltip(
            message: '관할 지역 경찰관들에게 메세지를 전파합니다.',
            child : TextButton.icon(
            onPressed: _showRadioDialog,
            icon: const Icon(Icons.campaign, color: Colors.redAccent),
            label: const Text('전체 메시지 전파', style: TextStyle(color: Colors.white)),
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

          Positioned(
            top: 24,
            left: 24,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20.0), // 내부 수치는 고정이므로 const 유지
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('실시간 현장 현황', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Text('👮 활동 중인 경찰관: ${_officerMarkers.length}명', 
                        style: const TextStyle(fontSize: 16, color: Colors.blue)),
                    const SizedBox(height: 8),
                    const Text('🚨 위협 감지: 0건', 
                        style: TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('📡 연결된 채널: ${_connectedRegions.isEmpty ? '없음' : _connectedRegions.join(', ')}', 
                        style: const TextStyle(fontSize: 16, color: Colors.black87)),
                  ],
                ),
              ),
            ),
          ),
          if (_selectedReportId != null)  // 사건 상세 패널은 선택된 사건이 있을 때만 화면 우측에 표시
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
            child: AdminDashboardList(  // 사건 목록 패널은 _isReportListOpen이 true일 때만 화면 우측에 표시
              onClose: _toggleReportList,
              reports: _reports.values.toList(),
              onReportTap: (reportId) {
                setState(() {
                  _selectedReportId = reportId;
                  _isReportListOpen = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
