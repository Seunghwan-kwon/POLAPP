// ignore: library_prefixes
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../models/officer_profile.dart';
import '../models/police_facility.dart';
import '../models/safety_status.dart';
import '../services/police_marker_service.dart';
import 'map_bottom_panel.dart';
import 'setting_page.dart';

// GPS 수신 지연 또는 실패 시 지도가 보여줄 기본 좌표 (광운대학교)
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

  // 서버에서 받은 JSON을 객체로 변환
  factory RadioMessage.fromJson(Map<String, dynamic> json) {
    return RadioMessage(
      officerId: json['officerId'],
      region: json['region'] ?? 'UNKNOWN', 
      message: json['message'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

// 지도의 초기 카메라 시점 설정
class _MapHomePageState extends State<MapHomePage> {
  static const NCameraPosition _initialCameraPosition = NCameraPosition(
    target: _defaultTarget,
    zoom: 15,
  );

  bool _isMapLoaded = false;
  bool _isBriefingVisible = false;
  bool _isVoiceRecognitionEnabled = false;
  bool _isRadioDialogOpen = false;
  SafetyStatus _safetyStatus = SafetyStatus.waiting;
  PoliceFacility? _selectedFacility;

  static const OfficerProfile _officerProfile = OfficerProfile(
    name: '홍길동',
    rank: '순경',
  );

  NaverMapController? _mapController; // 네이버 지도 조작을 위한 컨트롤러 인스턴스
  StreamSubscription<Position>? _positionStream;  // 실시간 기기 위치 업데이트를 감지하는 스트림 구독 객체
  NMarker? _myLocationMarker; // 현재 사용자의 위치를 지도 위에 표시하는 마커

  // 웹소켓 및 동료 마커 관리를 위한 변수
  IO.Socket? _socket; // 서버와 통신할 소켓 객체
  final String _myOfficerId = 'P-1001'; // 내 임시 경찰관 ID (나중에 로그인 정보로 교체)
  final Map<String, NMarker> _colleagueMarkers = {};  // 다른 경찰관들의 마커를 관리할 딕셔너리
  final PoliceMarkerService _policeMarkerService = PoliceMarkerService();

  // 메시지 내역을 저장할 리스트
  List<RadioMessage> _radioLogs = [];

  @override
  void initState() {
    super.initState();
    _startLocationTracking(); // 화면 로딩과 동시에 백그라운드에서 기기 위치 추적 시작
    _connectWebSocket();  // 앱 동작 시 소켓 연결
  }

  @override
  void dispose() {
    _positionStream?.cancel();  // 메모리 누수 및 백그라운드 배터리 소모를 방지하기 위해 화면 종료 시 GPS 스트림 해제
    _socket?.dispose();// 화면 종료 시 통신도 종료
    _policeMarkerService.dispose();
    super.dispose();
  }

// 웹소켓 연결 및 이벤트 리스너 설정
  void _connectWebSocket() {
    // 서버 주소 설정
    final String serverUrl = const String.fromEnvironment('WS_SERVER_URL');

    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    // 서버 연결 성공 시 내가 접속했다는 사실을 서버에 알림
    _socket?.onConnect((_) {
      debugPrint('WebSocket connected');
      _socket?.emit('join', {
        'officerId': _myOfficerId,
        'region': 'SEOUL_NOWON' // 관할 지역 추가
      });
    });

    // 서버 연결 실패 시 에러 로그 출력
    _socket?.onConnectError(
      (error) => debugPrint('WebSocket connect error: $error'),
    );

    // 서버로부터 다른 경찰관의 위치 데이터를 수신했을 때
    _socket?.on('updateColleagueLocation', (data) {
      final String officerId = data['officerId'].toString();
      final double lat = (data['latitude'] as num).toDouble();
      final double lng = (data['longitude'] as num).toDouble();
      _updateColleagueMarker(officerId, NLatLng(lat, lng));
    });

    // 서버로부터 다른 경찰관의 메시지를 수신했을 때
    _socket?.on('receiveRadioMessage', (data) {
      // 현재 맵 화면이 띄워져 있을 때만 UI 업데이트를 진행
      if (!mounted) return; 

      final newMessage = RadioMessage.fromJson(data);
      
      setState(() {
        _radioLogs.insert(0, newMessage); // 최신 메시지가 위로 오게 저장
      });

      // 팝업 알림 띄우기 (ScaffoldMessenger 사용)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("[${newMessage.region}] ${newMessage.officerId}: ${newMessage.message}"),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating, // 지도 위로 띄우기
          margin: const EdgeInsets.only(bottom: 100, left: 20, right: 20), // 위치 조정
        ),
      );
    });

    // 서버와 연결이 끊겼을 때
    _socket?.onDisconnect((_) => debugPrint('WebSocket disconnected'));

    // 세팅 완료 후 연결 시작
    _socket?.connect();
  }

// 동료 마커를 지도에 갱신하는 함수
  void _updateColleagueMarker(String officerId, NLatLng latLng) {
    if (_mapController == null || officerId == _myOfficerId) return;

    setState(() {
      if (_colleagueMarkers.containsKey(officerId)) {
        // 이미 지도에 있는 동료면 위치만 이동
        _colleagueMarkers[officerId]!.setPosition(latLng);
      } else {
        // 처음 보는 동료면 새로운 마커 생성해서 지도에 추가
        final newMarker = NMarker(
          id: officerId,
          position: latLng,
          iconTintColor: Colors.blue, // 내 마커와 색상으로 구분 (파란색)
          caption: NOverlayCaption(text: officerId),  // 마커 아래에 ID 표시
        );
        _colleagueMarkers[officerId] = newMarker;
        _mapController!.addOverlay(newMarker);
      }
    });
  }

  // 기기의 위치 권한을 확인하고, 실시간 위치 추적을 초기화하는 메서드
  Future<void> _startLocationTracking() async {
    // 기기 자체의 위치 서비스 활성화 여부 확인
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    // 앱의 위치 권한 상태 확인 및 거부 시 권한 요청 팝업 호출
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // GPS 통신 대기 시간을 줄이기 위해, OS가 마지막으로 기억하는 캐시된 위치를 먼저 불러와 지도를 즉시 이동시킴
    final Position? initialPosition = await Geolocator.getLastKnownPosition();
    if (initialPosition != null) {
      _updateMyLocationOnMap(initialPosition, isInitial: true);
    }

    // 지정된 간격(5미터) 이상 이동할 때마다 지속적으로 좌표를 수신하는 스트림 활성화
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      _updateMyLocationOnMap(position, isInitial: false);
    });
  }

  // 수신된 GPS 좌표를 바탕으로 마커를 갱신하고 카메라를 이동시키는 메서드
  void _updateMyLocationOnMap(Position position, {required bool isInitial}) {
    if (_mapController == null) return;

    final latLng = NLatLng(position.latitude, position.longitude);

    // 마커가 맵에 없다면 새로 생성하고, 이미 존재한다면 좌표값만 갱신 (화면 깜빡임 방지)
    if (_myLocationMarker == null) {
      _myLocationMarker = NMarker(id: 'my-location', position: latLng);
      _mapController!.addOverlay(_myLocationMarker!);
    } else {
      _myLocationMarker!.setPosition(latLng);
    }

    // 카메라 이동 객체 생성
    final cameraUpdate = NCameraUpdate.withParams(target: latLng);

    // 최초 위치 탐색 시에는 애니메이션 없이 즉시 카메라를 이동시키고,
    // 이후 실시간 이동 시에는 부드럽게 추적하도록 트랜지션 효과 적용
    cameraUpdate.setAnimation(
      animation: isInitial ? NCameraAnimation.none : NCameraAnimation.easing,
      duration:
          isInitial ? Duration.zero : const Duration(milliseconds: 300),
    );

    // 내 위치가 지도에 갱신될 때마다 서버에 전송
    if (_socket != null && _socket!.connected) {
      _socket!.emit('sendMyLocation', {
        'officerId': _myOfficerId,
        'latitude': position.latitude,
        'longitude': position.longitude,
      });
    }

    _mapController!.updateCamera(cameraUpdate);
  }

  // 메시지를 서버로 전송하는 함수
  void _sendRadioMessage(String text) {
    if (text.trim().isEmpty) return; // 빈 메시지 방지

    if (_socket != null && _socket!.connected) {
      final messageData = {
        'officerId': _myOfficerId,
        'region': 'SEOUL_NOWON',
        'message': text,
        'timestamp': DateTime.now().toIso8601String(), // 현재 시간을 표준 문자열로 변환
      };
      
      _socket!.emit('sendRadioMessage', messageData);
      debugPrint('메시지 전송 완료: $text');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서버와 연결되어 있지 않습니다.')),
      );
    }
  }

  // 메시지 입력창을 띄우는 함수
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
              Text('전체 메시지 전파', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: TextField(
            controller: messageController,
            decoration: const InputDecoration(
              hintText: '전파할 내용을 입력하세요.',
              border: OutlineInputBorder(),
            ),
            autofocus: true, // 창이 뜨자마자 키보드 올라오게 설정
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
                Navigator.pop(context); // 전송 후 창 닫기
              },
              child: const Text('전파하기', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ).then((_) {
      // 전송, 취소, 혹은 바깥 화면 터치로 창이 닫히면 무조건 실행
      setState(() {
        _isRadioDialogOpen = false; // 창이 닫히면 다시 하얀색으로 복구
      });
    });
  }

  // 지도를 한 단계 확대하는 외부 컨트롤 메서드
  void _zoomIn() {
    _mapController?.updateCamera(NCameraUpdate.zoomIn());
  }

  // 지도를 한 단계 축소하는 외부 컨트롤 메서드
  void _zoomOut() {
    _mapController?.updateCamera(NCameraUpdate.zoomOut());
  }

  void _nextSafetyStatus() {
    setState(() {
      _safetyStatus = _safetyStatus.next;
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SettingPage()),
    );
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

  // 경찰서, 지구대 마커 클릭 캡슐화에 따른 호출
  Future<void> _onMapReady(NaverMapController controller) async {
    await _policeMarkerService.addPoliceFacilityMarkers(
      context: context,
      controller: controller,
      onFacilityTap: _onPoliceFacilityTap,
    );
  }

  void _onPoliceFacilityTap(PoliceFacility facility) {
    setState(() {
      _selectedFacility = facility;
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

  @override
  Widget build(BuildContext context) {
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: Stack(
        children: [
          // 1. 최하단 배경: 네이버 지도 렌더링 영역
          Positioned.fill(
            child: NaverMap(
              options: const NaverMapViewOptions(
                mapType: NMapType.navi,
                nightModeEnable: true,
                initialCameraPosition: _initialCameraPosition,
                locationButtonEnable: true,
              ),
              onMapReady: (controller) {
                // 맵 초기화 완료 시 컨트롤러 인스턴스 보관 및 초기 마커 설정
                _mapController = controller;
                _onMapReady(controller);
              },
              onMapLoaded: () {
                if (!mounted) return;
                setState(() {
                  _isMapLoaded = true;
                });
              },
            ),
          ),
          // 2. 좌측 상단: 현재 맵 로딩 상태 및 출동 상태 표시
          // 우측 설정 버튼 및 음성 인식 On/Off 버튼
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
                            color: (_isMapLoaded
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
                          backgroundColor: _isRadioDialogOpen ? Colors.blueAccent : Colors.white,
                          child: Icon(
                            Icons.campaign,
                            color: _isRadioDialogOpen ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 3. 우측 하단: 지도 줌 인/아웃 컨트롤 FAB (Floating Action Button) 영역
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
            bottom: 220,  // 하단 DraggableScrollableSheet와 겹치지 않도록 높이 확보
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
          // 4. 최하단 패널: 드래그 가능한 주변 정보 브리핑 시트
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
                );
              },
            ),
        ],
      ),
    );
  }
}
