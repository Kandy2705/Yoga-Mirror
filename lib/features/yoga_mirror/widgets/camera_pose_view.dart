import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/yoga_mirror_controller.dart';
import '../services/pose_stream_processor.dart';

class CameraPoseView extends StatefulWidget {
  const CameraPoseView({
    super.key,
    required this.controller,
    this.poseProcessor,
  });

  final YogaMirrorController controller;
  final PoseStreamProcessor? poseProcessor;

  @override
  State<CameraPoseView> createState() => _CameraPoseViewState();
}

class _CameraPoseViewState extends State<CameraPoseView>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isDetecting = false;
  DateTime? _lastProcessedAt;
  String? _cameraError;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    widget.poseProcessor?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    if (kIsWeb) {
      await _initializeWebCamera();
      return;
    }

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _permissionDenied = true;
        _cameraError = 'Không có quyền camera';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'Không tìm thấy camera');
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup:
            Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );

      await controller.initialize();
      await widget.poseProcessor?.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraError = null;
        _permissionDenied = false;
      });

      if (widget.poseProcessor != null) {
        await _startImageStream();
      }
    } catch (error) {
      setState(() => _cameraError = 'Lỗi camera: $error');
    }
  }

  Future<void> _initializeWebCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'Web: không có camera');
        return;
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraError = null;
      });
    } catch (error) {
      setState(() => _cameraError = 'Web camera: $error');
    }
  }

  Future<void> _startImageStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isStreamingImages) {
      return;
    }

    await controller.startImageStream(_processCameraImage);
  }

  Future<void> _stopCamera() async {
    final controller = _cameraController;
    if (controller == null) {
      return;
    }

    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller.dispose();
    if (mounted) {
      setState(() => _cameraController = null);
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final processor = widget.poseProcessor;
    final camera = _cameraController;
    if (kIsWeb || processor == null || camera == null) {
      return;
    }

    if (_isDetecting) {
      return;
    }

    final now = DateTime.now();
    if (_lastProcessedAt != null &&
        now.difference(_lastProcessedAt!).inMilliseconds < 120) {
      return;
    }
    _lastProcessedAt = now;
    _isDetecting = true;

    try {
      final result = await processor.process(image, camera);
      widget.controller.onUserLandmarks(result?.landmarks);
    } catch (_) {
      widget.controller.onUserLandmarks(null);
    } finally {
      _isDetecting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    if (_permissionDenied) {
      return _messageView(
        'Cần quyền camera để demo YogaMirror',
        action: TextButton(
          onPressed: openAppSettings,
          child: const Text('Mở cài đặt'),
        ),
      );
    }

    if (_cameraError != null) {
      return _messageView(_cameraError!);
    }

    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 1,
          height: controller.value.previewSize?.width ?? 1,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _messageView(String message, {Widget? action}) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }
}