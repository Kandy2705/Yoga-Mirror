class PoseFeedbackService {
  List<String> buildFeedback({
    required double score,
    required bool userDetected,
    required bool poseDetectionSupported,
    required Map<String, double> angleDiffs,
    String bodyStatus = 'none',
  }) {
    if (!poseDetectionSupported) {
      return ['Chỉ hỗ trợ chấm điểm trên iOS/Android'];
    }

    if (!userDetected) {
      // Don't show the initial "stand in frame" instruction — keep UI clean.
      return [];
    }

    if (bodyStatus == 'no_torso') {
      return [
        'Vui lòng đặt điện thoại xa hơn để thấy toàn thân.',
        'Cần thấy vai, hông, gối và chân để chấm điểm.',
      ];
    }

    if (bodyStatus == 'partial') {
      return ['Chưa thấy đủ chân và gối.', 'Lùi xa để camera thấy toàn thân.'];
    }

    if (score > 85) {
      return ['Tốt lắm, giữ nguyên tư thế'];
    }

    if (angleDiffs.isEmpty) {
      return ['Điều chỉnh tư thế cho giống mẫu hơn'];
    }

    final sorted = angleDiffs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final suggestions = <String>[];

    for (final entry in sorted.take(3)) {
      final hint = _hintForJoint(entry.key, entry.value);
      if (hint != null && !suggestions.contains(hint)) {
        suggestions.add(hint);
      }
    }

    if (suggestions.isEmpty) {
      suggestions.add('Điều chỉnh tư thế cho giống mẫu hơn');
    }

    return suggestions.take(3).toList();
  }

  String? _hintForJoint(String joint, double diff) {
    if (diff < 12) {
      return null;
    }

    if (joint.contains('Elbow') || joint.contains('Shoulder')) {
      return 'Điều chỉnh tay gần giống mẫu hơn';
    }
    if (joint.contains('Hip') || joint.contains('Knee')) {
      return 'Điều chỉnh chân và gối theo dáng mẫu';
    }
    return 'Giữ thân người thẳng hơn';
  }
}
