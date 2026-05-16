import 'dart:async'; // Timer 기능을 사용하기 위해 추가
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kIsWeb을 사용하기 위해 추가

import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:web/web.dart' as web; // 브라우저의 HTML DOM(div 등)을 조작하기 위해 추가
import 'dart:js_interop' as js; // Dart 코드에서 JavaScript 변수나 함수를 직접 호출하기 위해 추가
import 'dart:js_interop_unsafe'; // JS 객체의 속성에 동적으로 접근하기 위해 추가
import 'dart:ui_web' as ui_web; // 플러터 웹 화면 안에 HTML 요소를 등록하기 위해 추가
import 'admin_dashboard_list.dart'; // 사건 내용 리스트

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  // HtmlElementView와 실제 생성할 HTML div 요소를 연결해주는 고유 식별자(ID)
  final String _viewId = 'naver-map-web-view'; 

  io.Socket? _socket;

  // 경찰관 ID를 Key로, 자바스크립트 마커 객체를 Value로 저장하는 딕셔너리
  final Map<String, js.JSObject> _officerMarkers = {};

  // 상태 관리 플래그
  bool _isReportListOpen = false;

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

        // 생성된 div 요소를 플러터 프레임워크에 반환하여 렌더링합니다.
        return div;
      });
    }
  }

  /// launch.json의 환경 변수를 읽어 HTML에 네이버 지도 스크립트를 동적으로 삽입
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
    } else {
      debugPrint('⚠️ [Error] 네이버 지도 스크립트 로드 실패');
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
      
      // [관리자(ADMIN) 권한으로 세션 방(Room)에 입장
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

    // 2. 서버로부터 현장 경찰관의 실시간 좌표 데이터를 수신했을 때 (`updateColleagueLocation`)
    _socket?.on('updateColleagueLocation', (data) {
      debugPrint('[Debug] 위치 데이터 수신함: $data');
      
      try {
        // 서버에서 받아온 JSON Object 보따리에서 개별 데이터 파싱
        final String officerId = data['officerId'].toString();
        final double lat = (data['latitude'] as num).toDouble();
        final double lng = (data['longitude'] as num).toDouble();
        
        // 파싱된 데이터를 기반으로 자바스크립트 지도 위에 마커를 투영하는 함수 호출
        _updateOfficerMarkerJS(officerId, lat, lng);
      } catch (e) {
        debugPrint('[Debug] 데이터 파싱 에러: $e');
      }
    });

    // 3. 현장 경찰관의 긴급 무전 메시지 수신 시 처리
    _socket?.on('receiveRadioMessage', (data) {
      if (!mounted) return;

      final String officerId = data['officerId'].toString();
      final String region = data['region'].toString();
      final String message = data['message'].toString();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.campaign, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('[$region] $officerId: $message')),
            ],
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent, 
        ),
      );
    });

    // 설정된 리스너들을 바탕으로 실제 서버 연결 세션을 활성화
    _socket?.connect();
  }

  /// [핵심 로직] dart:js_interop 기술을 활용하여 브라우저 런타임의 네이버 지도 JS 객체를 직접 제어하는 함수
  void _updateOfficerMarkerJS(String officerId, double lat, double lng) {
    // index.html 레이어에 로드된 window.naver 객체와 지도 초기화 시 저장해둔 window.adminMap 객체를 가져옴
    final naver = js.globalContext['naver'] as js.JSObject?;
    final adminMap = js.globalContext['adminMap'] as js.JSObject?;

    // 지도가 아직 화면에 그려지지 않았거나 스크립트 로딩이 누락되었다면 예외 처리 (C++의 Null Check 개념)
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
    }
  }

  void _toggleReportList() {
    setState(() {
      _isReportListOpen = !_isReportListOpen;
    });
  }

  void _showReportAlert() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        Future.delayed(const Duration(seconds: 2), () {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        });

        return const AlertDialog(
          backgroundColor: Color.fromARGB(255, 85, 117, 169),
          content: Text(
            '신고 발생 위치에 마우스를 클릭하세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _socket?.dispose(); // 페이지 종료 시 소켓 연결 해제
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'POLWEB - 종합 상황실 대시보드', 
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        backgroundColor: const Color.fromARGB(255, 85, 117, 169), 
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          Tooltip(
            message: '클릭한 위치에 신고를 접수합니다.',
            child: TextButton.icon(
            onPressed : _showReportAlert,
            icon: const Icon(Icons.crisis_alert, color: Colors.redAccent),
            label: const Text('신고 접수', style: TextStyle(color: Colors.white)),
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
            message: '관할 지역 경찰관에게 메세지를 전파합니다.',
            child : TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.campaign, color: Colors.redAccent),
            label: const Text('전체 긴급 무전', style: TextStyle(color: Colors.white)),
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
              child: const Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('실시간 현장 현황', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 16),
                    Text('👮 활동 중인 경찰관: 12명', style: TextStyle(fontSize: 16, color: Colors.blue)),
                    SizedBox(height: 8),
                    Text('🚨 위협 감지: 1건', style: TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('📡 연결된 채널: 노원구, 도봉구', style: TextStyle(fontSize: 16, color: Colors.black87)),
                  ],
                ),
              ),
            ),
          ),
          if (_isReportListOpen)
          Positioned(
            top: 24,
            right: 24,
            bottom: 24,
            width: 360,
            child: AdminDashboardList(onClose: _toggleReportList,),
          ),
        ],
      ),
    );
  }
}
