import CryptoKit
import Foundation
import Testing
@testable import KeyCellarCore

@Suite struct BackupCryptoTests {
    private let passphrase = "correct horse battery staple"

    @Test func roundTrip() throws {
        let file = try BackupCrypto.encrypt(Data("payload".utf8), passphrase: passphrase, itemCount: 3)
        let header = try BackupCrypto.readHeader(file)
        #expect(header.itemCount == 3)
        #expect(header.iterations == 600_000)
        #expect(header.salt.count == 32)
        #expect(try BackupCrypto.decrypt(file, passphrase: passphrase) == Data("payload".utf8))
    }

    @Test func wrongPassphraseAndTamperingAreRefused() throws {
        let file = try BackupCrypto.encrypt(Data("payload".utf8), passphrase: passphrase, itemCount: 1)
        #expect(throws: BackupError.wrongPassphraseOrCorrupt) { _ = try BackupCrypto.decrypt(file, passphrase: "not the passphrase") }

        var body = file
        body[body.count - 1] ^= 0x01
        #expect(throws: BackupError.wrongPassphraseOrCorrupt) { _ = try BackupCrypto.decrypt(body, passphrase: passphrase) }

        // Flip a byte inside the plaintext header: the tag check must fail
        // because the header is the additional authenticated data.
        var header = file
        let index = file.firstRange(of: Data("\"itemCount\":1".utf8))!.upperBound - 1
        header[index] = UInt8(ascii: "7")
        #expect(throws: BackupError.wrongPassphraseOrCorrupt) { _ = try BackupCrypto.decrypt(header, passphrase: passphrase) }
    }

    @Test func rejectsForeignFilesAndShortPassphrases() throws {
        #expect(throws: BackupError.notABackupFile) { _ = try BackupCrypto.readHeader(Data("hello".utf8)) }
        #expect(throws: BackupError.notABackupFile) { _ = try BackupCrypto.readHeader(Data([0, 0, 0, 200, 1, 2])) }
        #expect(throws: BackupError.passphraseTooShort) { _ = try BackupCrypto.encrypt(Data(), passphrase: "short", itemCount: 0) }
    }

    /// Pins the KDF and container layout: if this changes, old backups stop
    /// opening, so the change must be a deliberate new format version.
    @Test func fixedVector() throws {
        let salt = Data(repeating: 0x42, count: 32)
        let header = BackupCrypto.Header(iterations: 1_000, salt: salt, createdAt: Date(timeIntervalSince1970: 1_700_000_000), itemCount: 1)
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 0x24, count: 12))
        let file = try BackupCrypto.encrypt(Data("vector".utf8), passphrase: passphrase, header: header, nonce: nonce)
        let hex = file.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "000000b17b22637265617465644174223a22323032332d31312d31345432323a31333a32305a222c22666f726d6174223a22646b62736563726574222c226974656d436f756e74223a312c22697465726174696f6e73223a313030302c226b6466223a2270626b6466322d736861323536222c2273616c74223a22516b4a43516b4a43516b4a43516b4a43516b4a43516b4a43516b4a43516b4a43516b4a43516b4a43516b493d222c2276657273696f6e223a317d242424242424242424242424702b2d59291393231083e0ef796fb8c43265072a77c5",
                "layout or KDF changed — bump the format version instead of editing v1")
        #expect(try BackupCrypto.decrypt(file, passphrase: passphrase) == Data("vector".utf8))
    }
}

@Suite struct VaultBackupTests {
    private let passphrase = "a passphrase long enough"

    private func seededVault() async throws -> TestVault {
        let t = try TestVault()
        let project = try ProjectRepository(dbQueue: t.database.dbQueue).findOrCreate(name: "CaPheSuaDa")
        let a = makeItem("Resend", service: "Resend", projectId: project.id)
        try await t.vault.create(a, tags: ["email"], secrets: ["key": SecretBytes("re_1"), "notes": SecretBytes("n")])
        try await t.vault.rotate(itemId: a.id, field: "key", newValue: SecretBytes("re_2"))
        let b = makeItem("Trashed", kind: .secureNote)
        try await t.vault.create(b, secrets: ["body": SecretBytes("gone")])
        try await t.vault.moveToTrash(itemId: b.id)
        return t
    }

