import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/yoga_mirror/services/pose_stream_processor.dart';
import '../features/yoga_mirror/services/pose_stream_processor_stub.dart';
import '../features/yoga_mirror/widgets/yoga_mirror_demo_screen.dart';

class YogaMirrorApp extends StatelessWidget {
  const YogaMirrorApp({
    super.key,
    this.simulatorMode = false,
    this.poseProcessor,
  });

  final bool simulatorMode;
  final PoseStreamProcessor? poseProcessor;

  @override
  Widget build(BuildContext context) {
    final processor = poseProcessor ??
        (simulatorMode ? PoseStreamProcessorStub() : null);

    return MaterialApp(
      title: 'YogaMirror',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101018),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFB388FF),
          surface: Color(0xFF101018),
        ),
        useMaterial3: true,
      ),
      home: YogaMirrorDemoScreen(
        simulatorMode: simulatorMode,
        poseProcessor: processor,
      ),
    );
  }

  static Future<void> bootstrap() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}