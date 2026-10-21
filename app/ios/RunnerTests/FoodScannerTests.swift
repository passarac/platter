import CoreGraphics
import SQLite3
import XCTest

@testable import Runner

/// A photo library in memory. Each photo gets its own image, so the fake
/// classifier can tell which photo it's looking at.
private final class FakePhotoSource: PhotoSource {
  var all: [PhotoRef]
  var inCloud: Set<String> = []
  var broken: Set<String> = []
  let images: [String: CGImage]

  private let lock = NSLock()
  private var _downloaded: [String] = []
  var downloaded: [String] {
    lock.lock()
    defer { lock.unlock() }
    return _downloaded
  }

  init(_ photos: [PhotoRef]) {
    all = photos
    images = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, blankImage()) })
  }

  func photos() -> [PhotoRef] { all }

  func load(_ id: String, allowDownload: Bool) async -> PhotoLoad {
    if broken.contains(id) { return .failed }
    if inCloud.contains(id) {
      guard allowDownload else { return .inCloud }
      lock.lock()
      _downloaded.append(id)
      lock.unlock()
    }
    return .loaded(images[id]!, .up)
  }
}

private final class FakeClassifier: FoodClassifier {
  let model: String
  private var verdicts: [ObjectIdentifier: FoodVerdict] = [:]
  private let lock = NSLock()
  private var _checked: [String] = []
  private var ids: [ObjectIdentifier: String] = [:]

  init(model: String = "fake1", _ source: FakePhotoSource, _ verdicts: [String: FoodVerdict]) {
    self.model = model
    for (id, image) in source.images {
      self.verdicts[ObjectIdentifier(image)] = verdicts[id] ?? .notFood
      ids[ObjectIdentifier(image)] = id
    }
  }

  /// Photos classified, in order.
  var checked: [String] {
    lock.lock()
    defer { lock.unlock() }
    return _checked
  }

  func classify(
    _ image: CGImage, orientation: CGImagePropertyOrientation
  ) async throws -> FoodClassification {
    let key = ObjectIdentifier(image)
    lock.lock()
    _checked.append(ids[key]!)
    lock.unlock()
    let verdict = verdicts[key]!
    return FoodClassification(
      verdict: verdict, score: verdict == .food ? 0.9 : 0.1, model: model)
  }
}

/// Gives each photo the vector in `vectors`, or one far from every other.
private final class FakeFingerprinter: PhotoFingerprinter {
  let model = "fakeprint1"
  private var vectors: [ObjectIdentifier: [Float]] = [:]

  init(_ source: FakePhotoSource, _ vectors: [String: [Float]] = [:]) {
    for (i, (id, image)) in source.images.sorted(by: { $0.key < $1.key }).enumerated() {
      self.vectors[ObjectIdentifier(image)] = vectors[id] ?? [Float(i) * 10, 0]
    }
  }

  func fingerprint(
    _ image: CGImage, orientation: CGImagePropertyOrientation
  ) async throws -> PhotoFingerprint {
    PhotoFingerprint(vector: vectors[ObjectIdentifier(image)]!, quality: nil)
  }
}

