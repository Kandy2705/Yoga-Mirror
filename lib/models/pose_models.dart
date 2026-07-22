import 'dart:math' as math;
import 'dart:ui';

class PoseLandmark {
  const PoseLandmark({
    required this.name,
    required this.xNorm,
    required this.yNorm,
    required this.visibility,
  });

  final String name;
  final double xNorm;
  final double yNorm;
  final double visibility;

  factory PoseLandmark.fromJson(Map<String, dynamic> json) {
    final rawName = json['name']?.toString();
    final index = (json['index'] as num?)?.round();
    final name = _canonicalLandmarkName(rawName, index);
    final x = json['xNorm'] ?? json['x'];
    final y = json['yNorm'] ?? json['y'];

    if (name == null || x is! num || y is! num) {
      throw const FormatException('Landmark thiếu name/index hoặc tọa độ x/y.');
    }

    return PoseLandmark(
      name: name,
      xNorm: x.toDouble(),
      yNorm: y.toDouble(),
      visibility: ((json['visibility'] as num?) ??
              (json['score'] as num?) ??
              1)
          .toDouble()
          .clamp(0.0, 1.0)
          .toDouble(),
    );
  }

  static PoseLandmark lerp(PoseLandmark a, PoseLandmark b, double t) {
    return PoseLandmark(
      name: a.name,
      xNorm: _lerpDouble(a.xNorm, b.xNorm, t),
      yNorm: _lerpDouble(a.yNorm, b.yNorm, t),
      visibility: _lerpDouble(a.visibility, b.visibility, t),
    );
  }
}

class PoseFrame {
  const PoseFrame({
    required this.timestampMs,
    required this.frameWidth,
    required this.frameHeight,
    required this.personDetected,
    required this.avgVisibility,
    required this.bboxHeightNorm,
    required this.landmarks,
  });

  final int timestampMs;
  final int frameWidth;
  final int frameHeight;
  final bool personDetected;
  final double avgVisibility;
  final double? bboxHeightNorm;
  final Map<String, PoseLandmark> landmarks;

  factory PoseFrame.fromJson(
    Map<String, dynamic> json, {
    required int defaultWidth,
    required int defaultHeight,
    required double defaultFps,
    required int framePosition,
  }) {
    final poses = json['poses'] as List<dynamic>?;
    final firstPose = poses != null && poses.isNotEmpty
        ? _asMap(poses.first)
        : const <String, dynamic>{};

    final rawLandmarks = (json['landmarks'] as List<dynamic>?) ??
        (firstPose['pose_landmarks'] as List<dynamic>?) ??
        const <dynamic>[];

    final landmarks = <String, PoseLandmark>{};
    for (final raw in rawLandmarks) {
      final map = _asMap(raw);
      if (map.isEmpty) continue;
      try {
        final landmark = PoseLandmark.fromJson(map);
        landmarks[landmark.name] = landmark;
      } on FormatException {
        // Ignore malformed optional landmarks instead of rejecting the video.
      }
    }

    final frameWidth = ((json['frameWidth'] as num?)?.round() ?? defaultWidth)
        .clamp(1, 1000000)
        .toInt();
    final frameHeight = ((json['frameHeight'] as num?)?.round() ?? defaultHeight)
        .clamp(1, 1000000)
        .toInt();

    final timestamp = (json['timestampMs'] as num?)?.round() ??
        (json['timestamp_ms'] as num?)?.round() ??
        ((json['frame_index'] as num?)?.toDouble() ?? framePosition) /
            math.max(defaultFps, 0.001) *
            1000;

    final distanceProxy = _asMap(json['distanceProxy']);
    double? bboxHeightNorm =
        (distanceProxy['bboxHeightNorm'] as num?)?.toDouble();
    final bbox = firstPose['bbox'] as List<dynamic>?;
    if (bboxHeightNorm == null && bbox != null && bbox.length >= 4) {
      final top = bbox[1];
      final bottom = bbox[3];
      if (top is num && bottom is num) {
        bboxHeightNorm = ((bottom.toDouble() - top.toDouble()).abs() /
                frameHeight)
            .clamp(0.01, 2.0)
            .toDouble();
      }
    }

    final avgVisibility = (json['avgVisibility'] as num?)?.toDouble() ??
        _averageVisibility(landmarks.values);

    final explicitDetected = json['personDetected'] as bool?;
    final personDetected = explicitDetected ?? landmarks.isNotEmpty;

    return PoseFrame(
      timestampMs: timestamp.round(),
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      personDetected: personDetected,
      avgVisibility: avgVisibility,
      bboxHeightNorm: bboxHeightNorm,
      landmarks: landmarks,
    );
  }
}

