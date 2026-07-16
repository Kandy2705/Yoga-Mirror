import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

InputImage? cameraImageToInputImage({
  required CameraImage image,
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
}) {
  if (kIsWeb) {
    return null;
  }

  final rotation = _rotationInt(
    sensorOrientation: camera.sensorOrientation,
    lensDirection: camera.lensDirection,
    deviceOrientation: deviceOrientation,
  );

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null) {
    return null;
  }

  if (image.planes.isEmpty) {
    return null;
  }

  final plane = image.planes.first;
  final bytes = Platform.isIOS ? plane.bytes : _concatenatePlanes(image.planes);

  return InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

Uint8List _concatenatePlanes(List<Plane> planes) {
  var totalSize = 0;
  for (final plane in planes) {
    totalSize += plane.bytes.length;
  }
  final result = Uint8List(totalSize);
  var offset = 0;
  for (final plane in planes) {
    result.setRange(offset, offset + plane.bytes.length, plane.bytes);
    offset += plane.bytes.length;
  }
  return result;
}

InputImageRotation _rotationInt({
  required int sensorOrientation,
  required CameraLensDirection lensDirection,
  required DeviceOrientation deviceOrientation,
}) {
  if (Platform.isIOS) {
    return InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;
  }

  var rotationCompensation = 0;
  switch (deviceOrientation) {
    case DeviceOrientation.portraitUp:
      rotationCompensation = 0;
    case DeviceOrientation.landscapeLeft:
      rotationCompensation = 90;
    case DeviceOrientation.portraitDown:
      rotationCompensation = 180;
    case DeviceOrientation.landscapeRight:
      rotationCompensation = 270;
  }

  if (lensDirection == CameraLensDirection.front) {
    rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
  } else {
    rotationCompensation =
        (sensorOrientation - rotationCompensation + 360) % 360;
  }

  return InputImageRotationValue.fromRawValue(rotationCompensation) ??
      InputImageRotation.rotation0deg;
}