    @Test func exportThenImportIntoAnEmptyVaultRestoresEverything() async throws {
        let source = try await seededVault()
        let file = try await VaultBackup.export(vault: source.vault, passphrase: passphrase)
        #expect(try BackupCrypto.readHeader(file).itemCount == 2)

        let target = try TestVault()
        let summary = try await VaultBackup.import(file, passphrase: passphrase, mode: .merge, into: target.vault)
        #expect(summary == ImportSummary(imported: 2, skipped: 0))

        let resend = try #require(try target.items.fetch(ItemQuery(search: "Resend")).first)
        #expect(try target.items.tags(for: resend.id).map(\.name) == ["email"])
        #expect(try ProjectRepository(dbQueue: target.database.dbQueue).all().map(\.name) == ["CaPheSuaDa"])
        #expect(resend.projectId != nil)
        #expect(try await target.vault.reveal(itemId: resend.id, field: "key").string == "re_2")
        #expect(try await target.vault.reveal(itemId: resend.id, field: "key", slot: 1).string == "re_1")
        #expect(try await target.vault.reveal(itemId: resend.id, field: "notes").string == "n")
        #expect(try target.items.fetch(ItemQuery(scope: .trash)).map(\.title) == ["Trashed"])
    }

    @Test func exportDoesNotMarkItemsAsUsed() async throws {
        let source = try await seededVault()
        _ = try await VaultBackup.export(vault: source.vault, passphrase: passphrase)
        #expect(try source.items.fetch(ItemQuery()).allSatisfy { $0.lastUsedAt == nil })
    }

    @Test func mergeKeepsTheNewerSideAndReplaceWipesFirst() async throws {
        let source = try await seededVault()
        let file = try await VaultBackup.export(vault: source.vault, passphrase: passphrase)

        // Edit locally after the backup: local is newer → must be kept.
        var local = try #require(try source.items.fetch(ItemQuery(search: "Resend")).first)
        try await Task.sleep(for: .milliseconds(5))
        local.title = "Resend (edited)"
        try await source.vault.updateMetadata(local, tags: ["email"])
        let extra = makeItem("Local only")
        try await source.vault.create(extra, secrets: ["key": SecretBytes("x")])

        let merged = try await VaultBackup.import(file, passphrase: passphrase, mode: .merge, into: source.vault)
        #expect(merged == ImportSummary(imported: 0, skipped: 2))
        #expect(try source.items.fetch(id: local.id)?.title == "Resend (edited)")
        #expect(try source.items.fetch(ItemQuery()).count == 2)

        let replaced = try await VaultBackup.import(file, passphrase: passphrase, mode: .replace, into: source.vault)
        #expect(replaced == ImportSummary(imported: 2, skipped: 0))
        #expect(try source.items.fetch(id: local.id)?.title == "Resend")
        #expect(try source.items.fetch(id: extra.id) == nil)
    }

    @Test func aFailedImportLeavesTheVaultUntouched() async throws {
        let source = try await seededVault()
        let file = try await VaultBackup.export(vault: source.vault, passphrase: passphrase)

        // The target's sealer gives up part-way through re-sealing the
        // backup: with Replace, the old contents must still be there.
        let target = try TestVault(sealer: FlakySealer(failAfter: 1))
        let keep = makeItem("Keep me")
        try await target.vault.create(keep, secrets: ["key": SecretBytes("k")])
        let before = try target.database.dumpAllValues()

        await #expect(throws: FlakySealer.SealFailed.self) {
            try await VaultBackup.import(file, passphrase: passphrase, mode: .replace, into: target.vault)
        }
        #expect(try target.database.dumpAllValues() == before, "a failed import must not change a single row")
        #expect(try target.items.fetch(ItemQuery()).map(\.title) == ["Keep me"])
    }

    @Test func olderBackupOverwritesAnOlderLocalCopy() async throws {
        let source = try await seededVault()
        var item = try #require(try source.items.fetch(ItemQuery(search: "Resend")).first)
        try await Task.sleep(for: .milliseconds(5))
        item.title = "Newer in backup"
        try await source.vault.updateMetadata(item, tags: [])
        try await source.vault.setSecret(itemId: item.id, field: "key", value: SecretBytes("re_3"))
        let file = try await VaultBackup.export(vault: source.vault, passphrase: passphrase)

        // Roll the local copy back so the backup is the newer one.
        let itemId = item.id
        try await source.database.dbQueue.write { db in
            try db.execute(sql: "UPDATE items SET title = 'stale', updated_at = ? WHERE id = ?",
                           arguments: [Date(timeIntervalSince1970: 0), itemId])
        }
        let summary = try await VaultBackup.import(file, passphrase: passphrase, mode: .merge, into: source.vault)
        #expect(summary.imported == 1)
        #expect(try source.items.fetch(id: item.id)?.title == "Newer in backup")
        #expect(try await source.vault.reveal(itemId: item.id, field: "key").string == "re_3")
    }
}
