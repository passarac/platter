import Foundation
import SQLite3

/// One photo's verdict, as saved.
struct ScanResult: Equatable {
  /// The photo's `PHAsset.localIdentifier`.
  let id: String
  let taken: Date?
  let verdict: FoodVerdict
  let score: Float
  let model: String
}

struct ScanStoreError: Error {
  let message: String
}

/// Every photo's verdict, saved in SQLite so each photo is classified once
/// per model and a scan that's cut short picks up where it stopped.
final class ScanStore {
  private var db: OpaquePointer?

  /// Tells SQLite to copy bound strings, which Swift may free straight after.
  private static let transient = unsafeBitCast(
    -1, to: sqlite3_destructor_type.self)

  init(url: URL) throws {
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
      defer { sqlite3_close(db) }
      throw lastError()
    }
    try exec(
      """
      CREATE TABLE IF NOT EXISTS results (
        id TEXT PRIMARY KEY,
        taken REAL,
        verdict TEXT NOT NULL,
        score REAL NOT NULL,
        model TEXT NOT NULL
      )
      """)
  }

  deinit { sqlite3_close(db) }

  /// The app's store, in Application Support. Left out of backups: it can
  /// always be rebuilt by scanning again.
  static func standard() throws -> ScanStore {
    var dir = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try dir.setResourceValues(values)
    return try ScanStore(url: dir.appendingPathComponent("food_scan.sqlite"))
  }

  /// Saves `results`, replacing any earlier result for the same photo.
  func save(_ results: [ScanResult]) throws {
    guard !results.isEmpty else { return }
    try exec("BEGIN")
    do {
      let statement = try prepare(
        "INSERT OR REPLACE INTO results (id, taken, verdict, score, model) "
          + "VALUES (?, ?, ?, ?, ?)")
      defer { sqlite3_finalize(statement) }
      for result in results {
        sqlite3_bind_text(statement, 1, result.id, -1, Self.transient)
        if let taken = result.taken {
          sqlite3_bind_double(statement, 2, taken.timeIntervalSince1970)
        } else {
          sqlite3_bind_null(statement, 2)
        }
        sqlite3_bind_text(
          statement, 3, result.verdict.rawValue, -1, Self.transient)
        sqlite3_bind_double(statement, 4, Double(result.score))
        sqlite3_bind_text(statement, 5, result.model, -1, Self.transient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        sqlite3_reset(statement)
      }
      try exec("COMMIT")
    } catch {
      try? exec("ROLLBACK")
      throw error
    }
  }

  /// Every saved result, newest photo first.
  func all() throws -> [ScanResult] {
    let statement = try prepare(
      "SELECT id, taken, verdict, score, model FROM results "
        + "ORDER BY taken DESC")
    defer { sqlite3_finalize(statement) }
    var results: [ScanResult] = []
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW:
        guard
          let verdict = FoodVerdict(rawValue: text(statement, 2))
        else { continue }
        results.append(
          ScanResult(
            id: text(statement, 0),
            taken: sqlite3_column_type(statement, 1) == SQLITE_NULL
              ? nil
              : Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            verdict: verdict,
            score: Float(sqlite3_column_double(statement, 3)),
            model: text(statement, 4)))
      case SQLITE_DONE:
        return results
      default:
        throw lastError()
      }
    }
  }

  private func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
  }

  private func exec(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw lastError()
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw lastError()
    }
    return statement
  }

  private func lastError() -> ScanStoreError {
    ScanStoreError(message: String(cString: sqlite3_errmsg(db)))
  }
}
