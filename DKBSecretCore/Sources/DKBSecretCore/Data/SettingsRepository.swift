import Foundation
import GRDB

/// Plain key/value settings. Values are strings; typed accessors live with
/// the feature that owns the setting (auto-lock policy, backup schedule…).
public struct SettingsRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func get(_ key: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    public func set(_ key: String, _ value: String?) throws {
        try dbQueue.write { db in
            if let value {
                try db.execute(
                    sql: "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                    arguments: [key, value]
                )
            } else {
                try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: [key])
            }
        }
    }
}
