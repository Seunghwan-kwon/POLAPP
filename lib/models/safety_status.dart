import 'package:flutter/material.dart';

enum SafetyStatus {
  waiting,
  patrol,
  dispatch,
  handling,
}

extension SafetyStatusData on SafetyStatus {
  String get label {
    switch (this) {
      case SafetyStatus.waiting:
        return '대기';
      case SafetyStatus.patrol:
        return '순찰';
      case SafetyStatus.dispatch:
        return '출동';
      case SafetyStatus.handling:
        return '사건 처리';
    }
  }

  Color get color {
    switch (this) {
      case SafetyStatus.waiting:
        return const Color(0xFF16A34A);
      case SafetyStatus.patrol:
        return const Color(0xFF2563EB);
      case SafetyStatus.dispatch:
        return const Color(0xFFF97316);
      case SafetyStatus.handling:
        return const Color(0xFFDC2626);
    }
  }

  IconData get icon {
    switch (this) {
      case SafetyStatus.waiting:
        return Icons.shield_outlined;
      case SafetyStatus.patrol:
        return Icons.directions_walk;
      case SafetyStatus.dispatch:
        return Icons.local_police_outlined;
      case SafetyStatus.handling:
        return Icons.report_problem_outlined;
    }
  }

  SafetyStatus get next {
    final nextIndex = (index + 1) % SafetyStatus.values.length;
    return SafetyStatus.values[nextIndex];
  }
}
