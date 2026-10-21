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

  /// Only for food and maybes, to tell repeat shots of a dish apart.
  var fingerprint: PhotoFingerprint? = nil

  /// The `PhotoFingerprinter.model` that made `fingerprint`.
  var fingerprintModel: String? = nil
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
        model TEXT NOT NULL,
        fingerprint BLOB,
        quality REAL,
        fingerprint_model TEXT
      )
      """)
    // Stores from before fingerprints were saved.
    let columns = try columnNames()
    for (column, type) in [
      ("fingerprint", "BLOB"), ("quality", "REAL"), ("fingerprint_model", "TEXT"),
    ] where !columns.contains(column) {
      try exec("ALTER TABLE results ADD COLUMN \(column) \(type)")
    }
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
        "INSERT OR REPLACE INTO results (id, taken, verdict, score, model, "
          + "fingerprint, quality, fingerprint_model) "
          + "VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
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
        if let print = result.fingerprint {
          print.vector.withUnsafeBytes {
            _ = sqlite3_bind_blob(
              statement, 6, $0.baseAddress, Int32($0.count), Self.transient)
          }
          if let quality = print.quality {
            sqlite3_bind_double(statement, 7, Double(quality))
          } else {
            sqlite3_bind_null(statement, 7)
          }
        } else {
          sqlite3_bind_null(statement, 6)
          sqlite3_bind_null(statement, 7)
        }
        if let model = result.fingerprintModel {
          sqlite3_bind_text(statement, 8, model, -1, Self.transient)
        } else {
          sqlite3_bind_null(statement, 8)
        }
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
      "SELECT id, taken, verdict, score, model, fingerprint, quality, "
        + "fingerprint_model FROM results ORDER BY taken DESC")
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
            model: text(statement, 4),
            fingerprint: fingerprint(statement),
            fingerprintModel: sqlite3_column_type(statement, 7) == SQLITE_NULL
              ? nil : text(statement, 7)))
      case SQLITE_DONE:
        return results
      default:
        throw lastError()
      }
    }
  }

  private func fingerprint(_ statement: OpaquePointer?) -> PhotoFingerprint? {
    guard let blob = sqlite3_column_blob(statement, 5) else { return nil }
    let bytes = UnsafeRawBufferPointer(
      start: blob, count: Int(sqlite3_column_bytes(statement, 5)))
    // Copied rather than read in place: SQLite doesn't align blobs.
    var vector = [Float](repeating: 0, count: bytes.count / MemoryLayout<Float>.size)
    vector.withUnsafeMutableBytes { $0.copyMemory(from: bytes) }
    return PhotoFingerprint(
      vector: vector,
      quality: sqlite3_column_type(statement, 6) == SQLITE_NULL
        ? nil : Float(sqlite3_column_double(statement, 6)))
  }

  private func columnNames() throws -> Set<String> {
    let statement = try prepare("PRAGMA table_info(results)")
    defer { sqlite3_finalize(statement) }
    var names: Set<String> = []
    while sqlite3_step(statement) == SQLITE_ROW { names.insert(text(statement, 1)) }
    return names
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
