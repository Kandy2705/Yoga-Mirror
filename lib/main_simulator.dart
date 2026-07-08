import 'package:flutter/material.dart';

import 'app/yoga_mirror_app.dart';

/// Entry point cho iOS Simulator — không link ML Kit.
Future<void> main() async {
  await YogaMirrorApp.bootstrap();
  runApp(const YogaMirrorApp(simulatorMode: true));
}