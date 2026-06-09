import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Advanced Computer Vision Engine for MonnaieCheck V2.
/// Implements Art. 14 Ink Detection, ROI extraction, and more.
class CvEngine {
  
  /// Detects ink marks and surcharges using LAB color space analysis.
  /// Goal: Differentiate between shadows/folds and actual ink (Mandatory Acceptance Art. 14).
  /// Formula: shadow_score = ΔL / (Δa + Δb + 0.01)
  (cv.Mat, bool) detectArt14Ink(cv.Mat billetMat) {
    // 1. Convert to LAB color space
    final lab = cv.cvtColor(billetMat, cv.COLOR_BGR2Lab);
    
    // 2. Compute median blur as a background reference
    final median9 = cv.medianBlur(lab, 9);
    
    // 3. Simple delta calculation
    final diff = cv.absDiff(lab, median9);
    final channels = cv.split(diff);
    final deltaL = channels[0];
    final deltaA = channels[1];
    final deltaB = channels[2];
    
    // 4. Chroma change: Δa + Δb
    final chroma = cv.add(deltaA, deltaB);
    
    // 5. Apply the shadow_score < 3 threshold via binary comparison
    // ΔL < 3 * (Δa + Δb)
    // Fix: cv.multiply(src1, src2, {scale})
    // Let's use a more direct way:
    final cond1 = cv.compare(deltaL, cv.multiply(chroma, chroma, scale: 3.0), cv.CMP_LT);
    
    // 6. Chroma threshold (> 8) to ignore digital noise
    final thresh8 = cv.Mat.fromScalar(chroma.rows, chroma.cols, chroma.type, cv.Scalar(8, 0, 0, 0));
    final cond2 = cv.compare(chroma, thresh8, cv.CMP_GT);
    
    // 7. Boolean result: ink = (shadow_score < 3) AND (deltaChroma > 8)
    // Fix: names are bitwiseAND, bitwiseOR
    final mask = cv.bitwiseAND(cond1, cond2);
    
    // 8. Morphological cleaning
    final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
    cv.morphologyEx(mask, cv.MORPH_CLOSE, kernel, dst: mask);
    cv.morphologyEx(mask, cv.MORPH_OPEN, kernel, dst: mask);
    
    // 9. Connected components filtering (ignore noise < 50px)
    final labels = cv.Mat.empty();
    final stats = cv.Mat.empty();
    final centroids = cv.Mat.empty();
    // Fix: 7 positional arguments
    final count = cv.connectedComponentsWithStats(mask, labels, stats, centroids, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
    
    bool found = false;
    for (int i = 1; i < count; i++) {
        final area = stats.at<int>(i, cv.CC_STAT_AREA);
        if (area > 50 && area < 4000) {
            found = true;
            break;
        }
    }

    return (mask, found);
  }

  /// Identifies the denomination of a BCEAO banknote using HSV histogram patches.
  String identifyDenomination(cv.Mat alignedBillet) {
    final ranges = {
      '500': [0, 15, 165, 179],
      '1000': [10, 25],
      '2000': [130, 155],
      '5000': [45, 70],
      '10000': [100, 125],
    };

    final hsv = cv.cvtColor(alignedBillet, cv.COLOR_BGR2HSV);
    String winner = "Unknown";
    int maxVoxels = 0;

    ranges.forEach((deno, hRange) {
        cv.Mat mask;
        final lower = cv.Mat.fromScalar(hsv.rows, hsv.cols, hsv.type, cv.Scalar(hRange[0].toDouble(), 50, 50, 0));
        final upper = cv.Mat.fromScalar(hsv.rows, hsv.cols, hsv.type, cv.Scalar(hRange[1].toDouble(), 255, 255, 0));
        
        if (deno == '500') {
           final mask1 = cv.inRange(hsv, lower, upper);
           final lower2 = cv.Mat.fromScalar(hsv.rows, hsv.cols, hsv.type, cv.Scalar(hRange[2].toDouble(), 50, 50, 0));
           final upper2 = cv.Mat.fromScalar(hsv.rows, hsv.cols, hsv.type, cv.Scalar(hRange[3].toDouble(), 255, 255, 0));
           final mask2 = cv.inRange(hsv, lower2, upper2);
           mask = cv.bitwiseOR(mask1, mask2);
        } else {
           mask = cv.inRange(hsv, lower, upper);
        }

        final count = cv.countNonZero(mask);
        if (count > maxVoxels) {
            maxVoxels = count;
            winner = deno;
        }
    });

    return winner;
  }

  /// Calculates the geometric integrity of a coin.
  double calculateConvexity(cv.Mat coinMat) {
    final gray = cv.cvtColor(coinMat, cv.COLOR_BGR2GRAY);
    final blur = cv.gaussianBlur(gray, (5, 5), 0);
    final thresh = cv.threshold(blur, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU).$2;
    
    final (contours, _) = cv.findContours(thresh, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    if (contours.isEmpty) return 0.0;
    
    // Contours is VecVecPoint, so first is VecPoint
    final mainContour = contours.first; 
    final area = cv.contourArea(mainContour);
    
    final hullMat = cv.convexHull(mainContour, clockwise: false);
    // Convert Mat to VecPoint for contourArea
    final hullPoints = cv.VecPoint.fromMat(hullMat);
    final hullArea = cv.contourArea(hullPoints);
    
    if (hullArea == 0) return 0.0;
    return area / hullArea;
  }
}