class PoseSample {
  const PoseSample({
    required this.timestampMs,
    required this.frameWidth,
    required this.frameHeight,
    required this.personDetected,
    required this.avgVisibility,
    required this.bboxHeightNorm,
    required this.landmarks,
  });

  final double timestampMs;
  final int frameWidth;
  final int frameHeight;
  final bool personDetected;
  final double avgVisibility;
  final double? bboxHeightNorm;
  final Map<String, PoseLandmark> landmarks;

  PoseLandmark? landmark(String name, {double minimumVisibility = 0.15}) {
    final value = landmarks[name];
    if (value == null || value.visibility < minimumVisibility) return null;
    return value;
  }
}

class PoseSequence {
  PoseSequence({
    required this.schemaVersion,
    required this.sourceName,
    required this.sampleFps,
    required this.frames,
  }) : assert(frames.isNotEmpty, 'Pose sequence must contain frames.');

  final String schemaVersion;
  final String sourceName;
  final double sampleFps;
  final List<PoseFrame> frames;

  int get durationMs => frames.last.timestampMs;

  factory PoseSequence.fromJson(Map<String, dynamic> json) {
    final capture = _asMap(json['capture']);
    final captureParams = _asMap(json['captureParams']);
    final metadata = _asMap(json['metadata']);

    final sampleFps = ((captureParams['sampleFps'] as num?) ??
            (metadata['source_fps'] as num?) ??
            10)
        .toDouble();
    final defaultWidth = ((metadata['image_width'] as num?) ?? 1280).round();
    final defaultHeight = ((metadata['image_height'] as num?) ?? 720).round();

    final rawFrames = json['frames'] as List<dynamic>? ?? const <dynamic>[];
    final frameList = <PoseFrame>[];
    for (var i = 0; i < rawFrames.length; i++) {
      final raw = _asMap(rawFrames[i]);
      if (raw.isEmpty) continue;
      final frame = PoseFrame.fromJson(
        raw,
        defaultWidth: defaultWidth,
        defaultHeight: defaultHeight,
        defaultFps: sampleFps,
        framePosition: i,
      );
      if (frame.landmarks.isNotEmpty) frameList.add(frame);
    }

    frameList.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    if (frameList.isEmpty) {
      throw const FormatException('JSON không chứa frame pose hợp lệ.');
    }

    return PoseSequence(
      schemaVersion: json['schemaVersion']?.toString() ??
          metadata['coordinate_system']?.toString() ??
          'compatible',
      sourceName: capture['model']?.toString() ??
          capture['source']?.toString() ??
          metadata['model']?.toString() ??
          metadata['source']?.toString() ??
          'Pose JSON',
      sampleFps: sampleFps,
      frames: frameList,
    );
  }

  PoseSample sampleAt(double timestampMs) {
    if (timestampMs <= frames.first.timestampMs || frames.length == 1) {
      return _sampleFromFrame(frames.first);
    }
    if (timestampMs >= frames.last.timestampMs) {
      return _sampleFromFrame(frames.last);
    }

    var low = 0;
    var high = frames.length - 1;
    while (low + 1 < high) {
      final mid = (low + high) >> 1;
      if (frames[mid].timestampMs <= timestampMs) {
        low = mid;
      } else {
        high = mid;
      }
    }

    final a = frames[low];
    final b = frames[high];
    final span = math.max(1, b.timestampMs - a.timestampMs);
    final t = ((timestampMs - a.timestampMs) / span)
        .clamp(0.0, 1.0)
        .toDouble();
    final names = <String>{...a.landmarks.keys, ...b.landmarks.keys};
    final landmarks = <String, PoseLandmark>{};

    for (final name in names) {
      final left = a.landmarks[name];
      final right = b.landmarks[name];
      if (left != null && right != null) {
        landmarks[name] = PoseLandmark.lerp(left, right, t);
      } else if (left != null) {
        landmarks[name] = left;
      } else if (right != null) {
        landmarks[name] = right;
      }
    }

    final bboxA = a.bboxHeightNorm;
    final bboxB = b.bboxHeightNorm;
    final bbox = bboxA != null && bboxB != null
        ? _lerpDouble(bboxA, bboxB, t)
        : bboxA ?? bboxB;

    return PoseSample(
      timestampMs: timestampMs,
      frameWidth: a.frameWidth,
      frameHeight: a.frameHeight,
      personDetected: a.personDetected || b.personDetected,
      avgVisibility: _lerpDouble(a.avgVisibility, b.avgVisibility, t),
      bboxHeightNorm: bbox,
      landmarks: landmarks,
    );
  }

