import CoreGraphics
import Foundation
import ImageIO

/// A photo the scanner can look at.
struct PhotoRef: Equatable {
  /// The photo's `PHAsset.localIdentifier`.
  let id: String
  let taken: Date?
}

/// The result of asking for a photo's pixels.
enum PhotoLoad {
  case loaded(CGImage, CGImagePropertyOrientation)

  /// Only in iCloud, and downloading wasn't allowed or didn't finish.
  case inCloud

  case failed
}

/// Where the scanner gets photos: the photo library, or a fake in tests.
protocol PhotoSource: AnyObject {
  /// Every photo Platter can see, newest first.
  func photos() -> [PhotoRef]

  /// A small copy of the photo, big enough to classify.
  func load(_ id: String, allowDownload: Bool) async -> PhotoLoad
}

/// How far a scan has got. Counts cover every photo Platter can see,
/// including ones checked by earlier scans.
struct ScanProgress: Equatable {
  /// Photos Platter can see, not counting screenshots.
  var total = 0

  var checked = 0
  var meals = 0
  var maybes = 0

  /// Only in iCloud, waiting for Wi-Fi to download.
  var waitingForWiFi = 0

  /// Couldn't be loaded; tried again by the next scan.
  var unavailable = 0

  var running = false

  /// The newest meals, at most `previewSize`, for the scanning screen.
  var preview: [String] = []

  static let previewSize = 12
}

/// Looks through every photo Platter can see, newest first, and saves a
/// verdict for each. Photos only in iCloud are left until the rest are done,
/// then downloaded while `canDownload` allows it (on Wi-Fi).
actor FoodScanner {
  init(
    classifier: FoodClassifier,
    store: ScanStore,
    source: PhotoSource,
    canDownload: @escaping @Sendable () -> Bool
  ) {
    self.classifier = classifier
    self.store = store
    self.source = source
    self.canDownload = canDownload
  }

  private let classifier: FoodClassifier
  private let store: ScanStore
  private let source: PhotoSource
  private let canDownload: @Sendable () -> Bool

  /// Photos loaded and classified at once.
  private let parallel = 4

  /// Results are saved in batches of this many.
  private let batchSize = 25

  private var progress = ScanProgress()
  private var preview: [(taken: Date, id: String)] = []

  /// Scans until every photo is checked, Wi-Fi is needed, or the task is
  /// cancelled, calling `report` as it goes and once at the end.
  func run(report: @escaping (ScanProgress) -> Void) async {
    progress = ScanProgress(running: true)
    preview = []

    let photos = source.photos()
    progress.total = photos.count
    let saved = Dictionary(
      ((try? store.all()) ?? []).map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first })
    var todo: [PhotoRef] = []
    for photo in photos {
      if let result = saved[photo.id], result.model == classifier.model {
        count(result)
      } else {
        todo.append(photo)
      }
    }
    report(progress)

    var inCloud = await check(todo, allowDownload: false, report: report)
    if !inCloud.isEmpty && !Task.isCancelled && canDownload() {
      inCloud = await check(inCloud, allowDownload: true, report: report)
    }
    progress.waitingForWiFi = Task.isCancelled ? 0 : inCloud.count
    progress.running = false
    report(progress)
  }

  /// Meals and maybes among the photos Platter can still see, newest first.
  func meals() -> [ScanResult] {
    let visible = Set(source.photos().map(\.id))
    return ((try? store.all()) ?? []).filter {
      $0.verdict != .notFood && visible.contains($0.id)
    }
  }

  /// Classifies `photos`, a few at a time in order, and returns the ones
  /// that turned out to be only in iCloud.
  private func check(
    _ photos: [PhotoRef],
    allowDownload: Bool,
    report: @escaping (ScanProgress) -> Void
  ) async -> [PhotoRef] {
    var inCloud: [PhotoRef] = []
    var unsaved: [ScanResult] = []
    var lastReport = Date.distantPast

    await withTaskGroup(of: (PhotoRef, Outcome).self) { group in
      var queue = photos[...]
      /// Stops handing out work once cancelled or, when downloading, once
      /// off Wi-Fi; whatever's left over counts as still in iCloud.
      func startNext() {
        guard let photo = queue.first else { return }
        if Task.isCancelled { return }
        if allowDownload && !canDownload() {
          inCloud.append(contentsOf: queue)
          queue = []
          return
        }
        queue = queue.dropFirst()
        group.addTask { (photo, await self.outcome(for: photo, allowDownload)) }
      }

      for _ in 0..<parallel { startNext() }
      while let (photo, outcome) = await group.next() {
        switch outcome {
        case .classified(let result):
          unsaved.append(result)
          count(result)
        case .inCloud:
          inCloud.append(photo)
        case .failed:
          progress.unavailable += 1
        }
        if unsaved.count >= batchSize {
          try? store.save(unsaved)
          unsaved = []
        }
        if Date().timeIntervalSince(lastReport) > 0.2 {
          report(progress)
          lastReport = Date()
        }
        startNext()
      }
    }
    try? store.save(unsaved)
    return inCloud
  }

  private enum Outcome {
    case classified(ScanResult)
    case inCloud
    case failed
  }

  private nonisolated func outcome(
    for photo: PhotoRef,
    _ allowDownload: Bool
  ) async -> Outcome {
    switch await source.load(photo.id, allowDownload: allowDownload) {
    case .inCloud:
      return .inCloud
    case .failed:
      return .failed
    case .loaded(let image, let orientation):
      guard
        let found = try? await classifier.classify(
          image, orientation: orientation)
      else { return .failed }
      return .classified(
        ScanResult(
          id: photo.id, taken: photo.taken, verdict: found.verdict,
          score: found.score, model: found.model))
    }
  }

  private func count(_ result: ScanResult) {
    progress.checked += 1
    switch result.verdict {
    case .food:
      progress.meals += 1
      addToPreview(result)
    case .maybe:
      progress.maybes += 1
    case .notFood:
      break
    }
  }

  private func addToPreview(_ result: ScanResult) {
    let taken = result.taken ?? .distantPast
    let at = preview.firstIndex { $0.taken < taken } ?? preview.count
    guard at < ScanProgress.previewSize else { return }
    preview.insert((taken, result.id), at: at)
    preview = Array(preview.prefix(ScanProgress.previewSize))
    progress.preview = preview.map(\.id)
  }
}
