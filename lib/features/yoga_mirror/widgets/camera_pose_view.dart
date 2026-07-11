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
  bool _isInitializing = false;
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
    // iOS: kéo Control Center / volume / notification → AppLifecycleState.inactive
    // rồi resumed. KHÔNG được dispose camera ở inactive (sẽ load lại liên tục).
    // Chỉ nhả camera khi app thật sự vào background (paused / hidden).
    switch (state) {
      case AppLifecycleState.inactive:
        // Giữ preview; chỉ tạm dừng pose stream để đỡ tốn CPU.
        unawaited(_pauseImageStreamOnly());
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_stopCamera());
        break;
      case AppLifecycleState.resumed:
        unawaited(_onResumed());
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _onResumed() async {
    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      // Camera còn sống (vd. sau Control Center) → chỉ bật lại stream.
      if (widget.poseProcessor != null) {
        await _startImageStream();
      }
      return;
    }
    await _initialize();
  }

  Future<void> _pauseImageStreamOnly() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Ignore: controller may already be torn down.
    }
  }

  Future<void> _initialize() async {
    if (_isInitializing) return;
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      return;
    }
    _isInitializing = true;

    if (kIsWeb) {
      try {
        await _initializeWebCamera();
      } finally {
        _isInitializing = false;
      }
      return;
    }

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _cameraError = 'Không có quyền camera';
        });
      }
      _isInitializing = false;
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'Không tìm thấy camera');
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // Drop any half-dead controller before creating a new one.
      await _stopCamera();

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
      if (mounted) setState(() => _cameraError = 'Lỗi camera: $error');
    } finally {
      _isInitializing = false;
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
    _cameraController = null;
    if (controller == null) {
      return;
    }

    try {
      if (controller.value.isInitialized && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Stream may already be stopped.
    }
    try {
      await controller.dispose();
    } catch (_) {
      // Ignore double-dispose.
    }
    if (mounted) {
      setState(() {});
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