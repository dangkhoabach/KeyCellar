import AppKit
import KeyCellarCore
import Foundation
import Testing
@testable import KeyCellar

@MainActor
@Suite struct RotationTests {
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func formPresetFollowsTheKindsDefaultLifetime() throws {
        let database = try AppDatabase.inMemory()
        let vault = SecretVault(database: database, sealer: SoftwareSealer())
        var policy = ExpiryPolicy()
        policy.ttlDays[.login] = 30
        let make = { (kind: SecretKind?) in
            ItemFormModel(mode: .create(kind: kind), vault: vault, items: ItemRepository(dbQueue: database.dbQueue),
                          projects: ProjectRepository(dbQueue: database.dbQueue), expiryPolicy: policy)
        }
        #expect(make(.apiKey).expiryPreset == .days90)
        #expect(make(.login).expiryPreset == .days30)
        #expect(make(.secureNote).expiryPreset == .none)
        let picked = make(nil)
        picked.applyDefaultExpiry(.sshKey)
        #expect(picked.expiryPreset == .days365)
    }

    @Test func rotateKeepsHistoryAndResetsExpiryAndMarkRotatedOnlyMovesExpiry() async throws {
        let database = try AppDatabase.inMemory()
        let vault = SecretVault(database: database, sealer: SoftwareSealer())
        let items = ItemRepository(dbQueue: database.dbQueue)
        let actions = ItemActions(vault: vault, items: items, projects: ProjectRepository(dbQueue: database.dbQueue),
                                  clipboard: ClipboardService(pasteboard: NSPasteboard(name: .init("rot-\(UUID())"))),
                                  navigation: AppNavigationState.shared, expiryPolicy: { ExpiryPolicy() })
        let item = SecretItem(kind: .apiKey, title: "k", expiresAt: Date())
        try await vault.create(item, secrets: ["key": SecretBytes("old")])

        actions.rotate(item, field: "key", newValue: "new")
        await waitUntil { (try? items.blobs(for: item.id).count) == 2 }
        #expect(try await vault.reveal(itemId: item.id, field: "key").string == "new")
        #expect(try await vault.reveal(itemId: item.id, field: "key", slot: 1).string == "old")
        let rotated = try #require(try items.fetch(id: item.id))
        let days = Calendar.current.dateComponents([.day], from: .now, to: try #require(rotated.expiresAt)).day ?? 0
        #expect(days >= 89)

        try await vault.setExpiry(itemId: item.id, to: Date())
        actions.markRotated(item)
        await waitUntil { ((try? items.fetch(id: item.id)?.expiresAt)?.flatMap { $0 } ?? Date()) > Date().addingTimeInterval(80 * 86_400) }
        #expect(try items.blobs(for: item.id).count == 2, "no new history entry")
        #expect(actions.lastError == nil)
    }
}
