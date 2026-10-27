import AppKit
import KeyCellarCore
import Foundation
import LocalAuthentication
import Testing
@testable import KeyCellar

@Suite struct ItemActionsTests {
    @MainActor
    @Test func permanentDeleteWaitsForConfirmation() async throws {
        let database = try AppDatabase.inMemory()
        let vault = SecretVault(database: database, sealer: SoftwareSealer())
        let items = ItemRepository(dbQueue: database.dbQueue)
        let item = SecretItem(kind: .apiKey, title: "Doomed")
        try await vault.create(item, secrets: ["key": SecretBytes("k")])
        let actions = ItemActions(vault: vault, items: items, projects: ProjectRepository(dbQueue: database.dbQueue),
                                  clipboard: ClipboardService(pasteboard: NSPasteboard(name: NSPasteboard.Name("a-\(UUID())"))),
                                  navigation: AppNavigationState.shared)

        actions.requestPurge([])
        #expect(actions.pendingPurge.isEmpty, "nothing to confirm for an empty selection")
        actions.requestPurge(item)
        #expect(actions.pendingPurge.map(\.id) == [item.id])
        #expect(try items.fetch(id: item.id) != nil, "asking is not deleting")

        actions.confirmPendingPurge()
        #expect(actions.pendingPurge.isEmpty)
        for _ in 0..<50 where try items.fetch(id: item.id) != nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(try items.fetch(id: item.id) == nil)
    }

    // MARK: Recovery codes (fixtures are made up)

    @MainActor
    private struct CodesEnv {
        let items: ItemRepository
        let vault: SecretVault
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("codes-\(UUID())"))
        let actions: ItemActions
        let item: SecretItem

        init(used: [Int: Date] = [:]) async throws {
            let database = try AppDatabase.inMemory()
            vault = SecretVault(database: database, sealer: SoftwareSealer())
            items = ItemRepository(dbQueue: database.dbQueue)
            actions = ItemActions(vault: vault, items: items, projects: ProjectRepository(dbQueue: database.dbQueue),
                                  clipboard: ClipboardService(pasteboard: pasteboard), navigation: AppNavigationState.shared)
            var item = SecretItem(kind: .recoveryCodes, title: "GitHub")
            item.recoveryCodeCount = 3
            item.usedRecoveryCodes = used
            try await vault.create(item, secrets: ["codes": SecretBytes("aaaa-1111\nbbbb-2222\ncccc-3333")])
            self.item = item
        }

        func waitForClipboard() async throws -> String? {
            for _ in 0..<50 where pasteboard.string(forType: .string) == nil { try await Task.sleep(for: .milliseconds(20)) }
            return pasteboard.string(forType: .string)
        }

        func used() throws -> [Int] { Array(try items.fetch(id: item.id)!.usedRecoveryCodes.keys).sorted() }
    }

    @MainActor
    @Test func copyPrimaryCopiesTheFirstUnusedCodeAndMarksIt() async throws {
        let env = try await CodesEnv(used: [1: Date()])
        env.actions.copyPrimary(env.item)
        #expect(try await env.waitForClipboard() == "bbbb-2222")
        for _ in 0..<50 where try env.used() != [1, 2] { try await Task.sleep(for: .milliseconds(20)) }
        #expect(try env.used() == [1, 2])
    }

    @MainActor
    @Test func copyingAChosenCodeMarksThatOne() async throws {
        let env = try await CodesEnv()
        env.actions.copyRecoveryCode(env.item, index: 3)
        #expect(try await env.waitForClipboard() == "cccc-3333")
        for _ in 0..<50 where try env.used() != [3] { try await Task.sleep(for: .milliseconds(20)) }
        #expect(try env.used() == [3])
    }

    @MainActor
    @Test func noUnusedCodesLeftIsReportedWithoutRevealing() async throws {
        let env = try await CodesEnv(used: [1: Date(), 2: Date(), 3: Date()])
        env.actions.copyPrimary(env.item)
        #expect(env.actions.lastError == String(localized: "No unused codes left.", bundle: AppLocale.bundle))
        try await Task.sleep(for: .milliseconds(100))
        #expect(env.pasteboard.string(forType: .string) == nil)
    }

    @MainActor
    @Test func aTrashedSetIsNotCopied() async throws {
        let env = try await CodesEnv()
        try await env.vault.moveToTrash(itemId: env.item.id)
        env.actions.copyPrimary(env.item)
        try await Task.sleep(for: .milliseconds(100))
        #expect(env.pasteboard.string(forType: .string) == nil)
        #expect(try env.used().isEmpty)
    }

    @MainActor
    @Test func tickingAndUntickingKeepsTheFirstDate() async throws {
        let first = Date(timeIntervalSince1970: 1_790_000_000)
        let env = try await CodesEnv(used: [2: first])
        env.actions.setRecoveryCode(env.item, index: 2, used: true)
        #expect(try env.items.fetch(id: env.item.id)?.usedRecoveryCodes[2].map { Calendar.current.isDate($0, inSameDayAs: first) } == true)
        env.actions.setRecoveryCode(env.item, index: 3, used: true)
        env.actions.setRecoveryCode(env.item, index: 2, used: false)
        #expect(try env.used() == [3])
    }

    @MainActor
    @Test func replaceCodesOpensTheFormInReplaceMode() async throws {
        let env = try await CodesEnv()
        env.actions.replaceCodes(env.item)
        #expect(env.actions.form?.replacingCodes == true)
        #expect(env.actions.form?.isEditing == true)
    }

    @Test func userCancellationIsRecognisedThroughTheUnderlyingChain() {
        let cancel = LAError(.userCancel)
        #expect(ItemActions.isUserCancellation(cancel))
        let wrapped = NSError(domain: "CryptoTokenKit", code: -2, userInfo: [NSUnderlyingErrorKey: cancel as NSError])
        #expect(ItemActions.isUserCancellation(wrapped))
        #expect(!ItemActions.isUserCancellation(LAError(.biometryLockout)))
        #expect(!ItemActions.isUserCancellation(VaultError.itemNotFound("x")))
    }
}
