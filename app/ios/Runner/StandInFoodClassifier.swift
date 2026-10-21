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

    /// Hashes the image's 4×4-pixel thumbnail.
    private static func fingerprint(_ image: CGImage) -> Int {
      tinyPixels(image, size: 4).reduce(17) { ($0 &* 31 &+ Int($1)) & 0xFFFF_FFFF }
    }
  }

  /// Stands in for Vision's fingerprints on the simulator: the photo shrunk
  /// to 8×8 pixels, so near-identical photos still come out close.
  struct StandInFingerprinter: PhotoFingerprinter {
    let model = "standin1"

    func fingerprint(
      _ image: CGImage,
      orientation: CGImagePropertyOrientation
    ) async throws -> PhotoFingerprint {
      let pixels = tinyPixels(image, size: 8).map { Float($0) / 255 }
      let length = pixels.reduce(0) { $0 + $1 * $1 }.squareRoot()
      return PhotoFingerprint(
        vector: pixels.map { length > 0 ? $0 / length : 0 }, quality: nil)
    }
  }

  /// The image drawn at `size`×`size`, as RGBX bytes.
  private func tinyPixels(_ image: CGImage, size: Int) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    pixels.withUnsafeMutableBytes { buffer in
      CGContext(
        data: buffer.baseAddress, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )?.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    }
    return pixels
  }
#endif
