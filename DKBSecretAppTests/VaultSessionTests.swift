import AppKit
import DKBSecretCore
import Foundation
import Testing
@testable import DKB_Secret

@MainActor
@Suite struct VaultSessionTests {
    @Test func unlockAndLockDriveTheStateAndTheClipboard() async throws {
        let vault = SecretVault(database: try AppDatabase.inMemory(), sealer: SoftwareSealer())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dkb-secret-session-\(UUID().uuidString)"))
        let clipboard = ClipboardService(pasteboard: pasteboard)
        let session = VaultSession(vault: vault, clipboard: clipboard)
        #expect(session.isLocked)

        await session.unlock()
        #expect(!session.isLocked)
        #expect(session.lastUnlockError == nil)

        clipboard.copy(SecretBytes("x"))
        session.lock()
        #expect(session.isLocked)
        #expect(pasteboard.string(forType: .string) == nil, "locking clears our secret from the clipboard")
    }

    @Test func aFailedUnlockStaysLockedAndReportsWhy() async throws {
        struct Refusing: SecretSealing {
            struct Denied: LocalizedError { var errorDescription: String? { "denied" } }
            let inner = SoftwareSealer()
            func seal(_ p: Data, info: Data) throws -> SealedSecret { try inner.seal(p, info: info) }
            func open(_ s: SealedSecret, info: Data) throws -> Data { try inner.open(s, info: info) }
            func beginAuthenticationSession() throws { throw Denied() }
            func endAuthenticationSession() {}
        }
        let vault = SecretVault(database: try AppDatabase.inMemory(), sealer: Refusing())
        let session = VaultSession(vault: vault, clipboard: ClipboardService(pasteboard: NSPasteboard(name: NSPasteboard.Name("x-\(UUID())"))))
        await session.unlock()
        #expect(session.isLocked)
        #expect(session.lastUnlockError == "denied")
    }
}
