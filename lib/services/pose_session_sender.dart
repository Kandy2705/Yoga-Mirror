import 'dart:convert';

import 'package:flutter/services.dart';

import '../network/pose_websocket_client.dart';

class PoseSessionSender {
  PoseSessionSender(this.socket);

  final PoseWebSocketClient socket;

  bool _cancelled = false;

  Future<void> sendAsset({
    required String assetPath,
  }) async {
    _cancelled = false;

    final source = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(source);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON cap cao nhat phai la object.');
    }

    final rawFrames = decoded['frames'];

    if (rawFrames is! List || rawFrames.isEmpty) {
      throw const FormatException('JSON khong co mang frames.');
    }

    final frames = rawFrames
        .whereType<Map>()
        .map((frame) => Map<String, dynamic>.from(frame))
        .toList(growable: false);

    if (frames.isEmpty) {
      throw const FormatException('Khong co frame hop le.');
    }

    for (var index = 0; index < frames.length; index++) {
      if (_cancelled) return;

      socket.sendFrame(frames[index]);

      if (index < frames.length - 1) {
        final delay = _calculateDelay(
          current: frames[index],
          next: frames[index + 1],
        );
        await Future<void>.delayed(delay);
      }
    }

    if (!_cancelled) {
      socket.sendDone();
    }
  }

  void cancel() {
    _cancelled = true;
  }

  Duration _calculateDelay({
    required Map<String, dynamic> current,
    required Map<String, dynamic> next,
  }) {
    final currentMs = _readTimestamp(current);
    final nextMs = _readTimestamp(next);

    if (currentMs != null && nextMs != null) {
      final difference = nextMs - currentMs;
      if (difference >= 16 && difference <= 1000) {
        return Duration(milliseconds: difference);
      }
    }

    return const Duration(milliseconds: 100);
  }

  int? _readTimestamp(Map<String, dynamic> frame) {
    final value = frame['timestamp_ms'] ?? frame['timestampMs'];
    if (value is num) {
      return value.round();
    }
    return null;
  }
}
