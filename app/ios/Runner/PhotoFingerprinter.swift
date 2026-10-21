import CoreGraphics
import ImageIO
import Vision

/// What a photo looks like, for telling repeat shots of one dish apart from
/// different dishes.
struct PhotoFingerprint: Equatable {
  /// Photos that look alike have vectors a short (Euclidean) distance apart.
  let vector: [Float]

  /// How good the photo looks, from -1 to 1, for picking a meal's cover;
  /// nil where the phone can't tell.
  let quality: Float?
}

/// Fingerprints photos the classifier found food in. Like `FoodClassifier`,
/// it's a protocol so the model can be swapped.
protocol PhotoFingerprinter {
  /// Name and version, saved with each fingerprint. Fingerprints from
  /// different models can't be compared, so changing it re-fingerprints
  /// every meal photo.
  var model: String { get }

  func fingerprint(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation
  ) async throws -> PhotoFingerprint
}

struct FingerprintError: Error {}

/// Vision's image feature print, plus its aesthetics score on iOS 18+.
/// Free and on device, like `VisionFoodClassifier`, and likewise doesn't
/// work on the simulator.
struct VisionFingerprinter: PhotoFingerprinter {
  /// Revision 2 (iOS 17+) is what `MealGrouper`'s thresholds were tuned on.
  private let revision: Int = {
    if #available(iOS 17.0, *) {
      return VNGenerateImageFeaturePrintRequestRevision2
    }
    return VNGenerateImageFeaturePrintRequestRevision1
  }()

  private var ratesQuality: Bool {
    if #available(iOS 18.0, *) { return true }
    return false
  }

  var model: String {
    "featureprint\(revision)\(ratesQuality ? "-aesthetics1" : "")"
  }

  func fingerprint(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation
  ) async throws -> PhotoFingerprint {
    let print = VNGenerateImageFeaturePrintRequest()
    print.revision = revision
    // Squash rather than crop, so the whole plate counts.
    print.imageCropAndScaleOption = .scaleFill
    var requests: [VNRequest] = [print]
    var aesthetics: VNRequest?
    if #available(iOS 18.0, *) {
      let request = VNCalculateImageAestheticsScoresRequest()
      requests.append(request)
      aesthetics = request
    }
    try autoreleasepool {
      try VNImageRequestHandler(cgImage: image, orientation: orientation)
        .perform(requests)
    }
    guard let observation = print.results?.first else {
      throw FingerprintError()
    }
    var quality: Float?
    if #available(iOS 18.0, *) {
      quality = (aesthetics as? VNCalculateImageAestheticsScoresRequest)?
        .results?.first?.overallScore
    }
    return PhotoFingerprint(vector: Self.vector(observation), quality: quality)
  }

  private static func vector(_ observation: VNFeaturePrintObservation) -> [Float] {
    let data = observation.data
    if observation.elementType == .double {
      var doubles = [Double](repeating: 0, count: observation.elementCount)
      _ = doubles.withUnsafeMutableBytes { data.copyBytes(to: $0) }
      return doubles.map(Float.init)
    }
    var floats = [Float](repeating: 0, count: observation.elementCount)
    _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }
    return floats
  }
}