  PoseSample _sampleFromFrame(PoseFrame frame) {
    return PoseSample(
      timestampMs: frame.timestampMs.toDouble(),
      frameWidth: frame.frameWidth,
      frameHeight: frame.frameHeight,
      personDetected: frame.personDetected,
      avgVisibility: frame.avgVisibility,
      bboxHeightNorm: frame.bboxHeightNorm,
      landmarks: frame.landmarks,
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

double _averageVisibility(Iterable<PoseLandmark> landmarks) {
  final core = landmarks.where((landmark) => _coreLandmarks.contains(landmark.name));
  final values = core.isEmpty ? landmarks : core;
  if (values.isEmpty) return 0;
  var total = 0.0;
  var count = 0;
  for (final value in values) {
    total += value.visibility;
    count++;
  }
  return count == 0 ? 0 : total / count;
}

String? _canonicalLandmarkName(String? rawName, int? index) {
  if (rawName != null && rawName.trim().isNotEmpty) {
    final compact = rawName.trim();
    return _nameAliases[compact] ?? compact;
  }
  if (index != null && index >= 0 && index < _mediapipeNames.length) {
    return _mediapipeNames[index];
  }
  return null;
}

const _nameAliases = <String, String>{
  'left_eye': 'leftEye',
  'right_eye': 'rightEye',
  'left_ear': 'leftEar',
  'right_ear': 'rightEar',
  'left_shoulder': 'leftShoulder',
  'right_shoulder': 'rightShoulder',
  'left_elbow': 'leftElbow',
  'right_elbow': 'rightElbow',
  'left_wrist': 'leftWrist',
  'right_wrist': 'rightWrist',
  'left_pinky': 'leftPinky',
  'right_pinky': 'rightPinky',
  'left_index': 'leftIndex',
  'right_index': 'rightIndex',
  'left_thumb': 'leftThumb',
  'right_thumb': 'rightThumb',
  'left_hip': 'leftHip',
  'right_hip': 'rightHip',
  'left_knee': 'leftKnee',
  'right_knee': 'rightKnee',
  'left_ankle': 'leftAnkle',
  'right_ankle': 'rightAnkle',
  'left_heel': 'leftHeel',
  'right_heel': 'rightHeel',
  'left_foot_index': 'leftFootIndex',
  'right_foot_index': 'rightFootIndex',
};

const _mediapipeNames = <String>[
  'nose',
  'left_eye_inner',
  'leftEye',
  'left_eye_outer',
  'right_eye_inner',
  'rightEye',
  'right_eye_outer',
  'leftEar',
  'rightEar',
  'mouth_left',
  'mouth_right',
  'leftShoulder',
  'rightShoulder',
  'leftElbow',
  'rightElbow',
  'leftWrist',
  'rightWrist',
  'leftPinky',
  'rightPinky',
  'leftIndex',
  'rightIndex',
  'leftThumb',
  'rightThumb',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
  'leftAnkle',
  'rightAnkle',
  'leftHeel',
  'rightHeel',
  'leftFootIndex',
  'rightFootIndex',
];

const _coreLandmarks = <String>{
  'leftShoulder',
  'rightShoulder',
  'leftElbow',
  'rightElbow',
  'leftWrist',
  'rightWrist',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
  'leftAnkle',
  'rightAnkle',
};

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

Offset midpoint(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
