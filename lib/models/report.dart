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
    this.createdBy,
    this.closedBy,
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
  final int? createdBy;
  final int? closedBy;
  final ReportStatus status;

  // 백엔드 /reports 응답의 result 항목을 앱 내부 모델로 변환한다.
  // 현재 백엔드는 id를 숫자로 반환하므로 프론트에서는 문자열로 통일해서 관리한다.
  factory Report.fromJson(Map<String, dynamic> json) {
    final latitude = _readDouble(json['latitude']);
    final longitude = _readDouble(json['longitude']);

    return Report(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'LOW',
      lat: latitude,
      lng: longitude,
      status: _statusFromJson(json['status']),
      createdBy: _readIntOrNull(json['createdBy']),
      closedBy: _readIntOrNull(json['closedBy']),
      createdAt: _readDateTimeOrNow(json['createdAt']),
      closedAt: _readDateTimeOrNull(json['closedAt']),
    );
  }

  // 사건 생성 API는 createdBy를 세션에서 읽으므로 프론트는 사건 내용과 좌표만 보낸다.
  Map<String, dynamic> toCreateJson() {
    return {
      'title': title,
      'description': description,
      'severity': severity,
      'latitude': lat,
      'longitude': lng,
    };
  }

  // 사건 종료 시 기존 접수 정보는 유지하고 상태와 종료 시간만 갱신한다.
  Report copyWith({
    DateTime? closedAt,
    int? closedBy,
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
      createdBy: createdBy,
      closedBy: closedBy ?? this.closedBy,
      status: status ?? this.status,
    );
  }

  static ReportStatus _statusFromJson(Object? value) {
    return value?.toString().toUpperCase() == 'CLOSED'
        ? ReportStatus.closed
        : ReportStatus.open;
  }

  static double _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _readIntOrNull(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime _readDateTimeOrNow(Object? value) {
    return _readDateTimeOrNull(value) ?? DateTime.now();
  }

  static DateTime? _readDateTimeOrNull(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    if (text.isEmpty || text == 'null') return null;
    return DateTime.tryParse(text);
  }
}
