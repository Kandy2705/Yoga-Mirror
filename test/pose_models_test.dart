import 'package:flutter_test/flutter_test.dart';
import 'package:yoga_mirror_rive_demo/models/pose_models.dart';

void main() {
  test('interpolates landmarks between frames', () {
    final sequence = PoseSequence.fromJson({
      'schemaVersion': '2.0',
      'capture': {'model': 'test'},
      'captureParams': {'sampleFps': 10},
      'frames': [
        {
          'timestampMs': 0,
          'frameWidth': 100,
          'frameHeight': 100,
          'personDetected': true,
          'avgVisibility': 1,
          'distanceProxy': {'bboxHeightNorm': 0.5},
          'landmarks': [
            {'name': 'leftHip', 'xNorm': 0.2, 'yNorm': 0.5, 'visibility': 1},
          ],
        },
        {
          'timestampMs': 100,
          'frameWidth': 100,
          'frameHeight': 100,
          'personDetected': true,
          'avgVisibility': 1,
          'distanceProxy': {'bboxHeightNorm': 0.5},
          'landmarks': [
            {'name': 'leftHip', 'xNorm': 0.4, 'yNorm': 0.7, 'visibility': 1},
          ],
        },
      ],
    });

    final sample = sequence.sampleAt(50);
    expect(sample.landmark('leftHip')!.xNorm, closeTo(0.3, 0.0001));
    expect(sample.landmark('leftHip')!.yNorm, closeTo(0.6, 0.0001));
  });
}
