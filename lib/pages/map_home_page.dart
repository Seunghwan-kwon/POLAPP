import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../models/safety_status.dart';
import 'setting_page.dart';

// GPS 수신 지연 또는 실패 시 지도가 보여줄 기본 좌표 (광운대학교)
const NLatLng _defaultTarget = NLatLng(37.6194, 127.0598);

class MapHomePage extends StatefulWidget {
  const MapHomePage({super.key});

  @override
  State<MapHomePage> createState() => _MapHomePageState();
}

class _MapHomePageState extends State<MapHomePage> {
  // 지도의 초기 카메라 시점 설정
  static const NCameraPosition _initialCameraPosition = NCameraPosition(
    target: _defaultTarget,
    zoom: 15,
  );

  // 하단 바텀 시트에 표시될 치안 및 순찰 관련 임시 데이터 리스트
  final List<_PlacePreview> _places = const [
    _PlacePreview(
      name: '중랑천 산책로',
      category: '순찰 추천',
      distance: '도보 4분',
      description: '야간 이동이 잦은 구간입니다. 신고 이력과 CCTV 위치를 함께 확인해 보세요.',
    ),
    _PlacePreview(
      name: '망우역 1번 출구',
      category: '혼잡 지역',
      distance: '도보 7분',
      description: '퇴근 시간 유동인구가 높은 지점입니다. 주변 골목 진입 동선 확인에 적합합니다.',
    ),
    _PlacePreview(
      name: '면목초 사거리',
      category: '교통 주의',
      distance: '차량 3분',
      description: '불법 주정차 민원이 자주 접수되는 구역입니다.',
    ),
  ];

  // 지도 로딩 상태 관리
  bool _isMapLoaded = false;
  SafetyStatus _safetyStatus = SafetyStatus.waiting;
  
  // 네이버 지도 조작을 위한 컨트롤러 인스턴스
  NaverMapController? _mapController; 
  // 실시간 기기 위치 업데이트를 감지하는 스트림 구독 객체
  StreamSubscription<Position>? _positionStream; 
  // 현재 사용자의 위치를 지도 위에 표시하는 마커
  NMarker? _myLocationMarker; 

  @override
  void initState() {
    super.initState();
    // 화면 로딩과 동시에 백그라운드에서 기기 위치 추적 시작
    _startLocationTracking(); 
  }

  @override
  void dispose() {
    // 메모리 누수 및 백그라운드 배터리 소모를 방지하기 위해 화면 종료 시 GPS 스트림 해제
    _positionStream?.cancel();
    super.dispose();
  }

  // 기기의 위치 권한을 확인하고, 실시간 위치 추적을 초기화하는 메서드
  Future<void> _startLocationTracking() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 기기 자체의 위치 서비스 활성화 여부 확인
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    // 앱의 위치 권한 상태 확인 및 거부 시 권한 요청 팝업 호출
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // GPS 통신 대기 시간을 줄이기 위해, OS가 마지막으로 기억하는 캐시된 위치를 먼저 불러와 지도를 즉시 이동시킴
    Position? initialPosition = await Geolocator.getLastKnownPosition();
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
    debugPrint('위치 정보 업데이트: $latLng');

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
      duration: isInitial ? Duration.zero : const Duration(milliseconds: 300),
    );
    
    _mapController!.updateCamera(cameraUpdate);
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

  @override
  Widget build(BuildContext context) {
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
          
          // 2. 좌측 상단: 현재 맵 로딩 상태 및 치안 정보 안내 오버레이
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: _isMapLoaded ? _nextSafetyStatus : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: (_isMapLoaded ? _safetyStatus.color : Colors.black).withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isMapLoaded ? _safetyStatus.icon : Icons.map_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isMapLoaded ? '상태 · ${_safetyStatus.label}' : '지도를 불러오는 중...',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topRight,
                child: FloatingActionButton.small(
                  heroTag: 'btn_settings',
                  onPressed: _openSettings,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.settings, color: Colors.black87),
                ),
              ),
            ),
          ),

          // 3. 우측 하단: 지도 줌 인/아웃 컨트롤 FAB (Floating Action Button) 영역
          Positioned(
            right: 16,
            bottom: 220, // 하단 DraggableScrollableSheet와 겹치지 않도록 높이 확보
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

          // 4. 최상단 하단 패널: 드래그 가능한 주변 정보 브리핑 시트
          DraggableScrollableSheet(
            initialChildSize: 0.18,
            minChildSize: 0.12,
            maxChildSize: 0.78,
            snap: true,
            snapSizes: const [0.18, 0.42, 0.78],
            builder: (context, scrollController) {
              return DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(color: Color(0x26000000), blurRadius: 20, offset: Offset(0, -4)),
                  ],
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 44, height: 5,
                            decoration: BoxDecoration(color: const Color(0xFFD4D9E2), borderRadius: BorderRadius.circular(999)),
                          ),
                          const SizedBox(height: 16),
                          _buildHeader(context),
                          const SizedBox(height: 18),
                        ],
                      ),
                    ),
                    // 재사용 가능한 풀링 방식으로 리스트 데이터 렌더링
                    SliverList.separated(
                      itemCount: _places.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _PlaceCard(place: _places[index]),
                      ),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 28)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // 바텀 시트 상단의 브리핑 타이틀 영역 컴포넌트
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('현재 지역 브리핑', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('지도를 움직이면서 아래 패널을 함께 올려 상세 정보를 확인하세요.',
                    style: TextStyle(color: Color(0xFF5B6472), height: 1.4)),
              ],
            ),
          ),
          _buildBadge(),
        ],
      ),
    );
  }

  // 바텀 시트 타이틀 우측의 정보 카운트 뱃지 컴포넌트
  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFF3F6FB), borderRadius: BorderRadius.circular(16)),
      child: const Column(
        children: [
          Text('3곳', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          SizedBox(height: 2),
          Text('주변 알림', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  // 맵 컨트롤러가 준비된 직후 호출되는 콜백. 초기 데이터 렌더링을 담당.
  Future<void> _onMapReady(NaverMapController controller) async {
    final marker = NMarker(
      id: 'city-hall',
      position: _defaultTarget,
      caption: const NOverlayCaption(text: 'POL APP'),
    );
    await controller.addOverlay(marker);
  }
}

// ─── 데이터 모델 및 리스트 아이템 UI 컴포넌트 ───

// 바텀 시트 내부 리스트에 표시될 개별 장소 카드 위젯
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place});
  final _PlacePreview place;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFE8EEF9), borderRadius: BorderRadius.circular(999)),
                child: Text(place.category, style: const TextStyle(color: Color(0xFF2457C5), fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              const Spacer(),
              Text(place.distance, style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Text(place.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(place.description, style: const TextStyle(color: Color(0xFF4B5563), height: 1.5)),
        ],
      ),
    );
  }
}

// 장소 정보를 담는 데이터 모델 클래스 (프리뷰 용도)
class _PlacePreview {
  const _PlacePreview({
    required this.name, 
    required this.category, 
    required this.distance, 
    required this.description
  });
  
  final String name, category, distance, description;
}
