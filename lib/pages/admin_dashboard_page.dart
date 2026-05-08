import 'dart:async'; // Timer 기능을 사용하기 위해 추가
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kIsWeb을 사용하기 위해 추가

import 'package:web/web.dart' as web; // 브라우저의 HTML DOM(div 등)을 조작하기 위해 추가
import 'dart:js_interop' as js; // Dart 코드에서 JavaScript 변수나 함수를 직접 호출하기 위해 추가
import 'dart:js_interop_unsafe'; // JS 객체의 속성에 동적으로 접근하기 위해 추가
import 'dart:ui_web' as ui_web; // 플러터 웹 화면 안에 HTML 요소를 등록하기 위해 추가

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  // HtmlElementView와 실제 생성할 HTML div 요소를 연결해주는 고유 식별자(ID)
  final String _viewId = 'naver-map-web-view'; 

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

        // 플러터가 위에서 만든 div를 화면(DOM)에 완전히 그릴 때까지 기다린 후 지도를 띄움
        _waitForMapDivAndInitialize(div);

        // 생성된 div 요소를 플러터 프레임워크에 반환하여 렌더링합니다.
        return div;
      });
    }
  }

  /// HTML 요소 렌더링 대기 (경쟁 상태 방지)
  /// 컴퓨터 성능이나 네트워크에 따라 HTML div가 화면에 그려지는 속도가 다를 수 있음
  /// div가 존재하지 않는데 지도를 띄우려 하면 에러가 발생하므로, 확실히 그려졌는지 확인하는 함수
  void _waitForMapDivAndInitialize(web.HTMLDivElement div) {
    // 0.05초(50ms) 간격으로 화면을 계속 확인
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      // 브라우저 문서 전체에서 id가 'map'인 요소를 찾음
      final element = web.document.getElementById('map');

      // 요소가 찾아졌다면 (화면에 div가 성공적으로 그려졌다면)
      if (element != null) {
        timer.cancel(); // 더 이상의 확인 작업(타이머)을 중지
        _initializeNaverMap(div); // 안전하게 네이버 지도 초기화를 시작
      }
    });
  }

  /// 네이버 지도 객체 생성 및 JS 연동
  /// dart:js_interop을 활용하여 index.html에 추가된 네이버 지도 JS API를 호출
  void _initializeNaverMap(web.HTMLDivElement div) {
    // 브라우저의 전역 객체(window)에서 'naver' 객체를 가져옴
    final naver = js.globalContext['naver'] as js.JSObject?;
    
    // index.html에 네이버 지도 스크립트가 정상적으로 로드되었는지 확인
    if (naver != null) {
      // naver.maps 객체에 접근
      final maps = naver['maps'] as js.JSObject;

      // 중심 좌표 설정 (광운대학교)
      final center = maps.callMethod('LatLng'.toJS, 37.6194.toJS, 127.0598.toJS);
      
      // 지도의 초기 옵션(줌 레벨, 중심 좌표 등)을 JS 객체 형태로 변환
      final mapOptions = {
        'center': center,
        'zoom': 13.toJS,
      }.jsify();

      // JS의 "new naver.maps.Map(div, options)"를 실행하는 것과 동일한 코드
      final mapConstructor = maps['Map'] as js.JSFunction;
      final mapInstance = mapConstructor.callAsConstructor(div as js.JSAny, mapOptions as js.JSAny);
      
      // 추후 WebSocket으로 현장 경찰관의 위치를 수신했을 때 지도를 제어(마커 찍기 등)할 수 있도록,
      // 생성된 지도 객체를 전역 변수(window.adminMap)로 임시 저장
      js.globalContext['adminMap'] = mapInstance;
    } else {
      debugPrint('⚠️ [Error] 네이버 지도 스크립트(index.html)를 찾을 수 없습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // [상단 앱바] 관리자 페이지(상황실) 스타일의 어두운 UI 적용
      appBar: AppBar(
        title: const Text(
          'POL APP - 종합 상황실 대시보드', 
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        backgroundColor: const Color(0xFF1E293B), 
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          // 전체 무전 버튼 (향후 백엔드 WebSocket 연결을 통해 전체 방송 기능 구현 예정)
          TextButton.icon(
            onPressed: () {
              // TODO: 전체 관할 구역에 긴급 무전(이벤트)을 전송하는 로직 추가
            },
            icon: const Icon(Icons.campaign, color: Colors.redAccent),
            label: const Text('전체 긴급 무전', style: TextStyle(color: Colors.white)),
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
          // [레이어 1: 지도 영역] 화면 전체를 꽉 채우는 배경
          Positioned.fill(
            child: kIsWeb 
                // 웹 환경에서는 우리가 위에서 정의한 HTML 뷰(_viewId)를 렌더링
                ? HtmlElementView(viewType: _viewId)
                // 모바일 환경에서 잘못 호출되었을 경우를 대비한 안전 장치
                : const Center(child: Text('이 페이지는 웹 환경에서만 지원됩니다.')),
          ),

          // [레이어 2: 실시간 현황판 오버레이] 지도 좌측 상단에 떠 있는 상황 요약 카드
          Positioned(
            top: 24,
            left: 24,
            child: Card(
              elevation: 8, // 카드에 그림자 효과 부여
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
          )
        ],
      ),
    );
  }
}
