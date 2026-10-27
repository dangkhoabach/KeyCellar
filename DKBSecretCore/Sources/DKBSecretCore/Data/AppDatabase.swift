import Foundation
import GRDB

/// Opens (or creates) the app's SQLite database and keeps it migrated.
/// Holds metadata and HPKE ciphertext only — never a plaintext secret and
/// never the Secure Enclave key blob (an invariant pinned by
/// `SecretVaultTests.noPlaintextSecretEverLandsInTheDatabase`).
public struct AppDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
    }

    /// In-memory database for tests/previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(dbQueue: DatabaseQueue())
    }

    private init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_baseline") { db in
            try db.execute(sql: """
                CREATE TABLE projects (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL UNIQUE,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    color TEXT
                );

                CREATE TABLE tags (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL UNIQUE
                );

                CREATE TABLE items (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    title TEXT NOT NULL,
                    project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
                    service TEXT,
                    environment TEXT,
                    url TEXT,
                    username TEXT,
                    metadata_json TEXT NOT NULL DEFAULT '{}',
                    favorite INTEGER NOT NULL DEFAULT 0,
                    expires_at TEXT,
                    last_used_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    deleted_at TEXT
                );
                CREATE INDEX items_project ON items(project_id);
                CREATE INDEX items_deleted ON items(deleted_at);

                CREATE TABLE item_tags (
                    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                    tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                    PRIMARY KEY (item_id, tag_id)
                );

                CREATE TABLE secret_blobs (
                    id TEXT PRIMARY KEY,
                    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                    field TEXT NOT NULL,
                    slot INTEGER NOT NULL DEFAULT 0,
                    encapsulated_key BLOB NOT NULL,
                    ciphertext BLOB NOT NULL,
                    created_at TEXT NOT NULL,
                    UNIQUE (item_id, field, slot)
                );

                CREATE TABLE settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                """)
        }

        return migrator
    }
}
