import XCTest

@testable import Runner

class MealGrouperTests: XCTestCase {

  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  /// A photo taken `seconds` after `start`, fingerprinted at `x` along one
  /// axis, so the distance between two photos is the difference in `x`.
  private func photo(
    _ id: String,
    at seconds: TimeInterval,
    x: Float,
    verdict: FoodVerdict = .food,
    score: Float = 0.9,
    quality: Float? = nil
  ) -> ScanResult {
    ScanResult(
      id: id, taken: start.addingTimeInterval(seconds), verdict: verdict,
      score: score, model: "m1",
      fingerprint: PhotoFingerprint(vector: [x, 0], quality: quality),
      fingerprintModel: "f1")
  }

  private func groups(_ results: [ScanResult]) -> [[String]] {
    MealGrouper.group(results).map(\.photos)
  }

  func testLookalikesMinutesApartAreOneDish() {
    XCTAssertEqual(
      groups([photo("a", at: 0, x: 0), photo("b", at: 240, x: 0.55)]),
      [["a", "b"]])
  }

  func testLessAlikeShotsSecondsApartAreOneDish() {
    XCTAssertEqual(
      groups([photo("a", at: 0, x: 0), photo("b", at: 20, x: 0.7)]),
      [["a", "b"]])
  }

  /// Different dishes at the same table, a few minutes apart.
  func testLessAlikeShotsMinutesApartAreSeparateDishes() {
    XCTAssertEqual(
      groups([photo("a", at: 0, x: 0), photo("b", at: 120, x: 0.7)]),
      [["b"], ["a"]])
  }

  func testDifferentLookingShotsAreSeparateDishes() {
    XCTAssertEqual(
      groups([photo("a", at: 0, x: 0), photo("b", at: 2, x: 0.8)]),
      [["b"], ["a"]])
  }

  func testLookalikesMoreThanTenMinutesApartAreSeparateDishes() {
    XCTAssertEqual(
      groups([photo("a", at: 0, x: 0), photo("b", at: 601, x: 0)]),
      [["b"], ["a"]])
  }

  /// Each shot looks like the next, so the whole run is one dish.
  func testARunOfShotsChains() {
    XCTAssertEqual(
      groups([
        photo("a", at: 0, x: 0), photo("b", at: 60, x: 0.5),
        photo("c", at: 120, x: 1.0), photo("d", at: 180, x: 1.5),
      ]),
      [["a", "b", "c", "d"]])
  }

  func testAMaybeWithAFoodShotIsFood() {
    let meals = MealGrouper.group([
      photo("a", at: 0, x: 0, verdict: .maybe),
      photo("b", at: 10, x: 0.1, verdict: .food),
      photo("c", at: 3_600, x: 0, verdict: .maybe),
    ])
    XCTAssertEqual(meals.map(\.photos), [["c"], ["a", "b"]])
    XCTAssertEqual(meals.map(\.verdict), [.maybe, .food])
  }

  func testTheBestLookingShotIsTheCover() {
    let meal = MealGrouper.group([
      photo("a", at: 0, x: 0, score: 0.95, quality: 0.1),
      photo("b", at: 10, x: 0.1, score: 0.6, quality: 0.7),
    ])[0]
    XCTAssertEqual(meal.id, "b")
    XCTAssertEqual(meal.taken, start.addingTimeInterval(10))
  }

  func testWithoutQualityTheMostFoodLikeShotIsTheCover() {
    let meal = MealGrouper.group([
      photo("a", at: 0, x: 0, score: 0.6),
      photo("b", at: 10, x: 0.1, score: 0.95),
    ])[0]
    XCTAssertEqual(meal.id, "b")
  }

  func testPhotosWithoutAFingerprintOrDateStandAlone() {
    var undated = photo("b", at: 0, x: 0)
    undated = ScanResult(
      id: "b", taken: nil, verdict: .food, score: 0.9, model: "m1",
      fingerprint: undated.fingerprint, fingerprintModel: "f1")
    let unprinted = ScanResult(
      id: "c", taken: start.addingTimeInterval(5), verdict: .food,
      score: 0.9, model: "m1")

    XCTAssertEqual(
      groups([photo("a", at: 0, x: 0), undated, unprinted]),
      [["c"], ["a"], ["b"]])
  }

  func testNotFoodIsLeftOut() {
    XCTAssertEqual(
      groups([photo("a", at: 0, x: 0), photo("b", at: 5, x: 0, verdict: .notFood)]),
      [["a"]])
  }
}
