import Foundation
import GRDB

public enum VaultError: Error, Equatable {
    case itemNotFound(String)
    case secretNotFound(itemId: String, field: String, slot: Int)
}

/// The one door to secret values. Metadata reads go through
/// `ItemRepository` directly; every write that involves a secret, and every
/// read of one, goes through here so sealing, history and `last_used_at`
/// have a single implementation.
///
/// Sealing needs only the public key, so create/update/rotate never prompt;
/// `reveal` is the only call that reaches the Secure Enclave.
public actor SecretVault {
    public let database: AppDatabase
    private let sealer: any SecretSealing

    public init(database: AppDatabase, sealer: any SecretSealing) {
        self.database = database
        self.sealer = sealer
    }

    // MARK: Create / update

    /// `secrets` maps field key → value for every secret field the item has.
    public func create(_ item: SecretItem, tags: [String] = [], secrets: [String: SecretBytes]) async throws {
        let blobs = try await seal(secrets, itemId: item.id)
        try await database.dbQueue.write { db in
            try item.insert(db)
            try ItemRepository.setTags(tags, for: item.id, db)
            for blob in blobs { try blob.insert(db) }
        }
    }

    /// Metadata + tags only. Secret values change through `setSecret` /
    /// `rotate` / `deleteSecret`.
    public func updateMetadata(_ item: SecretItem, tags: [String]) async throws {
        var item = item
        item.updatedAt = Date()
        let updated = item
        try await database.dbQueue.write { db in
            try updated.update(db)
            try ItemRepository.setTags(tags, for: updated.id, db)
        }
    }

    /// Replaces the current value without keeping the old one — editing a
    /// typo, or a field the user never considers "rotated".
    public func setSecret(itemId: String, field: String, value: SecretBytes) async throws {
        let blob = try await seal(value, itemId: itemId, field: field)
        try await database.dbQueue.write { db in
            try Self.requireItem(itemId, db)
            try db.execute(sql: "DELETE FROM secret_blobs WHERE item_id = ? AND field = ? AND slot = 0", arguments: [itemId, field])
            try blob.insert(db)
            try Self.touchUpdated(itemId, db)
        }
    }

    /// The old value becomes history slot 1, older ones shift down, and
    /// anything past `SecretBlob.historyLimit` is dropped.
    public func rotate(itemId: String, field: String, newValue: SecretBytes) async throws {
        let blob = try await seal(newValue, itemId: itemId, field: field)
        try await database.dbQueue.write { db in
            try Self.requireItem(itemId, db)
            try db.execute(
                sql: "DELETE FROM secret_blobs WHERE item_id = ? AND field = ? AND slot >= ?",
                arguments: [itemId, field, SecretBlob.historyLimit]
            )
            // Two steps through negative slots: a single `slot = slot + 1`
            // trips the UNIQUE(item_id, field, slot) constraint row by row.
            try db.execute(sql: "UPDATE secret_blobs SET slot = -(slot + 1) WHERE item_id = ? AND field = ?", arguments: [itemId, field])
            try db.execute(sql: "UPDATE secret_blobs SET slot = -slot WHERE item_id = ? AND field = ? AND slot < 0", arguments: [itemId, field])
            try blob.insert(db)
            try Self.touchUpdated(itemId, db)
        }
    }

    /// Rotation and "mark as rotated" both reset the expiry on their own.
    public func setExpiry(itemId: String, to date: Date?) async throws {
        try await database.dbQueue.write { db in
            try Self.requireItem(itemId, db)
            try db.execute(sql: "UPDATE items SET expires_at = ?, updated_at = ? WHERE id = ?", arguments: [date, Date(), itemId])
        }
    }

    /// Removes the field and its history — an `envSet` KEY the user deleted.
    public func deleteSecret(itemId: String, field: String) async throws {
        try await database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM secret_blobs WHERE item_id = ? AND field = ?", arguments: [itemId, field])
            try Self.touchUpdated(itemId, db)
        }
    }

    // MARK: Reveal

    /// The only path from ciphertext to plaintext. Slot 0 marks the item as
    /// used; reading history does not.
    public func reveal(itemId: String, field: String, slot: Int = 0) async throws -> SecretBytes {
        let blob = try await database.dbQueue.read { db in
            try SecretBlob
                .filter(Column("item_id") == itemId && Column("field") == field && Column("slot") == slot)
                .fetchOne(db)
        }
        guard let blob else { throw VaultError.secretNotFound(itemId: itemId, field: field, slot: slot) }

        let sealed = SealedSecret(encapsulatedKey: blob.encapsulatedKey, ciphertext: blob.ciphertext)
        let plaintext = try await sealer.open(sealed, info: HPKEEnvelope.info(blobId: blob.id))
        if slot == 0 {
            try await database.dbQueue.write { db in
                try db.execute(sql: "UPDATE items SET last_used_at = ? WHERE id = ?", arguments: [Date(), itemId])
            }
        }
        return SecretBytes(plaintext)
    }

    /// Touch ID now; the reveals that follow ride on it (see `SecretSealing`).
    public func beginAuthenticationSession() async throws {
        try await sealer.beginAuthenticationSession()
    }

    public func endAuthenticationSession() async {
        await sealer.endAuthenticationSession()
    }

    // MARK: Trash

    public func moveToTrash(itemId: String) async throws {
        try await database.dbQueue.write { db in
            try Self.requireItem(itemId, db)
            try db.execute(sql: "UPDATE items SET deleted_at = ? WHERE id = ?", arguments: [Date(), itemId])
        }
    }

    public func restore(itemId: String) async throws {
        try await database.dbQueue.write { db in
            try Self.requireItem(itemId, db)
            try db.execute(sql: "UPDATE items SET deleted_at = NULL WHERE id = ?", arguments: [itemId])
        }
    }

    /// Hard delete. Blobs and tag links go with the row (`ON DELETE CASCADE`).
    public func purge(itemId: String) async throws {
        try await database.dbQueue.write { db in
            try Self.requireItem(itemId, db)
            _ = try SecretItem.deleteOne(db, key: itemId)
            try Self.purgeOrphanMarkers(db)
        }
    }

    /// Hard-deletes everything that has sat in the Trash longer than `days`.
    @discardableResult
    public func purgeTrash(olderThan days: Int = 30, now: Date = Date()) async throws -> Int {
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM items WHERE deleted_at IS NOT NULL AND deleted_at <= ?",
                arguments: [now.addingTimeInterval(-TimeInterval(days) * 86_400)]
            )
            let purged = db.changesCount
            try Self.purgeOrphanMarkers(db)
            return purged
        }
    }

    /// Expiry reminders record `notified.<itemId>.…` markers in `settings`
    /// (see `ExpiryMilestones`); drop the ones whose item no longer exists.
    static func purgeOrphanMarkers(_ db: Database) throws {
        try db.execute(sql: """
            DELETE FROM settings WHERE key LIKE 'notified.%'
              AND NOT EXISTS (SELECT 1 FROM items WHERE settings.key LIKE 'notified.' || items.id || '.%')
            """)
    }

    // MARK: Helpers

    /// Raw sealer access for `VaultBackup`, which needs seal/open without the
    /// per-item bookkeeping the public API adds.
    func seal(_ plaintext: Data, info: Data) async throws -> SealedSecret {
        try await sealer.seal(plaintext, info: info)
    }

    func open(_ sealed: SealedSecret, info: Data) async throws -> Data {
        try await sealer.open(sealed, info: info)
    }

    private func seal(_ secrets: [String: SecretBytes], itemId: String) async throws -> [SecretBlob] {
        var blobs: [SecretBlob] = []
        for (field, value) in secrets {
            blobs.append(try await seal(value, itemId: itemId, field: field))
        }
        return blobs
    }

    private func seal(_ value: SecretBytes, itemId: String, field: String) async throws -> SecretBlob {
        let blobId = UUID().uuidString
        let sealed = try await sealer.seal(value.data, info: HPKEEnvelope.info(blobId: blobId))
        return SecretBlob(
            id: blobId, itemId: itemId, field: field, slot: 0,
            encapsulatedKey: sealed.encapsulatedKey, ciphertext: sealed.ciphertext
        )
    }

    private static func requireItem(_ itemId: String, _ db: Database) throws {
        guard try SecretItem.exists(db, key: itemId) else { throw VaultError.itemNotFound(itemId) }
    }

    private static func touchUpdated(_ itemId: String, _ db: Database) throws {
        try db.execute(sql: "UPDATE items SET updated_at = ? WHERE id = ?", arguments: [Date(), itemId])
    }
}
