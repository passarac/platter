import Vision

/// Apple's built-in image classifier: free, on device, about 1,300 labels.
/// `VisionFoodRules` turns those labels into a verdict.
///
/// It doesn't work on the simulator: Vision either fails to load its model
/// there or, forced onto the CPU, returns nonsense labels for every photo.
struct VisionFoodClassifier: FoodClassifier {
  /// Revision 2 (iOS 17+) is more accurate and what the rules were tuned on;
  /// older phones fall back to 1, which has the same labels.
  private let revision: Int = {
    if #available(iOS 17.0, *) { return VNClassifyImageRequestRevision2 }
    return VNClassifyImageRequestRevision1
  }()

  var model: String { "vision\(revision)-rules\(VisionFoodRules.version)" }

  func classify(
    _ image: CGImage,
    orientation: CGImagePropertyOrientation
  ) async throws -> FoodClassification {
    let request = VNClassifyImageRequest()
    request.revision = revision
    // Thousands of photos go through here in one scan; release each one's
    // working memory straight away.
    try autoreleasepool {
      try VNImageRequestHandler(cgImage: image, orientation: orientation)
        .perform([request])
    }
    let labels = Dictionary(
      (request.results ?? []).map { ($0.identifier, $0.confidence) },
      uniquingKeysWith: max
    )
    let (verdict, score) = VisionFoodRules.judge(labels)
    return FoodClassification(verdict: verdict, score: score, model: model)
  }
}

/// Turns Vision's label confidences into a verdict. Tuned on real meal photos
/// and on tricky non-food (menus, shop shelves, cookbook covers, pets, food
/// paintings, plants); the tests hold the cases behind each threshold.
enum VisionFoodRules {
  /// Bump with any change below, so results from the old rules can be found.
  static let version = 3

  /// Things that can show food without being a meal someone ate.
  static let notMeal = [
    "interior_shop", "shopping_cart", "storefront", "document", "printed_page",
    "receipt", "screenshot", "handwriting", "chalkboard", "illustrations",
  ]

  static let tableware = [
    "tableware", "plate", "bowl", "utensil", "drinking_glass", "cup", "mug",
  ]

  static let vessels = ["drinking_glass", "cup", "mug"]

  /// Food as it grows: fine on a plate, but on its own more often a plant,
  /// a piece of shopping, or a painting of one.
  static let produce = [
    "fruit", "vegetable", "berry", "citrus_fruit", "herb", "seasonings",
    "mushroom", "nut",
  ]

  /// Made food, which keeps a strawberry-topped cake from counting as fruit.
  static let prepared = ["dessert", "baked_goods", "candy", "pastry"]

  static let plants = ["grass", "plant", "foliage", "flower", "land", "tree"]
  static let art = ["art", "painting", "illustrations"]

  /// Display-case glass and shop interiors.
  static let counter = ["interior_shop", "raw_glass"]

  /// Vision scores a parent label at least as high as its children, so
  /// "food", "dessert" and "drink" stand in for every dish and drink.
  static func judge(_ labels: [String: Float]) -> (FoodVerdict, Float) {
    func top(_ ids: [String]) -> Float { ids.map { labels[$0] ?? 0 }.max()! }
    let dish = top(["food", "dessert"])
    let drink = labels["drink"] ?? 0
    let score = max(dish, drink)

    if top(notMeal) >= 0.5 { return (.notFood, score) }

    // Vision is often unsure about the food itself but sure about the plate,
    // so a confident table setting lets a weaker food score count.
    let onTable = top(tableware) >= 0.5

    // Food that's all fruit, veg or herbs: the whole dish score comes from
    // produce and nothing looks made.
    let raw = dish > 0 && top(produce) >= dish - 0.02 && top(prepared) < 0.15

    // Off the table, food is often something other than a meal.
    if !onTable {
      if top(counter) >= 0.4 { return (dish >= 0.5 ? .maybe : .notFood, score) }
      if raw && top(plants) >= 0.4 { return (.notFood, score) }
      // Paintings of fruit are out; a painted dish is at most a maybe.
      if top(art) >= 0.3 {
        return (!raw && dish >= 0.3 ? .maybe : .notFood, score)
      }
      // An orange on a desk, strawberries in a hand: no plate at all.
      if raw && top(tableware) < 0.25 {
        return (dish >= 0.3 ? .maybe : .notFood, score)
      }
    }

    if dish >= 0.5 || (dish >= 0.3 && onTable) { return (.food, score) }

    // A drink needs something to drink it from: bottles on their own are
    // usually a shop or bar shelf. And drinks among a crowd of friends, with
    // no food, are more often a photo of the friends.
    if drink >= 0.5 && top(vessels) >= 0.3 {
      let social = (labels["people"] ?? 0) >= 0.85 && dish < 0.3
      return (social ? .maybe : .food, score)
    }

    if dish >= 0.3 || drink >= 0.3 || (dish >= 0.1 && onTable) {
      return (.maybe, score)
    }
    return (.notFood, score)
  }
}
