/// Vision Pipeline Architecture — MonnaieCheck
/// 
/// This is the architectural bridge between the Dart layer and native C++/TFLite.
/// The actual inference is triggered from camera_pipeline_service.dart → Isolate.
///
/// To activate:
///   1. Add your quantized models to assets/models/
///   2. Uncomment the Interpreter.fromAsset calls
///   3. Wire the mat pointer from opencv_dart for direct memory pass

import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'rule_engine.dart';

class VisionPipeline {
  Interpreter? _yoloInterpreter;
  Interpreter? _efficientNetInterpreter;
  bool _initialized = false;

  Future<void> init() async {
    // Uncomment when models are placed in assets/models/
    // _yoloInterpreter = await Interpreter.fromAsset('models/yolov8n_quant.tflite');
    // _efficientNetInterpreter = await Interpreter.fromAsset('models/efficientnet_l0_quant.tflite');
    _initialized = false;
  }

  bool get isReady => _initialized;

  /// Process a banknote RGB frame
  Future<ValidationResult> processBanknote({
    required Uint8List rgbBytes,
    required int width,
    required int height,
  }) async {
    // Step 1: OpenCV — Canny + Homography + surface estimation
    const surfacePercent = 94.5;

    // Step 2: YOLOv8n — defect detection (bounding boxes)
    // _yoloInterpreter.runForMultipleInputs(...);

    return RuleEngine.validateBanknote(
      AnalysisMetrics(
        isBanknote: true,
        surfacePercentage: surfacePercent,
        hasAnomalousInk: false,
        isSerialNumberReadable: true,
        textureSharpness: 85.0,
        denomination: "Unknown",
      ),
    );
  }

  /// Process a coin RGB frame
  Future<ValidationResult> processCoin({
    required Uint8List rgbBytes,
    required int width,
    required int height,
  }) async {
    // Step 1: OpenCV — HoughCircles + radial profiling
    // Step 2: EfficientNet-Lite0 — texture wear analysis
    // _efficientNetInterpreter.run(input, output);

    return RuleEngine.validateCoin(
      AnalysisMetrics(
        isBanknote: false,
        surfacePercentage: 100.0,
        textureSharpness: 90.0,
        coinConvexity: 0.99,
      ),
    );
  }

  void dispose() {
    _yoloInterpreter?.close();
    _efficientNetInterpreter?.close();
  }
}
