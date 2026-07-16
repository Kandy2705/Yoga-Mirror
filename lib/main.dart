import 'package:flutter/material.dart';

import 'app/yoga_mirror_app.dart';

Future<void> main() async {
  await YogaMirrorApp.bootstrap();
  runApp(const YogaMirrorApp());
}
