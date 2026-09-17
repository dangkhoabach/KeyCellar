import CryptoKit
import Foundation
import GRDB
import Testing
@testable import DKBSecretCore

@Suite struct SecretVaultTests {
    @Test func createThenRevealRoundTripsEveryField() async throws {
        let t = try TestVault()
        let item = makeItem("ssh", kind: .sshKey)
        try await t.vault.create(item, secrets: [
            "privateKey": SecretBytes("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----"),
            "passphrase": SecretBytes("hunter2"),
        ])
        #expect(try await t.vault.reveal(itemId: item.id, field: "passphrase").string == "hunter2")
        #expect(try await t.vault.reveal(itemId: item.id, field: "privateKey").string.hasPrefix("-----BEGIN"))
    }

    @Test func revealMarksTheItemUsedButHistoryDoesNot() async throws {
        let t = try TestVault()
        let item = makeItem("x")
        try await t.vault.create(item, secrets: ["key": SecretBytes("v1")])
        #expect(try t.items.fetch(id: item.id)?.lastUsedAt == nil)
        try await t.vault.rotate(itemId: item.id, field: "key", newValue: SecretBytes("v2"))
        _ = try await t.vault.reveal(itemId: item.id, field: "key", slot: 1)
        #expect(try t.items.fetch(id: item.id)?.lastUsedAt == nil)
        _ = try await t.vault.reveal(itemId: item.id, field: "key")
        #expect(try t.items.fetch(id: item.id)?.lastUsedAt != nil)
    }

