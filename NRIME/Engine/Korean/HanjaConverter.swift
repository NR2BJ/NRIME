import Foundation
import InputMethodKit
import SQLite3

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
            sqlite3_bind_text(statement, 1, (hangul as NSString).utf8String, -1, nil)
            while sqlite3_step(statement) == SQLITE_ROW {
                let hanja = String(cString: sqlite3_column_text(statement, 0))
                let meaning = String(cString: sqlite3_column_text(statement, 1))
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
