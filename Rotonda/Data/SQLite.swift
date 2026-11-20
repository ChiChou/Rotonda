import Foundation
import SQLite3

/// Minimal synchronous SQLite wrapper for the bundled, read-only content database. It is small
/// and local, so all access happens on the main actor without a connection pool.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String, readOnly: Bool) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(handle)
            throw NSError(domain: "SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    deinit { sqlite3_close(handle) }

    func query<T>(_ sql: String, _ arguments: [Any?] = [], map: (SQLiteRow) -> T) -> [T] {
        guard let statement = prepare(sql, arguments) else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(map(SQLiteRow(statement: statement)))
        }
        return result
    }

    func first<T>(_ sql: String, _ arguments: [Any?] = [], map: (SQLiteRow) -> T) -> T? {
        query(sql, arguments, map: map).first
    }

    func int(_ sql: String, _ arguments: [Any?] = []) -> Int {
        first(sql, arguments) { $0.int(0) } ?? 0
    }

    func execute(_ sql: String, _ arguments: [Any?] = []) {
        guard let statement = prepare(sql, arguments) else { return }
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) != SQLITE_DONE { logError(sql) }
    }

    func executeScript(_ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            if let error { print("SQLite error: \(String(cString: error))") }
            sqlite3_free(error)
        }
    }

    private func prepare(_ sql: String, _ arguments: [Any?]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            logError(sql)
            return nil
        }
        for (offset, value) in arguments.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let value as Int: sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Bool: sqlite3_bind_int(statement, index, value ? 1 : 0)
            case let value as Double: sqlite3_bind_double(statement, index, value)
            case let value as String: sqlite3_bind_text(statement, index, value, -1, Self.transient)
            default: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func logError(_ sql: String) {
        print("SQLite error: \(String(cString: sqlite3_errmsg(handle))) in \(sql.prefix(120))")
    }
}

struct SQLiteRow {
    let statement: OpaquePointer?

    func int(_ index: Int32) -> Int { Int(sqlite3_column_int64(statement, index)) }
    func double(_ index: Int32) -> Double { sqlite3_column_double(statement, index) }
    func bool(_ index: Int32) -> Bool { sqlite3_column_int(statement, index) != 0 }
    func isNull(_ index: Int32) -> Bool { sqlite3_column_type(statement, index) == SQLITE_NULL }

    func text(_ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    func optionalText(_ index: Int32) -> String? {
        let value = text(index)
        return value.isEmpty ? nil : value
    }

    func optionalInt(_ index: Int32) -> Int? { isNull(index) ? nil : int(index) }
}
