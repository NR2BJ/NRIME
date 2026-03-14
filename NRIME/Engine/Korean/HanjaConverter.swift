import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class HanjaConverter {
    private var db: OpaquePointer?

    init?() {
        guard let dbPath = Bundle.main.path(forResource: "hanja", ofType: "db") else {
            NSLog("NRIME: hanja.db not found in bundle")
            return nil
        }

        var dbPtr: OpaquePointer?
        let status = sqlite3_open_v2(dbPath, &dbPtr, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK else {
            NSLog("NRIME: Failed to open hanja.db: \(status)")
            return nil
        }
        db = dbPtr
        NSLog("NRIME: hanja.db loaded successfully")
    }

    /// Lookup Hanja candidates for a given Hangul string.
    func lookupCandidates(for hangul: String) -> [(hanja: String, meaning: String)] {
        guard let db = db else { return [] }

        var results: [(String, String)] = []
        var statement: OpaquePointer?

        let query = "SELECT hanja, meaning FROM hanja WHERE hangul = ? ORDER BY frequency DESC LIMIT 50"
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, hangul, -1, SQLITE_TRANSIENT)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let hanjaPtr = sqlite3_column_text(statement, 0),
                      let meaningPtr = sqlite3_column_text(statement, 1) else {
                    continue
                }
                let hanja = String(cString: hanjaPtr)
                let meaning = String(cString: meaningPtr)
                results.append((hanja, meaning))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
}