    @Test func revealingAMissingFieldThrows() async throws {
        let t = try TestVault()
        let item = makeItem("x")
        try await t.vault.create(item, secrets: ["key": SecretBytes("v")])
        await #expect(throws: VaultError.secretNotFound(itemId: item.id, field: "nope", slot: 0)) {
            _ = try await t.vault.reveal(itemId: item.id, field: "nope")
        }
    }

    @Test func setSecretReplacesWithoutHistory() async throws {
        let t = try TestVault()
        let item = makeItem("x")
        try await t.vault.create(item, secrets: ["key": SecretBytes("v1")])
        try await t.vault.setSecret(itemId: item.id, field: "key", value: SecretBytes("v2"))
        #expect(try await t.vault.reveal(itemId: item.id, field: "key").string == "v2")
        #expect(try t.items.blobs(for: item.id).count == 1)
    }

    @Test func rotateKeepsAtMostFiveOldValuesNewestFirst() async throws {
        let t = try TestVault()
        let item = makeItem("x")
        try await t.vault.create(item, secrets: ["key": SecretBytes("v0")])
        for i in 1...7 {
            try await t.vault.rotate(itemId: item.id, field: "key", newValue: SecretBytes("v\(i)"))
        }
        let blobs = try t.items.blobs(for: item.id)
        #expect(blobs.map(\.slot) == [0, 1, 2, 3, 4, 5])
        #expect(try await t.vault.reveal(itemId: item.id, field: "key").string == "v7")
        #expect(try await t.vault.reveal(itemId: item.id, field: "key", slot: 1).string == "v6")
        #expect(try await t.vault.reveal(itemId: item.id, field: "key", slot: 5).string == "v2")
    }

    @Test func deleteSecretRemovesTheFieldAndItsHistory() async throws {
        let t = try TestVault()
        let item = makeItem("env", kind: .envSet)
        try await t.vault.create(item, secrets: ["env.A": SecretBytes("1"), "env.B": SecretBytes("2")])
        try await t.vault.rotate(itemId: item.id, field: "env.A", newValue: SecretBytes("1b"))
        try await t.vault.deleteSecret(itemId: item.id, field: "env.A")
        #expect(try t.items.blobs(for: item.id).map(\.field) == ["env.B"])
    }

    @Test func trashRestoreAndPurge() async throws {
        let t = try TestVault()
        let item = makeItem("x")
        try await t.vault.create(item, tags: ["t"], secrets: ["key": SecretBytes("v")])
        try await t.vault.moveToTrash(itemId: item.id)
        #expect(try t.items.fetch(ItemQuery(scope: .all)).isEmpty)
        #expect(try t.items.fetch(ItemQuery(scope: .trash)).count == 1)
        // Still revealable from the Trash — nothing was destroyed yet.
        #expect(try await t.vault.reveal(itemId: item.id, field: "key").string == "v")
        try await t.vault.restore(itemId: item.id)
        #expect(try t.items.fetch(ItemQuery(scope: .all)).count == 1)
        try await t.vault.purge(itemId: item.id)
        let leftovers = try await t.database.dbQueue.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM secret_blobs") ?? -1,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_tags") ?? -1)
        }
        #expect(leftovers == (0, 0), "blobs and tag links must cascade")
    }

    @Test func purgeTrashOnlyRemovesOldEntries() async throws {
        let t = try TestVault()
        let old = makeItem("old"), fresh = makeItem("fresh")
        try await t.vault.create(old, secrets: ["key": SecretBytes("a")])
        try await t.vault.create(fresh, secrets: ["key": SecretBytes("b")])
        try await t.vault.moveToTrash(itemId: old.id)
        try await t.vault.moveToTrash(itemId: fresh.id)
        try await t.database.dbQueue.write { db in
            try db.execute(sql: "UPDATE items SET deleted_at = ? WHERE id = ?",
                           arguments: [Date().addingTimeInterval(-40 * 86_400), old.id])
        }
        let purged = try await t.vault.purgeTrash(olderThan: 30)
        #expect(purged == 1)
        #expect(try t.items.fetch(ItemQuery(scope: .trash)).map(\.title) == ["fresh"])
    }

    @Test func operationsOnAMissingItemThrow() async throws {
        let t = try TestVault()
        await #expect(throws: VaultError.itemNotFound("ghost")) {
            try await t.vault.setSecret(itemId: "ghost", field: "key", value: SecretBytes("v"))
        }
        await #expect(throws: VaultError.itemNotFound("ghost")) { try await t.vault.moveToTrash(itemId: "ghost") }
    }

    @Test func aBlobMovedToAnotherRowRefusesToOpen() async throws {
        let t = try TestVault()
        let a = makeItem("a"), b = makeItem("b")
        try await t.vault.create(a, secrets: ["key": SecretBytes("secret-a")])
        try await t.vault.create(b, secrets: ["key": SecretBytes("secret-b")])
        // Attacker with write access to the file: copy a's ciphertext under b's blob id.
        try await t.database.dbQueue.write { db in
            let blobA = try SecretBlob.filter(Column("item_id") == a.id).fetchOne(db)!
            try db.execute(sql: "UPDATE secret_blobs SET encapsulated_key = ?, ciphertext = ? WHERE item_id = ?",
                           arguments: [blobA.encapsulatedKey, blobA.ciphertext, b.id])
        }
        await #expect(throws: (any Error).self) {
            _ = try await t.vault.reveal(itemId: b.id, field: "key")
        }
        #expect(try await t.vault.reveal(itemId: a.id, field: "key").string == "secret-a")
    }

    @Test func noPlaintextSecretEverLandsInTheDatabase() async throws {
        let t = try TestVault()
        let canary = "CANARY-9f3a1c7e-do-not-store"
        let item = makeItem("x", kind: .login, username: "user")
        try await t.vault.create(item, tags: ["t"], secrets: ["password": SecretBytes(canary), "notes": SecretBytes("note \(canary)")])
        try await t.vault.rotate(itemId: item.id, field: "password", newValue: SecretBytes("\(canary)-2"))
        _ = try await t.vault.reveal(itemId: item.id, field: "password")
        let dump = try t.database.dumpAllValues()
        #expect(dump.range(of: Data(canary.utf8)) == nil)
        #expect(!dump.isEmpty)
    }

    @Test func endAuthenticationSessionIsForwardedToTheSealer() async throws {
        final class Spy: SecretSealing, @unchecked Sendable {
            var ended = 0
            let inner = SoftwareSealer()
            func seal(_ p: Data, info: Data) throws -> SealedSecret { try inner.seal(p, info: info) }
            func open(_ s: SealedSecret, info: Data) throws -> Data { try inner.open(s, info: info) }
            func beginAuthenticationSession() {}
            func endAuthenticationSession() { ended += 1 }
        }
        let spy = Spy()
        let vault = SecretVault(database: try AppDatabase.inMemory(), sealer: spy)
        await vault.endAuthenticationSession()
        #expect(spy.ended == 1)
    }
}
