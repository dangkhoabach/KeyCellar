import Foundation
import GRDB

/// What a backup holds: every item (Trash included), its tags by name, its
/// project by name, and every secret value with its history. Ids travel
/// with the items so a restore on the same machine merges cleanly; projects
/// and tags are matched by name so a restore elsewhere doesn't duplicate them.
public struct BackupPayload: Codable, Equatable, Sendable {
    public struct Secret: Codable, Equatable, Sendable {
        public var field: String
        public var slot: Int
        public var value: Data
        public var createdAt: Date
    }

    public struct Item: Codable, Equatable, Sendable {
        public var item: SecretItem
        public var projectName: String?
        public var tags: [String]
        public var secrets: [Secret]
    }

    public var version = 1
    public var exportedAt: Date
    public var projects: [Project]
    public var items: [Item]
}

public enum BackupMode: Sendable {
    /// Keep local items; for an id present on both sides the newer
    /// `updatedAt` wins.
    case merge
    /// Everything local is purged first.
    case replace
}

public struct ImportSummary: Equatable, Sendable {
    public var imported = 0
    public var skipped = 0
}

/// Export and import of the whole vault through `SecretVault`, so every
/// secret is decrypted by the enclave (one Touch ID for the run, within the
/// sealer's reuse window) and re-sealed on the way back in.
public enum VaultBackup {
    public static func export(vault: SecretVault, passphrase: String) async throws -> Data {
        let payload = try await snapshot(vault: vault)
        var plaintext = try BackupCrypto.encoder.encode(payload)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        return try BackupCrypto.encrypt(plaintext, passphrase: passphrase, itemCount: payload.items.count, createdAt: payload.exportedAt)
    }

    static func snapshot(vault: SecretVault) async throws -> BackupPayload {
        let database = vault.database
        let (items, projects, tagsByItem, blobs) = try await database.dbQueue.read { db in
            let items = try SecretItem.order(Column("title")).fetchAll(db)
            let projects = try Project.fetchAll(db)
            var tagsByItem: [String: [String]] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT it.item_id, t.name FROM item_tags it JOIN tags t ON t.id = it.tag_id ORDER BY t.name") {
                tagsByItem[row["item_id"], default: []].append(row["name"])
            }
            let blobs = try SecretBlob.order(Column("item_id"), Column("field"), Column("slot")).fetchAll(db)
            return (items, projects, tagsByItem, blobs)
        }
        let projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        var blobsByItem: [String: [SecretBlob]] = [:]
        for blob in blobs { blobsByItem[blob.itemId, default: []].append(blob) }

        try await vault.beginAuthenticationSession()
        var out: [BackupPayload.Item] = []
        for item in items {
            var secrets: [BackupPayload.Secret] = []
            for blob in blobsByItem[item.id] ?? [] {
                let value = try await vault.openForBackup(blob)
                secrets.append(.init(field: blob.field, slot: blob.slot, value: value, createdAt: blob.createdAt))
            }
            out.append(.init(item: item, projectName: item.projectId.flatMap { projectNames[$0] }, tags: tagsByItem[item.id] ?? [], secrets: secrets))
        }
        return BackupPayload(exportedAt: Date(), projects: projects, items: out)
    }

    @discardableResult
    public static func `import`(_ file: Data, passphrase: String, mode: BackupMode, into vault: SecretVault) async throws -> ImportSummary {
        var plaintext = try BackupCrypto.decrypt(file, passphrase: passphrase)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        let payload = try BackupCrypto.decoder.decode(BackupPayload.self, from: plaintext)
        return try await restore(payload, mode: mode, into: vault)
    }

    /// Re-seals every secret first (no Touch ID, no writes), then applies the
    /// whole import in one transaction: a failure anywhere leaves the vault
    /// exactly as it was, instead of a Replace that wiped it and stopped.
    static func restore(_ payload: BackupPayload, mode: BackupMode, into vault: SecretVault) async throws -> ImportSummary {
        var prepared: [(entry: BackupPayload.Item, blobs: [SecretBlob])] = []
        for entry in payload.items {
            var blobs: [SecretBlob] = []
            for secret in entry.secrets {
                blobs.append(try await vault.sealForBackup(secret, itemId: entry.item.id))
            }
            prepared.append((entry, blobs))
        }
        let entries = prepared
        let projects = payload.projects.sorted(by: { $0.sortOrder < $1.sortOrder })

        return try await vault.database.dbQueue.write { db in
            if mode == .replace {
                try db.execute(sql: "DELETE FROM items; DELETE FROM projects; DELETE FROM tags;")
            }
            for project in projects {
                var local = try ProjectRepository.findOrCreate(name: project.name, db)
                if local.color == nil, project.color != nil {
                    local.color = project.color
                    try local.update(db)
                }
            }
            let projectIds = Dictionary(uniqueKeysWithValues: try Project.fetchAll(db).map { ($0.name, $0.id) })

            var summary = ImportSummary()
            for (entry, blobs) in entries {
                var item = entry.item
                item.projectId = entry.projectName.flatMap { projectIds[$0] }
                if let existing = try SecretItem.fetchOne(db, key: item.id) {
                    if existing.updatedAt >= item.updatedAt {
                        summary.skipped += 1
                        continue
                    }
                    _ = try SecretItem.deleteOne(db, key: item.id)
                }
                try item.insert(db)
                try ItemRepository.setTags(entry.tags, for: item.id, db)
                for blob in blobs { try blob.insert(db) }
                summary.imported += 1
            }
            try SecretVault.purgeOrphanMarkers(db)
            return summary
        }
    }
}

extension SecretVault {
    /// Decrypts one blob without touching `last_used_at` — an export is not
    /// the user using the item.
    func openForBackup(_ blob: SecretBlob) async throws -> Data {
        try await open(SealedSecret(encapsulatedKey: blob.encapsulatedKey, ciphertext: blob.ciphertext), info: HPKEEnvelope.info(blobId: blob.id))
    }

    /// One backed-up value re-sealed to this vault's key, keeping its slot
    /// and date. Only seals — `VaultBackup.restore` does the inserting.
    func sealForBackup(_ secret: BackupPayload.Secret, itemId: String) async throws -> SecretBlob {
        let blobId = UUID().uuidString
        let sealed = try await seal(secret.value, info: HPKEEnvelope.info(blobId: blobId))
        return SecretBlob(id: blobId, itemId: itemId, field: secret.field, slot: secret.slot,
                          encapsulatedKey: sealed.encapsulatedKey, ciphertext: sealed.ciphertext, createdAt: secret.createdAt)
    }
}
