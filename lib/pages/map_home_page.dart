import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

const NLatLng _defaultTarget = NLatLng(37.6507, 127.2936);

class MapHomePage extends StatefulWidget {
  const MapHomePage({super.key});

  @override
  State<MapHomePage> createState() => _MapHomePageState();
}

class _MapHomePageState extends State<MapHomePage> {
  static const NCameraPosition _initialCameraPosition = NCameraPosition(
    target: _defaultTarget,
    zoom: 15,
  );

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

  bool _isMapLoaded = false;

  @override
  Widget build(BuildContext context) {
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
              onMapReady: _onMapReady,
              onMapLoaded: () {
                if (!mounted) return;
                setState(() {
                  _isMapLoaded = true;
                });
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _isMapLoaded ? '주변 치안 정보' : '지도를 불러오는 중...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
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
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
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
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4D9E2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '현재 지역 브리핑',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        '지도를 움직이면서 아래 패널을 함께 올려 상세 정보를 확인하세요.',
                                        style: TextStyle(
                                          color: Color(0xFF5B6472),
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F6FB),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Column(
                                    children: [
                                      Text(
                                        '3곳',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        '주변 알림',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                      ),
                    ),
                    SliverList.separated(
                      itemCount: _places.length,
                      itemBuilder: (context, index) {
                        final place = _places[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _PlaceCard(place: place),
                        );
                      },
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

  Future<void> _onMapReady(NaverMapController controller) async {
    final marker = NMarker(
      id: 'city-hall',
      position: _defaultTarget,
      caption: const NOverlayCaption(text: 'POL APP'),
    );

    await controller.addOverlay(marker);
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place});

  final _PlacePreview place;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EEF9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  place.category,
                  style: const TextStyle(
                    color: Color(0xFF2457C5),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                place.distance,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            place.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            place.description,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlacePreview {
  const _PlacePreview({
    required this.name,
    required this.category,
    required this.distance,
    required this.description,
  });

  final String name;
  final String category;
  final String distance;
  final String description;
}
