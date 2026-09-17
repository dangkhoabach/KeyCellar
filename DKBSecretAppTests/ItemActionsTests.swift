import AppKit
import DKBSecretCore
import Foundation
import LocalAuthentication
import Testing
@testable import DKB_Secret

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

    @Test func userCancellationIsRecognisedThroughTheUnderlyingChain() {
        let cancel = LAError(.userCancel)
        #expect(ItemActions.isUserCancellation(cancel))
        let wrapped = NSError(domain: "CryptoTokenKit", code: -2, userInfo: [NSUnderlyingErrorKey: cancel as NSError])
        #expect(ItemActions.isUserCancellation(wrapped))
        #expect(!ItemActions.isUserCancellation(LAError(.biometryLockout)))
        #expect(!ItemActions.isUserCancellation(VaultError.itemNotFound("x")))
    }
}
