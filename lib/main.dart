import 'package:flutter/material.dart';

import 'app/yoga_mirror_app.dart';
import 'features/yoga_mirror/services/pose_stream_processor.dart';
import 'features/yoga_mirror/services/pose_stream_processor_mlkit.dart';

Future<void> main() async {
  await YogaMirrorApp.bootstrap();
  runApp(
    YogaMirrorApp(
      poseProcessor: PoseStreamProcessorMlKit(),
    ),
  );
}