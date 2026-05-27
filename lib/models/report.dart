enum ReportStatus {
  open,
  closed,
}
// 사건 모델 클래스: 사건의 기본 정보와 상태를 담는 데이터 구조
class Report {
  const Report({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.lat,
    required this.lng,
    required this.createdAt,
    this.closedAt,
    this.status = ReportStatus.open,
  });
  // 사건의 고유 ID, 제목, 설명, 심각도, 위치 정보, 생성 및 종료 시간, 그리고 현재 상태를 포함한다.
  final String id;
  final String title;
  final String description;
  final String severity;
  final double lat;
  final double lng;
  final DateTime createdAt;
  final DateTime? closedAt;
  final ReportStatus status;

  // 사건 종료 시 기존 접수 정보는 유지하고 상태와 종료 시간만 갱신한다.
  Report copyWith({
    DateTime? closedAt,
    ReportStatus? status,
  }) {
    return Report(
      id: id,
      title: title,
      description: description,
      severity: severity,
      lat: lat,
      lng: lng,
      createdAt: createdAt,
      closedAt: closedAt ?? this.closedAt,
      status: status ?? this.status,
    );
  }
}
