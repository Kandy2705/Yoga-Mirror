import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/pose_models.dart';

class PoseLoader {
  const PoseLoader._();

  static Future<PoseSequence> fromAsset(String assetPath) async {
    final source = await rootBundle.loadString(assetPath);
    return _parse(source);
  }

  static Future<PoseSequence?> pickFromPhone() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;

    final String source;
    if (bytes != null) {
      source = utf8.decode(bytes);
    } else {
      source = await file.xFile.readAsString();
    }

    return _parse(source);
  }

  static Future<PoseSequence> _parse(String source) async {
    final decoded = await compute(_decodeJson, source);
    return PoseSequence.fromJson(decoded);
  }
}

Map<String, dynamic> _decodeJson(String source) {
  final value = jsonDecode(source);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('File JSON phải có object ở cấp cao nhất.');
  }
  return value;
}
