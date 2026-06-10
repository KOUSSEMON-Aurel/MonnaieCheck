/// Vision Pipeline — MonnaieCheck (Zero-Dataset Architecture)
///
/// Architecture overview:
///
///   [Camera Frame (YUV)]
///        │
///        ├─► [ML Kit Object Detector]  ← Model bundled in assets
///        │         (gets bounding box of the currency)
///        │
///        ├─► [ML Kit Text Recognition] ← Model managed by Google Play Services
///        │         (reads serial number)
///        │
///        └─► [CvEngine (OpenCV)]       ← Zero-dataset, pure math
///                  - Surface estimation (Canny + contours)
///                  - Art.14 ink detection (LAB color space)
///                  - Coin convexity (contourArea / hullArea)
///                  - HSV histogram for denomination
///

import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Wraps ML Kit detectors. Both are singletons to avoid re-initialization cost.
class VisionPipeline {
  // ML Kit Object Detector — local version for offline bundling
  // USES LocalObjectDetectorOptions for ML Kit 0.15.1
  static final ObjectDetector _objectDetector = ObjectDetector(
    options: LocalObjectDetectorOptions(
      mode: DetectionMode.stream,
      modelPath: 'assets/models/currency_detector.tflite',
      classifyObjects: true,
      multipleObjects: true,
    ),
  );

  // ML Kit Text Recognizer — Latin script (handles BCEAO serial numbers)
  static final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  bool get isReady => true;

  /// Detect the bounding box of a currency note/coin in the frame.
  /// Returns the first detected object, or null if nothing is found.
  Future<DetectedObject?> detectObject(InputImage inputImage) async {
    final objects = await _objectDetector.processImage(inputImage);
    return objects.isNotEmpty ? objects.first : null;
  }

  /// Read the serial number from a banknote.
  Future<String?> readSerialNumber(InputImage inputImage) async {
    final result = await _textRecognizer.processImage(inputImage);
    // A valid BCEAO serial number is 10–12 uppercase alphanumeric characters
    final serialPattern = RegExp(r'[A-Z0-9]{10,12}');
    for (final block in result.blocks) {
      final match = serialPattern.firstMatch(block.text);
      if (match != null) return match.group(0);
    }
    return null; // Not found or not readable
  }

  void dispose() {
    _objectDetector.close();
    _textRecognizer.close();
  }
}
