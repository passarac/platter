import Foundation

/// One dish, in one or more photos.
struct Meal: Equatable {
  /// The cover photo's id, which also identifies the meal.
  let id: String

  /// Every photo of the dish, oldest first, the cover among them.
  let photos: [String]

  let taken: Date?

  /// `.food` if any photo is, otherwise `.maybe`.
  let verdict: FoodVerdict
}

/// Merges repeat shots of the same dish into one meal: photos taken close
/// together that look alike. Tuned on a real library, where it errs towards
/// keeping photos apart, since a wrongly merged dish would vanish from the
/// calendar but a leftover repeat is only a nuisance.
enum MealGrouper {
  /// Repeat shots are this close in time at most.
  static let window: TimeInterval = 10 * 60

  /// Closer than this, two photos showed the same dish every time, even
  /// from a different angle.
  static let sameDish: Float = 0.6

  /// Up to this distance, photos seconds apart were still the same dish,
  /// but minutes apart they were often different dishes at one table.
  static let likelySameDish: Float = 0.72
  static let burst: TimeInterval = 30

  /// Meals from the food and maybe `results`, newest first. Results
  /// without a fingerprint or date stay meals of their own.
  static func group(_ results: [ScanResult]) -> [Meal] {
    let photos = results.filter { $0.verdict != .notFood }
    let dated = photos.filter { $0.taken != nil && $0.fingerprint != nil }
      .sorted { $0.taken! < $1.taken! }

    var parent = Array(dated.indices)
    func root(_ i: Int) -> Int {
      var i = i
      while parent[i] != i {
        parent[i] = parent[parent[i]]
        i = parent[i]
      }
      return i
    }
    for i in dated.indices {
      var j = i + 1
      while j < dated.count {
        let apart = dated[j].taken!.timeIntervalSince(dated[i].taken!)
        if apart > window { break }
        let d = distance(dated[i].fingerprint!.vector, dated[j].fingerprint!.vector)
        if d < sameDish || (d < likelySameDish && apart <= burst) {
          parent[root(j)] = root(i)
        }
        j += 1
      }
    }

    var groups: [Int: [ScanResult]] = [:]
    for i in dated.indices { groups[root(i), default: []].append(dated[i]) }
    let loose = photos.filter { $0.taken == nil || $0.fingerprint == nil }
    return (groups.values.map { $0 } + loose.map { [$0] })
      .map(meal)
      .sorted { ($0.taken ?? .distantPast) > ($1.taken ?? .distantPast) }
  }

  private static func meal(_ photos: [ScanResult]) -> Meal {
    let cover = photos.max { better($1, than: $0) }!
    return Meal(
      id: cover.id,
      photos: photos.map(\.id),
      taken: cover.taken,
      verdict: photos.contains { $0.verdict == .food } ? .food : .maybe)
  }

  /// The better-looking photo makes the cover; without a quality rating, the
  /// one that looks most like food; then the earlier one.
  private static func better(_ a: ScanResult, than b: ScanResult) -> Bool {
    let qa = a.fingerprint?.quality ?? -.infinity
    let qb = b.fingerprint?.quality ?? -.infinity
    if qa != qb { return qa > qb }
    if a.score != b.score { return a.score > b.score }
    return (a.taken ?? .distantFuture) < (b.taken ?? .distantFuture)
  }

  static func distance(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count else { return .infinity }
    var sum: Float = 0
    for i in a.indices {
      let d = a[i] - b[i]
      sum += d * d
    }
    return sum.squareRoot()
  }
}
