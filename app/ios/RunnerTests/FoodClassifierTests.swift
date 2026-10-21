import CoreGraphics
import XCTest

@testable import Runner

/// Label confidences below are what Vision actually returned for each kind
/// of photo while the rules were being tuned.
class VisionFoodRulesTests: XCTestCase {

  private func verdict(_ labels: [String: Float]) -> FoodVerdict {
    VisionFoodRules.judge(labels).0
  }

  func testConfidentDishIsFood() {
    XCTAssertEqual(
      verdict(["food": 0.70, "spaghetti": 0.69, "plate": 0.85]), .food)
    XCTAssertEqual(verdict(["food": 0.88, "strawberry": 0.88]), .food)
  }

  func testWeakerDishOnAPlateIsFood() {
    XCTAssertEqual(verdict(["food": 0.35, "bread": 0.35, "bowl": 0.82]), .food)
  }

  func testWeakerDishWithoutAPlateIsMaybe() {
    XCTAssertEqual(verdict(["food": 0.40, "soup": 0.39]), .maybe)
  }

  /// A plated meal Vision barely recognised as food.
  func testFaintDishOnAPlateIsMaybe() {
    XCTAssertEqual(
      verdict(["food": 0.14, "tableware": 0.94, "drinking_glass": 0.85]),
      .maybe)
  }

  func testDrinkInAGlassIsFood() {
    XCTAssertEqual(
      verdict(["drink": 0.80, "coffee": 0.80, "cup": 0.70]), .food)
  }

  /// A shelf of wine bottles.
  func testDrinkWithoutAGlassIsMaybe() {
    XCTAssertEqual(
      verdict(["drink": 0.89, "wine": 0.89, "wine_bottle": 0.89]), .maybe)
  }

  /// A poster of pasta shapes on a restaurant wall.
  func testFaintDishOffTheTableIsNotFood() {
    XCTAssertEqual(verdict(["food": 0.27, "pasta": 0.27]), .notFood)
  }

  func testGroceryShelfIsNotFood() {
    XCTAssertEqual(
      verdict(["food": 0.60, "fruit": 0.60, "interior_shop": 0.80]), .notFood)
  }

  func testMenuIsNotFood() {
    XCTAssertEqual(
      verdict(["food": 0.55, "document": 0.80, "printed_page": 0.70]),
      .notFood)
  }

  func testUnrelatedPhotoIsNotFood() {
    XCTAssertEqual(verdict(["outdoor": 0.92, "sunset_sunrise": 0.85]), .notFood)
    XCTAssertEqual(verdict([:]), .notFood)
  }

  func testScoreIsTheStrongestFoodOrDrinkLabel() {
    XCTAssertEqual(VisionFoodRules.judge(["food": 0.4, "drink": 0.6]).1, 0.6)
  }
}

/// Runs the real Vision request, so it only runs on a device.
class VisionFoodClassifierTests: XCTestCase {

  func testBlankImageIsNotFood() async throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Vision can't classify images on the simulator")
    #endif
    let context = CGContext(
      data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))

    let classifier = VisionFoodClassifier()
    let result = try await classifier.classify(
      context.makeImage()!, orientation: .up)

    XCTAssertEqual(result.verdict, .notFood)
    XCTAssertEqual(result.model, classifier.model)
    XCTAssertTrue(result.model.hasPrefix("vision"))
  }
}
