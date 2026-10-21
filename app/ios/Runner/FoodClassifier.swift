import CoreGraphics
import ImageIO

/// What a classifier thinks one photo shows.
enum FoodVerdict: String {
  case food

  /// Might be food. Kept, but the user is asked to check it.
  case maybe

  case notFood
}

/// A classifier's answer for one photo.
struct FoodClassification: Equatable {
  let verdict: FoodVerdict

  /// How food-like the photo looked, from 0 to 1. Only comparable between
  /// results from the same `model`.
  let score: Float

  /// The `FoodClassifier.model` that gave this answer, saved with the result
  /// so photos judged by an older or different model can be rescanned.
  let model: String
}

/// Decides whether a photo shows food. The scanner only knows this protocol,
/// so Vision, a Core ML model or a mix of both can be swapped in without
/// touching how photos are found, loaded or saved.
protocol FoodClassifier {
  /// Name and version, e.g. "vision2-rules1". Change it whenever the model
  /// or its thresholds change, so earlier results can be told apart.
  var model: String { get }

  func classify(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation
  ) async throws -> FoodClassification
}
