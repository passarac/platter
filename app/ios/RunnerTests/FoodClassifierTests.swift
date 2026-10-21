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

  func testPaintingOfFoodIsNotFood() {
    XCTAssertEqual(
      verdict([
        "art": 0.72, "painting": 0.72, "food": 0.52, "vegetable": 0.52,
        "bell_pepper": 0.52,
      ]),
      .notFood)
  }

  func testArtWithoutFoodIsNotFood() {
    XCTAssertEqual(verdict(["art": 0.9, "painting": 0.9, "food": 0.05]), .notFood)
    XCTAssertEqual(verdict(["art": 0.9, "painting": 0.9]), .notFood)
  }

  /// A painting of a dish, not just produce, might still be worth a look.
  func testPaintingOfADishIsMaybe() {
    XCTAssertEqual(verdict(["art": 0.5, "painting": 0.5, "food": 0.6, "pasta": 0.6]), .maybe)
  }

  func testPlantsAreNotFood() {
    XCTAssertEqual(
      verdict([
        "grass": 0.69, "outdoor": 0.69, "food": 0.61, "mushroom": 0.61,
        "vegetable": 0.61,
      ]),
      .notFood)
    XCTAssertEqual(
      verdict([
        "dandelion": 0.96, "food": 0.96, "herb": 0.96, "seasonings": 0.96,
        "plant": 0.89,
      ]),
      .notFood)
  }

  /// An orange on a desk, strawberries held up to the camera.
  func testProduceWithoutAPlateIsMaybe() {
    XCTAssertEqual(
      verdict(["food": 0.58, "fruit": 0.58, "citrus_fruit": 0.58, "oranges": 0.58]),
      .maybe)
    XCTAssertEqual(
      verdict(["food": 0.81, "berry": 0.81, "strawberry": 0.81, "utensil": 0.08]),
      .maybe)
  }

  func testProduceInABowlIsFood() {
    XCTAssertEqual(
      verdict(["bowl": 0.73, "food": 0.63, "fruit": 0.63, "oranges": 0.59]), .food)
  }

  /// Vision sees the strawberries more than the cake under them.
  func testFruitToppedDessertsAreFood() {
    XCTAssertEqual(
      verdict([
        "food": 0.82, "berry": 0.80, "strawberry": 0.80, "candy": 0.50,
        "tableware": 0.28,
      ]),
      .food)
    XCTAssertEqual(
      verdict(["food": 0.64, "berry": 0.64, "strawberry": 0.64, "plate": 0.46]),
      .food)
  }

  /// Strawberry tarts at a picnic: plates on the grass.
  func testPicnicOnGrassIsFood() {
    XCTAssertEqual(
      verdict([
        "food": 0.89, "berry": 0.89, "strawberry": 0.89, "plate": 0.77,
        "grass": 0.54, "outdoor": 0.54,
      ]),
      .food)
  }

  func testDisplayCaseIsNotAMeal() {
    XCTAssertEqual(
      verdict([
        "food": 0.73, "cake": 0.63, "dessert": 0.63, "raw_glass": 0.53,
      ]),
      .maybe)
    XCTAssertEqual(
      verdict(["food": 0.42, "chocolate": 0.42, "raw_glass": 0.45]), .notFood)
  }

  func testFriendsWithBeersIsMaybe() {
    XCTAssertEqual(
      verdict([
        "people": 0.95, "drinking_glass": 0.82, "beer": 0.76, "drink": 0.76,
      ]),
      .maybe)
  }

  func testDrinkWithSomeoneInTheBackgroundIsFood() {
    XCTAssertEqual(
      verdict([
        "people": 0.70, "drinking_glass": 0.91, "drink": 0.54, "liquid": 0.54,
      ]),
      .food)
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
