import Foundation
import GRDB
@testable import KeyCellarCore

/// In-memory database + software master key: the whole Core stack minus
/// the Secure Enclave.
struct TestVault {
    let database: AppDatabase
    let vault: SecretVault
    let items: ItemRepository

    init(sealer: any SecretSealing = SoftwareSealer()) throws {
        database = try AppDatabase.inMemory()
        vault = SecretVault(database: database, sealer: sealer)
        items = ItemRepository(dbQueue: database.dbQueue)
    }
}

/// Seals normally until `failAfter` seals have happened, then throws — for
/// proving that a half-failed import changes nothing.
final class FlakySealer: SecretSealing, @unchecked Sendable {
    struct SealFailed: Error {}
    private let inner = SoftwareSealer()
    private let lock = NSLock()
    private var seals = 0
    let failAfter: Int

    init(failAfter: Int) { self.failAfter = failAfter }

    func seal(_ plaintext: Data, info: Data) throws -> SealedSecret {
        let n = lock.withLock { seals += 1; return seals }
        if n > failAfter { throw SealFailed() }
        return try inner.seal(plaintext, info: info)
    }

    func open(_ sealed: SealedSecret, info: Data) throws -> Data { try inner.open(sealed, info: info) }
    func beginAuthenticationSession() {}
    func endAuthenticationSession() {}
}

extension AppDatabase {
    /// Every text and blob value in every table, concatenated — what an
    /// attacker reading the file would see. Used to prove a plaintext
    /// secret never lands in SQLite.
    func dumpAllValues() throws -> Data {
        try dbQueue.read { db in
            var out = Data()
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            for table in tables {
                for row in try Row.fetchAll(db, sql: "SELECT * FROM \(table)") {
                    for (_, value) in row {
                        switch value.storage {
                        case .string(let s): out.append(Data(s.utf8))
                        case .blob(let d): out.append(d)
                        default: break
                        }
                    }
                }
            }
            return out
        }
    }
}

final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var blob: Data?
    private(set) var writes = 0

    func readMasterKeyBlob() throws -> Data? { lock.withLock { blob } }
    func writeMasterKeyBlob(_ blob: Data) throws { lock.withLock { self.blob = blob; writes += 1 } }
    func deleteMasterKeyBlob() throws { lock.withLock { blob = nil } }
}

func makeItem(_ title: String, kind: SecretKind = .apiKey, service: String? = nil, username: String? = nil,
              url: String? = nil, projectId: String? = nil, favorite: Bool = false, expiresAt: Date? = nil) -> SecretItem {
    SecretItem(kind: kind, title: title, projectId: projectId, service: service, url: url, username: username,
               favorite: favorite, expiresAt: expiresAt)
}
