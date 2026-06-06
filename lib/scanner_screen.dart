import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'camera_pipeline_service.dart';
import 'rule_engine.dart';

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
        // 720p MAX — sufficient for FCFA detection, saves RAM
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

  /// Called at ~30fps. Backpressure is managed inside CameraPipelineService.
  Future<void> _onFrameReceived(CameraImage image) async {
    final result = await _pipeline.processFrame(
      image,
      _controller!,
      widget.isBanknote,
    );

    if (result == null || !mounted) return;

    setState(() {
      _lastResult = result;
      _isBlurry = result.sharpnessScore < CameraPipelineService._sharpnessThreshold;
      _flashOn = result.flashWasActivated;
    });
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
          // Camera Feed (full-screen)
          Positioned.fill(child: CameraPreview(_controller!)),

          // Darkening overlay outside the scan zone
          _buildScanZoneOverlay(size),

          // Defect bounding boxes from YOLO/EfficientNet
          if (_lastResult != null && _lastResult!.defects.isNotEmpty)
            _buildDefectBoxes(size),

          // Status indicators (blur warning, flash indicator)
          _buildStatusBar(),

          // Verdict Result Card
          if (_lastResult != null && !_isBlurry)
            _buildResultCard(),

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

  Widget _buildScanZoneOverlay(Size size) {
    final areaW = size.width * 0.85;
    final areaH = widget.isBanknote ? 200.0 : areaW;
    final top = (size.height - areaH) / 2;
    final left = (size.width - areaW) / 2;

    return Stack(
      children: [
        // Dark overlay with a clear hole
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.55),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(color: Colors.transparent),
              Positioned(
                top: top,
                left: left,
                child: Container(
                  width: areaW,
                  height: areaH,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(
                      widget.isBanknote ? 16 : areaW,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Border on scan zone
        Positioned(
          top: top,
          left: left,
          child: Container(
            width: areaW,
            height: areaH,
            decoration: BoxDecoration(
              border: Border.all(
                color: _isBlurry ? Colors.redAccent : Colors.blueAccent,
                width: 2.5,
              ),
              borderRadius: BorderRadius.circular(
                widget.isBanknote ? 16 : areaW,
              ),
            ),
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              widget.isBanknote ? 'Cadrez le billet' : 'Cadrez la pièce',
              style: TextStyle(
                color: _isBlurry ? Colors.redAccent : Colors.blue[100],
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Renders AI-detected defect bounding boxes on the camera preview
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amberAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.flash_on, size: 16, color: Colors.black),
                    SizedBox(width: 4),
                    Text('TORCHE AUTO', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
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

    // Blur warning takes priority
    if (_isBlurry) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: _buildPill(
          icon: Icons.blur_on,
          color: Colors.orange,
          message: 'Stabilisez l\'appareil — Image floue',
          subtext: 'Netteté: ${res.sharpnessScore.toStringAsFixed(0)} / ${CameraPipelineService._sharpnessThreshold.toInt()} requis',
        ),
      );
    }

    final color = res.verdict.verdict == Verdict.mandatoryAcceptance
        ? Colors.greenAccent
        : res.verdict.verdict == Verdict.legitimateRefusal
            ? Colors.redAccent
            : Colors.orangeAccent;

    final icon = res.verdict.verdict == Verdict.mandatoryAcceptance
        ? Icons.check_circle_rounded
        : res.verdict.verdict == Verdict.legitimateRefusal
            ? Icons.cancel_rounded
            : Icons.warning_rounded;

    final title = switch(res.verdict.verdict) {
      Verdict.mandatoryAcceptance => 'ACCEPTATION OBLIGATOIRE',
      Verdict.legitimateRefusal => 'REFUS LÉGITIME',
      Verdict.exchangeAtBCEAO => 'ÉCHANGE À LA BCEAO',
    };

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E).withOpacity(0.96),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.7), blurRadius: 30)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildMetricRow('Surface estimée', '${res.surfacePercentage.toStringAsFixed(1)}%', color),
            const SizedBox(height: 6),
            _buildMetricRow('Netteté', res.sharpnessScore.toStringAsFixed(0), Colors.white70),
            if (res.defects.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildMetricRow('Défauts détectés', '${res.defects.length}', Colors.amberAccent),
            ],
            const SizedBox(height: 14),
            Text(res.verdict.reason, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(res.verdict.legalNotice, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPill({required IconData icon, required Color color, required String message, required String subtext}) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E).withOpacity(0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 10),
              Expanded(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15))),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtext, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}

/// CustomPainter that draws bounding boxes from the IA model on the camera preview
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
        ..color = Colors.redAccent.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      final rect = Rect.fromLTRB(
        defect.left * scaleX,
        defect.top * scaleY,
        defect.right * scaleX,
        defect.bottom * scaleY,
      );

      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), paint);

      // Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${defect.label} ${(defect.confidence * 100).toInt()}%',
          style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold, backgroundColor: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, rect.topLeft + const Offset(4, 4));
    }
  }

  @override
  bool shouldRepaint(_DefectBoxPainter old) =>
      old.defects != defects || old.previewSize != previewSize;
}
