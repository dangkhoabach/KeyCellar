import GRDB
import Testing
@testable import KeyCellarCore

@Suite struct AppDatabaseTests {
    @Test func freshDatabaseHasEveryTable() throws {
        let db = try AppDatabase.inMemory()
        let tables = try db.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }
        #expect(tables.contains("items"))
        #expect(tables.contains("secret_blobs"))
        #expect(tables.contains("projects"))
        #expect(tables.contains("tags"))
        #expect(tables.contains("item_tags"))
        #expect(tables.contains("settings"))
    }

    @Test func migrationIsIdempotent() throws {
        let db = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(db.dbQueue)
        #expect(try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM items") } == 0)
    }

    @Test func foreignKeysAreEnforced() throws {
        let db = try AppDatabase.inMemory()
        #expect(throws: DatabaseError.self) {
            try db.dbQueue.write { db in
                try db.execute(sql: """
                    INSERT INTO secret_blobs (id, item_id, field, slot, encapsulated_key, ciphertext, created_at)
                    VALUES ('b', 'missing-item', 'key', 0, x'00', x'00', '2026-01-01')
                    """)
            }
        }
    }
}
