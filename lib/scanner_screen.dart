import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'camera_pipeline_service.dart';
import 'rule_engine.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class ScannerScreen extends StatefulWidget {
  final bool isBanknote;

  const ScannerScreen({super.key, required this.isBanknote});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  final CameraPipelineService _pipeline = CameraPipelineService();

  PipelineResult? _lastResult;
  bool _isBlurry = false;
  bool _flashOn = false;
  bool _isProcessingFrame = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _controller = CameraController(
        cameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      if (!mounted) return;

      setState(() {});

      // Start streaming YUV frames
      await _controller!.startImageStream(_onFrameReceived);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _onFrameReceived(CameraImage image) async {
    if (_isProcessingFrame || _isNavigating) return;
    _isProcessingFrame = true;

    final result = await _pipeline.processFrame(
      image,
      _controller!,
      widget.isBanknote,
    );

    if (!mounted) return;

    _onFrameProcessed(result);
  }

  void _onFrameProcessed(PipelineResult? result) {
    if (result == null) {
      setState(() => _isProcessingFrame = false);
      return;
    }

    setState(() {
      _lastResult = result;
      _isBlurry =
          result.sharpnessScore < CameraPipelineService.sharpnessThreshold;
      _flashOn = result.flashWasActivated;
      _isProcessingFrame = false;
    });

    // Auto-Capture Trigger
    if (result.shouldCapture && !_isNavigating) {
      _captureImage();
    }
  }

  Future<void> _captureImage() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    // Stop stream to stabilize
    await _controller?.stopImageStream();

    // In a real app, we'd take a high-res photo here
    // For now, we navigated to results with the current verdict
    if (mounted) {
      // Placeholder for navigation to a detailed result screen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto-Capture Déclenchée !')),
      );
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Feed
          Positioned.fill(child: CameraPreview(_controller!)),

          // ─────────────────────────────────────────────────────────
          // DYNAMIC PRO OVERLAY (Perspective / Circles)
          // ─────────────────────────────────────────────────────────
          CustomPaint(
            size: Size.infinite,
            painter: PerspectiveOverlay(
              polyPoints: _lastResult?.polyPoints,
              circleCenter: _lastResult?.circleCenter,
              circleRadius: _lastResult?.circleRadius,
              cameraSize: Size(
                _controller!.value.previewSize!.height,
                _controller!.value.previewSize!.width,
              ),
            ),
          ),

          // Defect bounding boxes
          if (_lastResult != null && _lastResult!.defects.isNotEmpty)
            _buildDefectBoxes(size),

          // Status indicators
          _buildStatusBar(),

          // Verdict Result Card
          if (_lastResult != null && !_isBlurry) _buildResultCard(),

          // Back Button
          Positioned(
            top: 48,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefectBoxes(Size screenSize) {
    return CustomPaint(
      size: screenSize,
      painter: _DefectBoxPainter(
        defects: _lastResult!.defects,
        previewSize: _controller!.value.previewSize!,
        screenSize: screenSize,
      ),
    );
  }

  Widget _buildStatusBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_flashOn)
              Container(
                margin: const EdgeInsets.only(right: 16, top: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amberAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.flash_on, size: 16, color: Colors.black),
                    SizedBox(width: 4),
                    Text('TORCHE AUTO',
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final res = _lastResult!;

    final color = res.verdict.verdict == Verdict.mandatoryAcceptance
        ? Colors.greenAccent
        : res.verdict.verdict == Verdict.legitimateRefusal
            ? Colors.redAccent
            : Colors.orangeAccent;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E).withOpacity(0.96),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              res.isBanknote ? 'BILLET DÉTECTÉ' : 'PIÈCE DÉTECTÉE',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(res.verdict.reason,
                style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class PerspectiveOverlay extends CustomPainter {
  final List<cv.Point>? polyPoints;
  final cv.Point? circleCenter;
  final double? circleRadius;
  final Size cameraSize;

  PerspectiveOverlay({
    this.polyPoints,
    this.circleCenter,
    this.circleRadius,
    required this.cameraSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cameraSize.width == 0 || cameraSize.height == 0) return;
    final scaleX = size.width / cameraSize.width;
    final scaleY = size.height / cameraSize.height;

    final paint = Paint()
      ..color = Colors.green.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final fillPaint = Paint()
      ..color = Colors.green.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    if (polyPoints != null && polyPoints!.length == 4) {
      final path = Path();
      path.moveTo(polyPoints![0].x * scaleX, polyPoints![0].y * scaleY);
      for (var i = 1; i < 4; i++) {
        path.lineTo(polyPoints![i].x * scaleX, polyPoints![i].y * scaleY);
      }
      path.close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, paint);
    }

    if (circleCenter != null && circleRadius != null) {
      final center = Offset(circleCenter!.x * scaleX, circleCenter!.y * scaleY);
      final radius = circleRadius! * scaleX;
      canvas.drawCircle(center, radius, fillPaint);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PerspectiveOverlay oldDelegate) => true;
}

class _DefectBoxPainter extends CustomPainter {
  final List<DefectBox> defects;
  final Size previewSize;
  final Size screenSize;

  _DefectBoxPainter({
    required this.defects,
    required this.previewSize,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = screenSize.width / previewSize.height;
    final scaleY = screenSize.height / previewSize.width;

    for (final defect in defects) {
      final paint = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final rect = Rect.fromLTRB(
        defect.left * scaleX,
        defect.top * scaleY,
        defect.right * scaleX,
        defect.bottom * scaleY,
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_DefectBoxPainter old) => true;
}
