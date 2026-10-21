import Foundation
import Network

/// Owns the app's one food scan, so the Flutter screens and background tasks
/// share it. Its state is only touched on the main thread, which is what
/// makes it safe to send between threads.
final class FoodScanService: @unchecked Sendable {
  static let shared = FoodScanService()

  /// The classifier every scan uses. To try a different model, or Vision
  /// plus a second model, change this.
  private static func makeClassifier() -> FoodClassifier {
    #if targetEnvironment(simulator)
      return StandInFoodClassifier()
    #else
      return VisionFoodClassifier()
    #endif
  }

  /// Fingerprints meal photos to find repeat shots of a dish.
  private static func makeFingerprinter() -> PhotoFingerprinter {
    #if targetEnvironment(simulator)
      return StandInFingerprinter()
    #else
      return VisionFingerprinter()
    #endif
  }

  private(set) var progress = ScanProgress()
  private var scanner: FoodScanner?
  private var task: Task<Void, Never>?
  private var observers: [UUID: (ScanProgress) -> Void] = [:]

  private let source = PhotoLibrarySource()
  private let network = NWPathMonitor()
  private let onWiFi = OnWiFi()

  private init() {
    network.pathUpdateHandler = { [onWiFi] path in
      // Hotspots count as Wi-Fi but bill like cellular, so they're excluded.
      let now = path.status == .satisfied && path.usesInterfaceType(.wifi)
        && !path.isExpensive
      if onWiFi.update(now) && now {
        DispatchQueue.main.async { self.resumeDownloads() }
      }
    }
    network.start(queue: DispatchQueue(label: "platter.food-scan.network"))
  }

  /// Starts a scan unless one is already running.
  func start() throws {
    guard task == nil else { return }
    let scanner = try self.scanner ?? makeScanner()
    self.scanner = scanner
    task = Task {
      await scanner.run { progress in
        DispatchQueue.main.async { self.update(progress) }
      }
      DispatchQueue.main.async { self.task = nil }
    }
    // Report it straight away, before `start` returns, so nobody watching
    // mistakes the last scan's (or no scan's) result for this one's.
    var starting = progress
    starting.running = true
    update(starting)
  }

  func stop() {
    task?.cancel()
  }

  /// Meals and maybes found so far, newest first.
  func meals(_ done: @escaping ([Meal]) -> Void) throws {
    let scanner = try self.scanner ?? makeScanner()
    self.scanner = scanner
    Task {
      let meals = await scanner.meals()
      DispatchQueue.main.async { done(meals) }
    }
  }

  /// Calls `observer` with the current progress now and on every change,
  /// until `removeObserver` is called with the returned token.
  func observe(_ observer: @escaping (ScanProgress) -> Void) -> UUID {
    let token = UUID()
    observers[token] = observer
    observer(progress)
    return token
  }

  func removeObserver(_ token: UUID) {
    observers[token] = nil
  }

  private func update(_ progress: ScanProgress) {
    self.progress = progress
    observers.values.forEach { $0(progress) }
  }

  /// Back on Wi-Fi with iCloud photos left over: carry on with those.
  private func resumeDownloads() {
    if progress.waitingForWiFi > 0 { try? start() }
  }

  private func makeScanner() throws -> FoodScanner {
    let onWiFi = self.onWiFi
    return FoodScanner(
      classifier: Self.makeClassifier(),
      fingerprinter: Self.makeFingerprinter(),
      store: try ScanStore.standard(),
      source: source,
      canDownload: { onWiFi.value })
  }
}

/// Whether the phone is on Wi-Fi, readable from any thread.
private final class OnWiFi: @unchecked Sendable {
  private let lock = NSLock()
  private var current = false

  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  /// Returns whether the value changed.
  func update(_ value: Bool) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let changed = current != value
    current = value
    return changed
  }
}
