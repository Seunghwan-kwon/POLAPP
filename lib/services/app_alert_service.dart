import 'dart:async';

import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
OverlayEntry? _activeAlertEntry;
Timer? _activeAlertTimer;

void showTopAppAlert({
  required String message,
  Color backgroundColor = const Color(0xFFB42318),
}) {
  final overlay = appNavigatorKey.currentState?.overlay;
  if (overlay == null) return;

  _activeAlertTimer?.cancel();
  if (_activeAlertEntry?.mounted == true) {
    _activeAlertEntry!.remove();
  }

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  _activeAlertEntry = entry;
  _activeAlertTimer = Timer(const Duration(seconds: 4), () {
    if (entry.mounted) {
      entry.remove();
    }
    if (identical(_activeAlertEntry, entry)) {
      _activeAlertEntry = null;
      _activeAlertTimer = null;
    }
  });
}
