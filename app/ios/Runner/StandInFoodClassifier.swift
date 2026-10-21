#if targetEnvironment(simulator)
  import CoreGraphics
  import ImageIO

  /// Stands in for Vision on the simulator, where Vision can't classify
  /// images, so the scanning screens can still be built and tried there.
  /// The verdict comes from the photo's pixels, so a photo always gets the
  /// same one: about 3 in 10 photos are meals and 1 in 10 a maybe.
  struct StandInFoodClassifier: FoodClassifier {
    let model = "standin1"

    func classify(
      _ image: CGImage,
      orientation: CGImagePropertyOrientation
    ) async throws -> FoodClassification {
      switch Self.fingerprint(image) % 10 {
      case 0..<3:
        return FoodClassification(verdict: .food, score: 0.9, model: model)
      case 3:
        return FoodClassification(verdict: .maybe, score: 0.4, model: model)
      default:
        return FoodClassification(verdict: .notFood, score: 0.05, model: model)
      }
    }

    /// Draws the image at 4×4 pixels and hashes the bytes.
    private static func fingerprint(_ image: CGImage) -> Int {
      var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
      pixels.withUnsafeMutableBytes { buffer in
        CGContext(
          data: buffer.baseAddress, width: 4, height: 4, bitsPerComponent: 8,
          bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )?.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 4))
      }
      return pixels.reduce(17) { ($0 &* 31 &+ Int($1)) & 0xFFFF_FFFF }
    }
  }
#endif
