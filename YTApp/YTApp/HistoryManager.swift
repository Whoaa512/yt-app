import Foundation
import SQLite3

struct HistoryEntry {
    var id: Int64
    var url: String
    var title: String?
    var duration: String?
    var visitedAt: Date
}

class HistoryManager {
    static let shared = HistoryManager()
    private var db: OpaquePointer?
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func setup() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("YTApp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("history.db").path

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }

        let sql = """
        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            title TEXT,
            duration TEXT,
            visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_history_visited_at ON history(visited_at DESC);
        CREATE INDEX IF NOT EXISTS idx_history_title ON history(title);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func recordVisit(url: String, title: String?, duration: String?) {
        guard let db = db else { return }

        // Deduplicate: if same URL within 60 seconds, update instead
        let checkSQL = "SELECT id FROM history WHERE url = ? AND visited_at > datetime('now', '-1 minute') LIMIT 1"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, checkSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (url as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let existingId = sqlite3_column_int64(stmt, 0)
                sqlite3_finalize(stmt)
                let updateSQL = "UPDATE history SET title = ?, duration = ?, visited_at = CURRENT_TIMESTAMP WHERE id = ?"
                var updateStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(updateStmt, 1, (title as NSString?)?.utf8String, -1, nil)
                    sqlite3_bind_text(updateStmt, 2, (duration as NSString?)?.utf8String, -1, nil)
                    sqlite3_bind_int64(updateStmt, 3, existingId)
                    sqlite3_step(updateStmt)
                }
                sqlite3_finalize(updateStmt)
                return
            }
        }
        sqlite3_finalize(stmt)

        let insertSQL = "INSERT INTO history (url, title, duration) VALUES (?, ?, ?)"
        var insertStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStmt, 1, (url as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStmt, 2, (title as NSString?)?.utf8String, -1, nil)
            sqlite3_bind_text(insertStmt, 3, (duration as NSString?)?.utf8String, -1, nil)
            sqlite3_step(insertStmt)
        }
        sqlite3_finalize(insertStmt)
    }

    func search(query: String = "", limit: Int = 200) -> [HistoryEntry] {
        guard let db = db else { return [] }
        var results: [HistoryEntry] = []
        let sql: String
        if query.isEmpty {
            sql = "SELECT id, url, title, duration, visited_at FROM history ORDER BY visited_at DESC LIMIT ?"
        } else {
            sql = "SELECT id, url, title, duration, visited_at FROM history WHERE title LIKE ? OR url LIKE ? ORDER BY visited_at DESC LIMIT ?"
        }

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if query.isEmpty {
                sqlite3_bind_int(stmt, 1, Int32(limit))
            } else {
                let pattern = "%\(query)%"
                sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 3, Int32(limit))
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let url = String(cString: sqlite3_column_text(stmt, 1))
                let title = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let duration = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                let visitedAtStr = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                let visitedAt = visitedAtStr.flatMap { dateFormatter.date(from: $0) } ?? Date()
                results.append(HistoryEntry(id: id, url: url, title: title, duration: duration, visitedAt: visitedAt))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    func delete(id: Int64) {
        guard let db = db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM history WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func clearAll() {
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM history", nil, nil, nil)
    }
}