private func blankImage() -> CGImage {
  CGContext(
    data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
}

/// Photos "p0", "p1", … taken a day apart, newest first.
private func photos(_ count: Int) -> [PhotoRef] {
  let now = Date()
  return (0..<count).map {
    PhotoRef(id: "p\($0)", taken: now.addingTimeInterval(Double(-$0) * 86_400))
  }
}

private func temporaryStore() throws -> ScanStore {
  try ScanStore(
    url: FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).sqlite"))
}

class FoodScannerTests: XCTestCase {

  private func scan(
    _ source: FakePhotoSource,
    _ classifier: FakeClassifier,
    store: ScanStore,
    fingerprints: [String: [Float]] = [:],
    onWiFi: Bool = true
  ) async -> (ScanProgress, FoodScanner) {
    let scanner = FoodScanner(
      classifier: classifier,
      fingerprinter: FakeFingerprinter(source, fingerprints), store: store,
      source: source, canDownload: { onWiFi })
    var last = ScanProgress()
    await scanner.run { last = $0 }
    return (last, scanner)
  }

  func testChecksEveryPhotoAndCountsMeals() async throws {
    let source = FakePhotoSource(photos(6))
    let classifier = FakeClassifier(
      source, ["p0": .food, "p2": .maybe, "p3": .food])
    let store = try temporaryStore()

    let (progress, _) = await scan(source, classifier, store: store)

    XCTAssertEqual(
      progress,
      ScanProgress(
        total: 6, checked: 6, meals: 2, maybes: 1, running: false,
        preview: ["p0", "p3"]))
    XCTAssertEqual(try store.all().map(\.id), ["p0", "p1", "p2", "p3", "p4", "p5"])
    XCTAssertEqual(try store.all().map(\.model), Array(repeating: "fake1", count: 6))
  }

  func testOnlyChecksNewPhotosNextTime() async throws {
    let source = FakePhotoSource(photos(4))
    let store = try temporaryStore()
    _ = await scan(source, FakeClassifier(source, ["p0": .food]), store: store)

    let classifier = FakeClassifier(source, ["p0": .food])
    let (progress, _) = await scan(source, classifier, store: store)

    XCTAssertEqual(classifier.checked, [])
    XCTAssertEqual(progress.checked, 4)
    XCTAssertEqual(progress.meals, 1)
  }

  func testRechecksPhotosFromAnotherModel() async throws {
    let source = FakePhotoSource(photos(3))
    let store = try temporaryStore()
    _ = await scan(source, FakeClassifier(model: "old1", source, [:]), store: store)

    let classifier = FakeClassifier(model: "new1", source, ["p1": .food])
    let (progress, _) = await scan(source, classifier, store: store)

    XCTAssertEqual(Set(classifier.checked), ["p0", "p1", "p2"])
    XCTAssertEqual(progress.meals, 1)
    XCTAssertEqual(try store.all().map(\.model), ["new1", "new1", "new1"])
  }

  func testICloudPhotosWaitForWiFi() async throws {
    let source = FakePhotoSource(photos(5))
    source.inCloud = ["p1", "p3"]
    let classifier = FakeClassifier(source, ["p1": .food])

    let (progress, _) = await scan(
      source, classifier, store: try temporaryStore(), onWiFi: false)

    XCTAssertEqual(progress.checked, 3)
    XCTAssertEqual(progress.waitingForWiFi, 2)
    XCTAssertEqual(progress.meals, 0)
    XCTAssertEqual(source.downloaded, [])
  }

  func testICloudPhotosDownloadOnWiFiAfterTheRest() async throws {
    let source = FakePhotoSource(photos(5))
    source.inCloud = ["p1", "p3"]
    let classifier = FakeClassifier(source, ["p1": .food])

    let (progress, _) = await scan(source, classifier, store: try temporaryStore())

    XCTAssertEqual(progress.checked, 5)
    XCTAssertEqual(progress.waitingForWiFi, 0)
    XCTAssertEqual(progress.meals, 1)
    XCTAssertEqual(Set(source.downloaded), ["p1", "p3"])
    XCTAssertEqual(Set(classifier.checked.suffix(2)), ["p1", "p3"])
  }

  func testPhotosThatWontLoadAreTriedAgainNextTime() async throws {
    let source = FakePhotoSource(photos(3))
    source.broken = ["p1"]
    let store = try temporaryStore()

    let (first, _) = await scan(source, FakeClassifier(source, [:]), store: store)
    XCTAssertEqual(first.checked, 2)
    XCTAssertEqual(first.unavailable, 1)

    source.broken = []
    let classifier = FakeClassifier(source, ["p1": .food])
    let (second, _) = await scan(source, classifier, store: store)
    XCTAssertEqual(classifier.checked, ["p1"])
    XCTAssertEqual(second.checked, 3)
    XCTAssertEqual(second.unavailable, 0)
    XCTAssertEqual(second.meals, 1)
  }

  func testPreviewHoldsTheNewestTwelveMeals() async throws {
    let source = FakePhotoSource(photos(20))
    let everyPhoto = Dictionary(uniqueKeysWithValues: source.all.map { ($0.id, FoodVerdict.food) })

    let (progress, _) = await scan(
      source, FakeClassifier(source, everyPhoto), store: try temporaryStore())

    XCTAssertEqual(progress.preview, (0..<12).map { "p\($0)" })
  }

  func testRepeatShotsOfADishCountOnce() async throws {
    // p0–p2 are a minute apart; p0 and p1 look alike, p2 doesn't.
    let now = Date()
    let source = FakePhotoSource(
      (0..<3).map { PhotoRef(id: "p\($0)", taken: now.addingTimeInterval(Double(-$0) * 60)) })
    let classifier = FakeClassifier(
      source, ["p0": .food, "p1": .maybe, "p2": .food])

    let (progress, scanner) = await scan(
      source, classifier, store: try temporaryStore(),
      fingerprints: ["p0": [0, 0], "p1": [0.1, 0], "p2": [5, 0]])

    XCTAssertEqual(progress.meals, 2)
    XCTAssertEqual(progress.maybes, 0)
    XCTAssertEqual(progress.preview.count, 2)
    let meals = await scanner.meals()
    XCTAssertEqual(meals.map(\.photos), [["p1", "p0"], ["p2"]])
    XCTAssertEqual(meals.map(\.verdict), [.food, .food])
  }

  func testOnlyMealPhotosAreFingerprinted() async throws {
    let source = FakePhotoSource(photos(3))
    let store = try temporaryStore()
    _ = await scan(source, FakeClassifier(source, ["p1": .maybe]), store: store)

    let saved = Dictionary(uniqueKeysWithValues: try store.all().map { ($0.id, $0) })
    XCTAssertNil(saved["p0"]!.fingerprint)
    XCTAssertNotNil(saved["p1"]!.fingerprint)
    XCTAssertEqual(saved["p1"]!.fingerprintModel, "fakeprint1")
  }

  func testMealPhotosWithoutAFingerprintAreCheckedAgain() async throws {
    let source = FakePhotoSource(photos(2))
    let store = try temporaryStore()
    // As saved before fingerprints existed.
    try store.save([
      ScanResult(id: "p0", taken: source.all[0].taken, verdict: .food, score: 0.9, model: "fake1"),
      ScanResult(id: "p1", taken: source.all[1].taken, verdict: .notFood, score: 0.1, model: "fake1"),
    ])

    let classifier = FakeClassifier(source, ["p0": .food])
    _ = await scan(source, classifier, store: store)

    XCTAssertEqual(classifier.checked, ["p0"])
    XCTAssertNotNil(try store.all().first { $0.id == "p0" }!.fingerprint)
  }

  func testMealsLeaveOutPhotosNoLongerVisible() async throws {
    let source = FakePhotoSource(photos(4))
    let classifier = FakeClassifier(
      source, ["p0": .food, "p1": .maybe, "p2": .food])
    let (_, scanner) = await scan(source, classifier, store: try temporaryStore())

    // The user deselected p0 (limited access) and nothing else changed.
    source.all.removeFirst()
    let meals = await scanner.meals()

    XCTAssertEqual(meals.map(\.id), ["p1", "p2"])
    XCTAssertEqual(meals.map(\.verdict), [.maybe, .food])
    XCTAssertEqual(meals.map(\.photos), [["p1"], ["p2"]])
  }
}

class ScanStoreTests: XCTestCase {

  func testSavesAndReplacesResultsNewestFirst() throws {
    let store = try temporaryStore()
    let old = Date(timeIntervalSince1970: 1_000)
    let new = Date(timeIntervalSince1970: 2_000)
    try store.save([
      ScanResult(id: "a", taken: old, verdict: .food, score: 0.9, model: "m1"),
      ScanResult(id: "b", taken: new, verdict: .notFood, score: 0.1, model: "m1"),
      ScanResult(id: "c", taken: nil, verdict: .maybe, score: 0.4, model: "m1"),
    ])
    try store.save([
      ScanResult(id: "a", taken: old, verdict: .maybe, score: 0.5, model: "m2")
    ])

    XCTAssertEqual(
      try store.all(),
      [
        ScanResult(id: "b", taken: new, verdict: .notFood, score: 0.1, model: "m1"),
        ScanResult(id: "a", taken: old, verdict: .maybe, score: 0.5, model: "m2"),
        ScanResult(id: "c", taken: nil, verdict: .maybe, score: 0.4, model: "m1"),
      ])
  }

  func testSavesFingerprints() throws {
    let store = try temporaryStore()
    let print = PhotoFingerprint(vector: [0.25, -1.5, 3], quality: 0.4)
    try store.save([
      ScanResult(
        id: "a", taken: nil, verdict: .food, score: 0.9, model: "m1",
        fingerprint: print, fingerprintModel: "f1"),
      ScanResult(
        id: "b", taken: nil, verdict: .food, score: 0.9, model: "m1",
        fingerprint: PhotoFingerprint(vector: [1], quality: nil),
        fingerprintModel: "f1"),
    ])

    let saved = try store.all().sorted { $0.id < $1.id }
    XCTAssertEqual(saved[0].fingerprint, print)
    XCTAssertEqual(saved[0].fingerprintModel, "f1")
    XCTAssertNil(saved[1].fingerprint!.quality)
  }

  /// Stores made before fingerprints keep their results and gain the columns.
  func testUpgradesAnOlderStore() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).sqlite")
    var db: OpaquePointer?
    sqlite3_open(url.path, &db)
    sqlite3_exec(
      db,
      "CREATE TABLE results (id TEXT PRIMARY KEY, taken REAL, verdict TEXT NOT NULL, "
        + "score REAL NOT NULL, model TEXT NOT NULL); "
        + "INSERT INTO results VALUES ('a', NULL, 'food', 0.9, 'm1');",
      nil, nil, nil)
    sqlite3_close(db)

    let store = try ScanStore(url: url)
    XCTAssertEqual(try store.all().map(\.id), ["a"])
    XCTAssertNil(try store.all()[0].fingerprint)
    try store.save([
      ScanResult(
        id: "a", taken: nil, verdict: .food, score: 0.9, model: "m1",
        fingerprint: PhotoFingerprint(vector: [1, 2], quality: nil),
        fingerprintModel: "f1")
    ])
    XCTAssertEqual(try store.all()[0].fingerprint?.vector, [1, 2])
  }

  func testKeepsResultsAfterReopening() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).sqlite")
    try ScanStore(url: url).save([
      ScanResult(id: "a", taken: nil, verdict: .food, score: 0.9, model: "m1")
    ])

    XCTAssertEqual(try ScanStore(url: url).all().map(\.id), ["a"])
  }
}
