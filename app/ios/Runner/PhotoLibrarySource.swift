import Photos
import UIKit

/// The photos Platter can see in the user's library: everything with full
/// access, or just the selected ones with limited access.
final class PhotoLibrarySource: PhotoSource {
  /// Vision looks at about 300px, so this is plenty and usually already on
  /// the phone even when the original is only in iCloud.
  private static let size = CGSize(width: 360, height: 360)

  /// The assets from the last `photos()`, so loading doesn't refetch them.
  private var assets: [String: PHAsset] = [:]
  private let lock = NSLock()

  func photos() -> [PhotoRef] {
    let options = PHFetchOptions()
    options.sortDescriptors = [
      NSSortDescriptor(key: "creationDate", ascending: false)
    ]
    // Screenshots are never a meal someone ate.
    options.predicate = NSPredicate(
      format: "(mediaSubtypes & %d) == 0",
      PHAssetMediaSubtype.photoScreenshot.rawValue)
    let found = PHAsset.fetchAssets(with: .image, options: options)

    var photos: [PhotoRef] = []
    var byID: [String: PHAsset] = [:]
    photos.reserveCapacity(found.count)
    byID.reserveCapacity(found.count)
    found.enumerateObjects { asset, _, _ in
      photos.append(PhotoRef(id: asset.localIdentifier, taken: asset.creationDate))
      byID[asset.localIdentifier] = asset
    }
    lock.lock()
    assets = byID
    lock.unlock()
    return photos
  }

  func load(_ id: String, allowDownload: Bool) async -> PhotoLoad {
    lock.lock()
    let asset = assets[id]
    lock.unlock()
    guard let asset else { return .failed }

    let options = PHImageRequestOptions()
    // Called back once, with the real image rather than a blurry preview.
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .fast
    options.isNetworkAccessAllowed = allowDownload
    return await withCheckedContinuation { done in
      PHImageManager.default().requestImage(
        for: asset, targetSize: Self.size, contentMode: .aspectFit,
        options: options
      ) { image, info in
        if let image, let cgImage = image.cgImage {
          done.resume(
            returning: .loaded(
              cgImage, CGImagePropertyOrientation(image.imageOrientation)))
        } else if info?[PHImageResultIsInCloudKey] as? Bool == true {
          done.resume(returning: .inCloud)
        } else {
          done.resume(returning: .failed)
        }
      }
    }
  }
}

extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
